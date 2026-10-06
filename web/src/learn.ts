import { isPlaceholder } from "./choices";
import { submitControl, TOUCH_EVENTS, touchedField } from "./capture";
import { classify, isSignIn } from "./classify";
import { fieldText } from "./custom";
import { isDemographic } from "./demographics";
import { eventOrigin, fieldElements, isFieldElement, isRendered, placeFixed } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { questionOf } from "./fill";
import { PILL_STYLE, setStyles } from "./fillChip";
import {
  HIDDEN_CHARACTERS,
  LIMITS,
  parseExtensionResponse,
  type AnswersRequest,
  type AnswersResult,
  type JobQuestion,
} from "./messages";

// Learn as the person applies: when they submit a job application, their answers to the
// questions every application asks (school, major, sponsorship and the like) go to the app,
// which saves the new ones as custom answers. A small pill then says "Saved 3 answers" with
// Undo. Only answers the person typed or picked themselves are read, never demographic ones.

export interface LearnOptions {
  host: () => string;
  send: (request: AnswersRequest) => Promise<unknown>;
  isUserEvent?: (event: Event) => boolean;
  now?: () => number;
}

// What a field asked and held when the person last changed it. A page that relabels the
// field or swaps its value afterwards no longer matches, so nothing of the page's is saved.
interface Snapshot {
  text: string;
  value: string;
}
type Touched = WeakMap<Element, Snapshot>;

type Answer = AnswersRequest["answers"][number];

// The first pattern that matches wins, so "authorized to work without sponsorship" is the
// authorization question.
const QUESTIONS: readonly (readonly [JobQuestion, RegExp])[] = [
  ["authorization", /authori[sz]ed to work|work authori[sz]ation|legally (?:authori[sz]ed|eligible|permitted)|eligible to work/iu],
  ["sponsorship", /sponsor/iu],
  ["heard", /how did you (?:hear|find)|hear about/iu],
  ["gpa", /\bgpa\b|grade point/iu],
  ["graduation", /graduation|grad (?:date|year)/iu],
  ["major", /\bmajor\b|field of study|discipline/iu],
  ["degree", /\bdegree\b/iu],
  ["school", /\bschool\b|university|college/iu],
];
const NOT_ASKED = /high school|\bid\b|\bnumber\b|e-?mail/iu;
// A submit counts only this soon after the person pressed the form's submit button or Enter in it.
const SUBMIT_MS = 1_000;
const SEPARATOR = "·";
const TYPED_INPUTS: ReadonlySet<string> = new Set(["text", "number", "month", "date"]);
const MAX_INSPECTED = 300;
const TOAST_MS = 8_000;
const EDGE = 16;

const answersNoun = (count: number): string => (count === 1 ? "answer" : "answers");

// What the pill says after a submit: "Saved 2 answers", "Updated your answer", or both.
export function savedText({ saved, updated }: Pick<AnswersResult, "saved" | "updated">): string {
  const changed = updated === 1 ? "your answer" : `${String(updated)} answers`;
  if (saved === 0) return `Updated ${changed}`;
  const added = `Saved ${String(saved)} ${answersNoun(saved)}`;
  return updated === 0 ? added : `${added} and updated ${String(updated)}`;
}

export function jobQuestion(text: string): JobQuestion | undefined {
  if (isDemographic(text) || NOT_ASKED.test(text)) return undefined;
  return QUESTIONS.find(([, pattern]) => pattern.test(text))?.[0];
}

function shownValue(element: FieldElement): string {
  if (element.localName !== "select") return element.value.trim();
  const chosen = (element as HTMLSelectElement).selectedOptions[0];
  return chosen === undefined || isPlaceholder({ text: chosen.text, value: chosen.value }) ? "" : chosen.text.trim();
}

function isLearnable(element: FieldElement): boolean {
  if (!isRendered(element) || isSignIn(element) || classify(element).kind !== "ignored") return false;
  if (element.localName === "select") return !(element as HTMLSelectElement).multiple;
  return element.localName === "input" && TYPED_INPUTS.has((element as HTMLInputElement).type.toLowerCase());
}

function radioGroup(elements: readonly FieldElement[], radio: HTMLInputElement): HTMLInputElement[] {
  return elements.filter(
    (element): element is HTMLInputElement =>
      element.localName === "input" && (element as HTMLInputElement).type === "radio" && (element as HTMLInputElement).name === radio.name,
  );
}

function readRadio(radio: HTMLInputElement, elements: readonly FieldElement[]): Snapshot | undefined {
  if (!radio.checked || radio.name === "") return undefined;
  return { text: questionOf(radioGroup(elements, radio)), value: radio.labels?.[0]?.textContent.trim() ?? "" };
}

// The question and answer a field shows right now, or nothing for one Prefill doesn't learn from.
function read(element: FieldElement, elements: readonly FieldElement[]): Snapshot | undefined {
  if (element.localName === "input" && (element as HTMLInputElement).type === "radio")
    return readRadio(element as HTMLInputElement, elements);
  return isLearnable(element) ? { text: fieldText(element), value: shownValue(element) } : undefined;
}

function fits(value: string): boolean {
  return value !== "" && value.length <= LIMITS.customValue && !HIDDEN_CHARACTERS.test(value) && !value.includes(SEPARATOR);
}

// What the field still reads, when that is exactly what the person left in it.
function unchanged(element: FieldElement, elements: readonly FieldElement[], touched: Touched): Snapshot | undefined {
  const then = touched.get(element);
  if (then === undefined) return undefined;
  const now = read(element, elements);
  return now?.text === then.text && now.value === then.value ? now : undefined;
}

// The answers in a form the person set themselves and that still read as they left them,
// one per question, first one first.
export function collectAnswers(scope: ParentNode, touched: Touched): Answer[] {
  const elements = fieldElements(scope, MAX_INSPECTED);
  const answers = new Map<JobQuestion, string>();
  for (const element of elements) {
    const kept = unchanged(element, elements, touched);
    const question = kept === undefined ? undefined : jobQuestion(kept.text);
    if (kept === undefined || question === undefined || !fits(kept.value) || answers.has(question)) continue;
    answers.set(question, kept.value);
  }
  return [...answers].slice(0, LIMITS.answers).map(([question, value]) => ({ question, value }));
}

// "Saved 3 answers" with Undo, at the bottom of the page, in a closed shadow root like the
// fill pill so the page can't press it.
interface PillAction {
  label: string;
  run: () => void;
  isUserEvent: (event: Event) => boolean;
}

function showPill(doc: Document, win: Window, text: string, action?: PillAction): void {
  const host = doc.createElement("prefill-saved");
  const root = host.attachShadow({ mode: "closed" });
  const style = doc.createElement("style");
  style.textContent = PILL_STYLE;
  const pill = doc.createElement("div");
  pill.className = "pill";
  const status = doc.createElement("span");
  status.className = "status";
  status.setAttribute("role", "status");
  status.textContent = text;
  pill.append(status);
  root.append(style, pill);
  host.setAttribute("popover", "manual");
  setStyles(host, { position: "fixed", margin: "0", padding: "0", border: "0", background: "transparent", inset: "auto", "z-index": "2147483647", overflow: "visible" });
  doc.documentElement.append(host);
  try {
    host.showPopover();
  } catch {
    // Popovers unsupported: the fixed position still shows it.
  }
  const size = host.getBoundingClientRect();
  const height = win.visualViewport?.height ?? win.innerHeight;
  placeFixed(host, Math.max(EDGE, (win.innerWidth - size.width) / 2), height - size.height - EDGE);
  const timer = setTimeout(() => {
    host.remove();
  }, TOAST_MS);
  if (action === undefined) return;
  const button = doc.createElement("button");
  button.className = "main";
  button.textContent = action.label;
  pill.append(button);
  button.addEventListener("click", (event) => {
    if (!action.isUserEvent(event)) return;
    clearTimeout(timer);
    host.remove();
    action.run();
  });
}

// Enter submits from a field, but starts a new line in a text area.
function enterForm(event: KeyboardEvent, target: Element): HTMLFormElement | undefined {
  if (event.key !== "Enter" || !isFieldElement(target) || target.localName === "textarea") return undefined;
  return (target as HTMLInputElement).form ?? undefined;
}

// The form a trusted click on a submit control or Enter key would submit.
function formOf(event: Event): HTMLFormElement | undefined {
  const target = eventOrigin(event);
  if (!(target instanceof Element)) return undefined;
  if (event.type === "keydown") return enterForm(event as KeyboardEvent, target);
  return submitControl(target)?.form ?? undefined;
}

export function installLearn(doc: Document, win: Window, options: LearnOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const now = options.now ?? (() => Date.now());
  const touched: Touched = new WeakMap();
  // A page script can call requestSubmit() and get a trusted submit event, so only a submit
  // that follows the person's own press on that form counts.
  let pressed: { form: HTMLFormElement; at: number } | undefined;

  // execCommand makes trusted input events too, so only a field the person pressed,
  // typed or composed in counts as theirs.
  const handled = new WeakSet<FieldElement>();
  const handle = (event: Event): void => {
    const field = isUserEvent(event) ? touchedField(event) : undefined;
    if (field !== undefined) handled.add(field);
  };

  const touch = (event: Event): void => {
    const target = eventOrigin(event);
    if (!isUserEvent(event) || !isFieldElement(target) || !handled.has(target)) return;
    const scope = (target as HTMLInputElement).form ?? doc;
    const snapshot = read(target, fieldElements(scope, MAX_INSPECTED));
    if (snapshot === undefined) touched.delete(target);
    else touched.set(target, snapshot);
  };

  const press = (event: Event): void => {
    const form = isUserEvent(event) ? formOf(event) : undefined;
    if (form !== undefined) pressed = { form, at: now() };
  };

  // The answers are already on the card, so a failed undo must say so rather than vanish.
  const undo = (): void => {
    const failed = (): void => {
      showPill(doc, win, "Couldn’t undo. Remove the answers in Contacts.");
    };
    options
      .send({ type: "answers", host: options.host(), action: "undo", answers: [] })
      .then((raw) => {
        const reply = parseExtensionResponse(raw);
        if (reply?.type !== "answersResult" || reply.saved === 0) failed();
      })
      .catch(failed);
  };

  const onSubmit = (event: Event): void => {
    const isPressed = pressed !== undefined && pressed.form === event.target && now() - pressed.at < SUBMIT_MS;
    pressed = undefined;
    if (!isUserEvent(event) || !isPressed || !(event.target instanceof HTMLFormElement)) return;
    const answers = collectAnswers(event.target, touched);
    if (answers.length === 0) return;
    void options
      .send({ type: "answers", host: options.host(), action: "learn", answers })
      .then((raw) => {
        const reply = parseExtensionResponse(raw);
        if (reply?.type !== "answersResult" || reply.saved + reply.updated === 0) return;
        showPill(doc, win, savedText(reply), { label: "Undo", run: undo, isUserEvent });
      })
      .catch(() => undefined);
  };

  for (const type of TOUCH_EVENTS) doc.addEventListener(type, handle, true);
  doc.addEventListener("input", touch, true);
  doc.addEventListener("change", touch, true);
  doc.addEventListener("click", press, true);
  doc.addEventListener("keydown", press, true);
  doc.addEventListener("submit", onSubmit, true);
  return () => {
    for (const type of TOUCH_EVENTS) doc.removeEventListener(type, handle, true);
    doc.removeEventListener("input", touch, true);
    doc.removeEventListener("change", touch, true);
    doc.removeEventListener("click", press, true);
    doc.removeEventListener("keydown", press, true);
    doc.removeEventListener("submit", onSubmit, true);
  };
}
