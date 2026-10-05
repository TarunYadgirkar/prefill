import { isPlaceholder } from "./choices";
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
  hasActivation?: () => boolean;
}

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
const NOT_ASKED = /high school/iu;
const TYPED_INPUTS: ReadonlySet<string> = new Set(["text", "number", "month", "date"]);
const MAX_INSPECTED = 300;
const TOAST_MS = 8_000;
const EDGE = 16;

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

function radioAnswers(elements: readonly FieldElement[], touched: WeakSet<Element>): [string, string][] {
  const checked = elements.filter(
    (element): element is HTMLInputElement =>
      element.localName === "input" && (element as HTMLInputElement).type === "radio" && (element as HTMLInputElement).checked,
  );
  return checked
    .filter((radio) => touched.has(radio) && radio.name !== "")
    .map((radio) => {
      const group = elements.filter(
        (element): element is HTMLInputElement => element.localName === "input" && (element as HTMLInputElement).name === radio.name,
      );
      return [questionOf(group), radio.labels?.[0]?.textContent.trim() ?? ""];
    });
}

// The answers in a form the person set themselves, one per question, first one first.
export function collectAnswers(scope: ParentNode, touched: WeakSet<Element>): Answer[] {
  const elements = fieldElements(scope, MAX_INSPECTED);
  const typed: [string, string][] = elements
    .filter((element) => touched.has(element) && isLearnable(element))
    .map((element) => [fieldText(element), shownValue(element)]);
  const answers = new Map<JobQuestion, string>();
  for (const [text, value] of [...typed, ...radioAnswers(elements, touched)]) {
    const question = jobQuestion(text);
    const fits = value !== "" && value.length <= LIMITS.customValue && !HIDDEN_CHARACTERS.test(value);
    if (question !== undefined && fits && !answers.has(question)) answers.set(question, value);
  }
  return [...answers].slice(0, LIMITS.answers).map(([question, value]) => ({ question, value }));
}

// "Saved 3 answers" with Undo, at the bottom of the page, in a closed shadow root like the
// fill pill so the page can't press it.
function showSaved(doc: Document, win: Window, saved: number, undo: () => void, isUserEvent: (event: Event) => boolean): void {
  const host = doc.createElement("prefill-saved");
  const root = host.attachShadow({ mode: "closed" });
  const style = doc.createElement("style");
  style.textContent = PILL_STYLE;
  const pill = doc.createElement("div");
  pill.className = "pill";
  const status = doc.createElement("span");
  status.className = "status";
  status.setAttribute("role", "status");
  status.textContent = `Saved ${String(saved)} ${saved === 1 ? "answer" : "answers"}`;
  const button = doc.createElement("button");
  button.className = "main";
  button.textContent = "Undo";
  pill.append(status, button);
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
  button.addEventListener("click", (event) => {
    if (!isUserEvent(event)) return;
    clearTimeout(timer);
    host.remove();
    undo();
  });
}

export function installLearn(doc: Document, win: Window, options: LearnOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const hasActivation =
    options.hasActivation ?? (() => (win.navigator as Partial<Navigator>).userActivation?.isActive === true);
  const touched = new WeakSet<Element>();

  const touch = (event: Event): void => {
    const target = eventOrigin(event);
    if (isUserEvent(event) && isFieldElement(target)) touched.add(target);
  };

  const undo = (): void => {
    options.send({ type: "answers", host: options.host(), action: "undo", answers: [] }).catch(() => undefined);
  };

  const onSubmit = (event: Event): void => {
    if (!isUserEvent(event) || !hasActivation() || !(event.target instanceof HTMLFormElement)) return;
    const answers = collectAnswers(event.target, touched);
    if (answers.length === 0) return;
    void options
      .send({ type: "answers", host: options.host(), action: "learn", answers })
      .then((raw) => {
        const reply = parseExtensionResponse(raw);
        if (reply?.type === "answersResult" && reply.saved > 0) showSaved(doc, win, reply.saved, undo, isUserEvent);
      })
      .catch(() => undefined);
  };

  doc.addEventListener("input", touch, true);
  doc.addEventListener("change", touch, true);
  doc.addEventListener("submit", onSubmit, true);
  return () => {
    doc.removeEventListener("input", touch, true);
    doc.removeEventListener("change", touch, true);
    doc.removeEventListener("submit", onSubmit, true);
  };
}
