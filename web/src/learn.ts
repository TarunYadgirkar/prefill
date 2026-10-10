import { isPlaceholder } from "./choices";
import { submitControl, TOUCH_EVENTS, touchedField } from "./capture";
import { classify, isSignIn } from "./classify";
import { fieldText, joinFieldText } from "./custom";
import { isDemographic } from "./demographics";
import { eventOrigin, fieldElements, isFieldElement, isRendered, placeFixed } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { filledAnswer, questionOf } from "./fill";
import { labelText } from "./dom";
import { PILL_STYLE, setStyles } from "./fillChip";
import {
  HIDDEN_CHARACTERS,
  LIMITS,
  parseExtensionResponse,
  type AnswersRequest,
  type AnswersResult,
  type JobQuestion,
} from "./messages";
import { workQuestion } from "./workQuestion";

// Learn as the person applies: when they submit a job application, their answers to the
// questions every application asks (school, major, sponsorship and the like) go to the app,
// which saves the new ones as custom answers. A small pill then says "Saved 3 answers" with
// Undo. Only answers the person typed or picked themselves are read, never demographic ones.

export interface LearnOptions {
  host: () => string;
  send: (request: AnswersRequest) => Promise<unknown>;
  isUserEvent?: (event: Event) => boolean;
  now?: () => number;
  // Every form the person sent with their own press, learned from or not.
  onSubmitted?: (form: HTMLFormElement) => void;
}

// What a field asked and held when the person last changed it. A page that relabels the
// field or swaps its value afterwards no longer matches, so nothing of the page's is saved.
interface Snapshot {
  text: string;
  value: string;
}
type Touched = WeakMap<Element, Snapshot>;

type Answer = AnswersRequest["answers"][number];

// The first pattern that matches wins. Sponsorship and authorization are told apart first
// (`workQuestion`).
const QUESTIONS: readonly (readonly [JobQuestion, RegExp])[] = [
  ["authorization", /authori[sz]ed to work|work authori[sz]ation|legally (?:authori[sz]ed|eligible|permitted|able to work)|eligible to work/iu],
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

// What the pill says after a submit: "Saved 2 answers", "Updated your answer to School",
// "Updated 2 answers", or both. Naming the question shows which answer a page changed.
export function savedText({ saved, updated }: Pick<AnswersResult, "saved" | "updated">): string {
  const [only] = updated;
  const changed = updated.length === 1 && only !== undefined ? `your answer to ${only}` : `${String(updated.length)} answers`;
  if (saved === 0) return `Updated ${changed}`;
  const added = `Saved ${String(saved)} ${answersNoun(saved)}`;
  return updated.length === 0 ? added : `${added} and updated ${String(updated.length)}`;
}

// What the pill asks after a submit that changed answers Prefill filled: "Saved 1 answer ·
// Changed your answer to School", then "Update everywhere" or "Just here".
export function askText(saved: number, ask: readonly string[]): string {
  const [only] = ask;
  const changed = ask.length === 1 && only !== undefined ? `your answer to ${only}` : `${String(ask.length)} answers`;
  const prefix = saved === 0 ? "" : `Saved ${String(saved)} ${answersNoun(saved)} · `;
  return `${prefix}You changed ${changed}`;
}

export function jobQuestion(text: string): JobQuestion | undefined {
  if (isDemographic(text) || NOT_ASKED.test(text)) return undefined;
  const work = workQuestion(text);
  // One answer can't say both, so a question that asks both isn't learned.
  if (work === "both") return undefined;
  return work ?? QUESTIONS.find(([, pattern]) => pattern.test(text))?.[0];
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

// The texts of a select's or radio group's options, which tell the app what the answer was
// chosen from. A text box has none.
function optionTexts(element: FieldElement, elements: readonly FieldElement[]): string[] {
  const radio = element.localName === "input" && (element as HTMLInputElement).type === "radio";
  const texts =
    element.localName === "select"
      ? [...(element as HTMLSelectElement).options].filter((option) => !isPlaceholder(optionOf(option))).map((option) => option.text)
      : radio ? radioGroup(elements, element as HTMLInputElement).map(labelText) : [];
  return texts.map((text) => joinFieldText([text], LIMITS.text)).filter(Boolean).slice(0, LIMITS.answerOptions);
}

const optionOf = (option: HTMLOptionElement) => ({ text: option.text, value: option.value });

// Whether the person changed an answer Prefill filled in this field before submitting.
function fillChange(element: FieldElement, value: string): { changedFill?: true } {
  const filled = filledAnswer(element);
  return filled !== undefined && filled !== value ? { changedFill: true } : {};
}

// What the person answered in a field and still left there, with the question and options.
function answerIn(element: FieldElement, elements: readonly FieldElement[], touched: Touched): Answer | undefined {
  const kept = unchanged(element, elements, touched);
  const question = kept === undefined ? undefined : jobQuestion(kept.text);
  if (kept === undefined || question === undefined || !fits(kept.value)) return undefined;
  const options = optionTexts(element, elements);
  return { question, value: kept.value, text: kept.text, ...(options.length === 0 ? {} : { options }), ...fillChange(element, kept.value) };
}

// The answers in a form the person set themselves and that still read as they left them,
// one per question as the page words it, first one first. The app reads what each applies
// to ("...in Canada?") from those words.
export function collectAnswers(scope: ParentNode, touched: Touched): Answer[] {
  const elements = fieldElements(scope, MAX_INSPECTED);
  const answers = new Map<string, Answer>();
  for (const element of elements) {
    const answer = answerIn(element, elements, touched);
    const key = `${answer?.question ?? ""} ${answer?.text ?? ""}`;
    if (answer !== undefined && !answers.has(key)) answers.set(key, answer);
  }
  return [...answers.values()].slice(0, LIMITS.answers);
}

// "Saved 3 answers" with Undo, at the bottom of the page, in a closed shadow root like the
// fill pill so the page can't press it. Each button acts only on the person's own click.
interface PillAction {
  label: string;
  run: () => void;
}

function showPill(
  doc: Document,
  win: Window,
  text: string,
  actions: readonly PillAction[] = [],
  isUserEvent: (event: Event) => boolean = (event) => event.isTrusted,
): void {
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
  for (const action of actions) {
    const button = doc.createElement("button");
    button.className = "main";
    button.textContent = action.label;
    pill.append(button);
    button.addEventListener("click", (event) => {
      if (!isUserEvent(event)) return;
      clearTimeout(timer);
      host.remove();
      action.run();
    });
  }
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
      showPill(doc, win, "Couldn’t undo. Remove the answers in Contacts.", [], isUserEvent);
    };
    options
      .send({ type: "answers", host: options.host(), action: "undo", answers: [] })
      .then((raw) => {
        const reply = parseExtensionResponse(raw);
        if (reply?.type !== "answersResult" || reply.saved === 0) failed();
      })
      .catch(failed);
  };

  const send = (action: AnswersRequest["action"], answers: readonly Answer[]): Promise<AnswersResult | undefined> =>
    options
      .send({ type: "answers", host: options.host(), action, answers: [...answers] })
      .then((raw) => {
        const reply = parseExtensionResponse(raw);
        return reply?.type === "answersResult" ? reply : undefined;
      })
      .catch(() => undefined);

  const pill = (text: string, actions: readonly PillAction[] = []): void => {
    showPill(doc, win, text, actions, isUserEvent);
  };
  const undoAction: PillAction = { label: "Undo", run: undo };

  // "Update everywhere" replaces the saved answers through the app's usual guards, with Undo;
  // "Just here" keeps the saved ones and notes what the person used on this site.
  const ask = (first: AnswersResult, changed: readonly Answer[]): void => {
    const earlier = first.saved > 0 ? [undoAction] : [];
    const everywhere = (): void => {
      void send("update", changed).then((reply) => {
        if (reply === undefined || reply.updated.length === 0) pill("Couldn’t update it. Edit the answer in Prefill.", earlier);
        else pill(savedText({ saved: first.saved, updated: reply.updated }), [undoAction]);
      });
    };
    const justHere = (): void => {
      void send("keepHere", changed).then((reply) => {
        pill(reply === undefined || reply.saved === 0 ? "Couldn’t keep it for this site." : "Kept for this site only", earlier);
      });
    };
    pill(askText(first.saved, first.ask ?? []), [
      { label: "Update everywhere", run: everywhere },
      { label: "Just here", run: justHere },
    ]);
  };

  const onLearned = (reply: AnswersResult | undefined, answers: readonly Answer[]): void => {
    if (reply === undefined) return;
    if ((reply.ask ?? []).length > 0) ask(reply, answers.filter((answer) => answer.changedFill === true));
    else if (reply.saved + reply.updated.length > 0) pill(savedText(reply), [undoAction]);
  };

  const onSubmit = (event: Event): void => {
    const isPressed = pressed !== undefined && pressed.form === event.target && now() - pressed.at < SUBMIT_MS;
    pressed = undefined;
    if (!isUserEvent(event) || !isPressed || !(event.target instanceof HTMLFormElement)) return;
    options.onSubmitted?.(event.target);
    const answers = collectAnswers(event.target, touched);
    if (answers.length === 0) return;
    void send("learn", answers).then((reply) => {
      onLearned(reply, answers);
    });
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
