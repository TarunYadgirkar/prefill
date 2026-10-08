import { parseAutocomplete } from "./autocomplete";
import { classify, isSignIn } from "./classify";
import type { Attach, Choice, TextField } from "./dropdown";
import {
  eventOrigin,
  hasOwnList,
  fieldElements,
  isFieldElement,
  inferredLabel,
  nameTexts,
  placeholderText,
} from "./dom";
import type { FieldElement } from "./fieldTypes";
import { onEmptied, trackGestures } from "./gesture";
import { reportPick } from "./picks";
import { DRAFT_DETAIL, GUESS_DETAIL, noAnswerFor, whyDetail } from "./why";
import {
  HIDDEN_CHARACTERS,
  LIMITS,
  parseExtensionResponse,
  type CustomSuggestionsRequest,
  type CustomSuggestionsResult,
  type PickedRequest,
} from "./messages";

export interface CustomOptions {
  host: () => string;
  send: (request: CustomSuggestionsRequest | PickedRequest) => Promise<unknown>;
  // Only events the browser made count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
  // Draws Prefill's list under the field (showDropdown in pages).
  attach: Attach;
  // Fields another of Prefill's lists already serves, such as ones a one-tap fill filled.
  skip?: (element: FieldElement) => boolean;
  textAreas?: boolean;
}

const MAX_INSPECTED = 200;
export const CUSTOM_DETAIL = "Custom field";
// Plain text inputs, and text areas when the caller asks; a search box never wants a saved
// answer.
const LIST_INPUTS: ReadonlySet<string> = new Set(["text"]);
const ALL_HIDDEN = new RegExp(HIDDEN_CHARACTERS.source, "gu");

type CustomField = CustomSuggestionsResult["fields"][number];

// A value only offered, never filled: picking it is worth remembering for the question.
function offeredOnly(value: string, detail: string, onPick: (value: string) => void): Choice {
  return { value, detail, tone: "guess", onPick: () => { onPick(value); } };
}

// "Draft · Cover letter": which draft, when the person keeps more than one.
const draftDetail = (label: string | undefined): string => (label === undefined ? DRAFT_DETAIL : `${DRAFT_DETAIL} · ${label}`);

// The field's answers, then answers kept for another scope and the model's guesses, which
// are only offered, then drafts, then a note when the person has no answer for the question's
// scope. A pick of an answer that wasn't first, or of a suggestion or guess, is worth
// remembering; a draft is the person's to edit each time, so its pick isn't.
export function customChoices(
  field: CustomField | undefined,
  onPick: (value: string) => void,
): Choice[] {
  if (field === undefined) return [];
  const answers = field.values.map((offered, index) => ({
    value: offered.value,
    detail: whyDetail(offered, offered.label ?? CUSTOM_DETAIL),
    ...(index === 0 ? {} : { onPick: () => { onPick(offered.value); } }),
  }));
  // The label says which scope the answer is for: "Work authorization (US)".
  // "Used here" for the answer the person kept on this site in place of the saved one.
  const suggested = (field.suggested ?? []).map((offered) => offeredOnly(offered.value, whyDetail(offered, offered.label ?? CUSTOM_DETAIL), onPick));
  const guesses = (field.guesses ?? []).map((value) => offeredOnly(value, GUESS_DETAIL, onPick));
  const drafts = (field.drafts ?? []).map((offered): Choice => ({ value: offered.value, detail: draftDetail(offered.label), tone: "draft" }));
  const note: Choice[] = field.noAnswerFor === undefined ? [] : [{ value: noAnswerFor(field.noAnswerFor), detail: "", tone: "note" }];
  return [...answers, ...suggested, ...guesses, ...drafts, ...note];
}

// What a one-tap fill or a filled field's list may use: the person's own answers for the question.
export const fillable = (choices: readonly Choice[]): Choice[] => choices.filter((choice) => choice.tone === undefined);

// A text area is a message or an essay, not a short question, so it gets no guess.
function offeredFor(element: TextField, choices: readonly Choice[] | undefined): readonly Choice[] | undefined {
  return element.localName === "textarea" ? choices?.filter((choice) => choice.tone !== "guess") : choices;
}

// A field only gets custom values when nothing else claims it: no contact or link meaning,
// no autofill token, not sensitive, and not on a sign-in form.
export function isCustomCandidate(
  element: FieldElement,
  textAreas = false,
): element is TextField {
  const isTextArea = textAreas && element.localName === "textarea";
  if (
    !isTextArea &&
    (element.localName !== "input" ||
      !LIST_INPUTS.has((element as HTMLInputElement).type.toLowerCase()))
  )
    return false;
  if (
    parseAutocomplete(element.getAttribute("autocomplete")) !== undefined ||
    isSignIn(element)
  )
    return false;
  return classify(element).kind === "ignored";
}

// What the app matches against the person's custom fields: label first, then placeholder,
// then name and id, cut to the message limit without splitting a character.
export function fieldText(element: FieldElement): string {
  return joinFieldText([
    inferredLabel(element),
    placeholderText(element),
    ...nameTexts(element),
  ]);
}

export function joinFieldText(parts: readonly string[], max: number = LIMITS.fieldText): string {
  const text = parts
    .join(" ")
    .replace(ALL_HIDDEN, " ")
    .replace(/\p{Cs}/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
  return text.slice(0, max).replace(/[\uD800-\uDBFF]$/u, "");
}

const HEADINGS = "h1, h2, h3, h4, h5, h6, [role=heading], legend";

// The last heading before the field in page order ("Education", "Work eligibility"), which
// tells the on-device model what a short question is about.
export function headingOf(element: Element): string | undefined {
  let found: Element | undefined;
  for (const heading of element.ownerDocument.querySelectorAll(HEADINGS)) {
    if ((heading.compareDocumentPosition(element) & Node.DOCUMENT_POSITION_FOLLOWING) === 0) break;
    found = heading;
  }
  const text = joinFieldText([found?.textContent ?? ""], LIMITS.text);
  return text === "" ? undefined : text;
}

type AskedField = CustomSuggestionsRequest["fields"][number];

// A question as the app's request carries it: its words, and its heading when it has one.
export function askedField(text: string, element: Element, options: readonly string[] = []): AskedField {
  const heading = headingOf(element);
  return {
    text,
    ...(heading === undefined ? {} : { heading }),
    ...(options.length === 0 ? {} : { options: options.slice(0, LIMITS.answerOptions) }),
  };
}

// Offers the person's custom field values ("School" = "UC Berkeley") on fields whose words
// match, in Prefill's own list under the field. The matches are fetched when the page loads,
// so the list is ready as the field takes focus, and again on each focus, which covers
// fields a page adds later. The list goes away when the field loses focus.
export function installCustom(
  doc: Document,
  options: CustomOptions,
): () => void {
  const isUserEvent =
    options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const attach = options.attach;
  // Prefill's own list would sit on top of the page's, so it skips fields that have one.
  const isTaken = (element: FieldElement): boolean =>
    options.skip?.(element) === true || hasOwnList(element);
  const isCandidate = (element: FieldElement): element is TextField =>
    isCustomCandidate(element, options.textAreas);
  const gestures = trackGestures(doc, isUserEvent);
  const known = new Map<string, readonly Choice[]>();
  const asked = new Map<string, AskedField>();
  let detach: (() => void) | undefined;
  let focused: { element: TextField; text: string } | undefined;

  const clear = (): void => {
    detach?.();
    detach = undefined;
    focused = undefined;
    shown = 0;
  };

  // How many rows the open list shows, so a reply that brings more (drafts come only with
  // the focused field's own request) redraws it.
  let shown = 0;
  const offer = (): void => {
    const values = focused === undefined ? undefined : offeredFor(focused.element, known.get(focused.text));
    if (
      focused === undefined ||
      detach !== undefined ||
      values === undefined ||
      values.length === 0
    )
      return;
    shown = values.length;
    detach = attach(focused.element, [...values]);
  };

  const redraw = (texts: readonly string[]): void => {
    const now = focused === undefined ? undefined : offeredFor(focused.element, known.get(focused.text));
    if (focused === undefined || !texts.includes(focused.text) || (now?.length ?? 0) <= shown) return;
    detach?.();
    detach = undefined;
    offer();
  };

  const fetchValues = (texts: readonly string[]): void => {
    if (texts.length === 0) return;
    options
      .send({
        type: "customSuggestions",
        host: options.host(),
        fields: texts.map((text) => asked.get(text) ?? { text }),
      })
      .then((reply) => {
        const response = parseExtensionResponse(reply);
        if (
          response?.type !== "customSuggestionsResult" ||
          response.fields.length !== texts.length
        )
          return;
        texts.forEach((text, index) => {
          known.set(text, customChoices(response.fields[index], (value) => {
            picked(text, value);
          }));
        });
        if (detach === undefined) offer();
        else redraw(texts);
      })
      .catch(() => undefined);
  };

  const picked = (text: string, value: string): void => {
    reportPick(
      options.send,
      { type: "picked", host: options.host(), kind: "custom", value, question: text },
      () => {
        fetchValues([text]);
      },
    );
  };

  const prefetch = (): void => {
    const texts = fieldElements(doc, MAX_INSPECTED)
      .filter(isCandidate)
      .map((element) => {
        const text = fieldText(element);
        if (!asked.has(text)) asked.set(text, askedField(text, element));
        return text;
      });
    fetchValues(
      [...new Set(texts)].filter(Boolean).slice(0, LIMITS.pageFields),
    );
  };

  const show = (target: FieldElement): void => {
    if (detach !== undefined || isTaken(target) || !isCandidate(target)) return;
    const text = fieldText(target);
    if (text === "") return;
    if (!asked.has(text)) asked.set(text, askedField(text, target));
    clear();
    focused = { element: target, text };
    offer();
    fetchValues([text]);
  };

  // The field the person tapped or tabbed into, even one Prefill filled, so emptying it
  // brings its list back.
  let armed: FieldElement | undefined;
  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || !isCandidate(target) || !gestures.allows(target)) return;
    armed = target;
    clear();
    show(target);
  };

  const onBlur = (event: Event): void => {
    const target = eventOrigin(event);
    if (target === armed) armed = undefined;
    if (target === focused?.element) clear();
  };
  const stopEmptied = onEmptied(doc, isUserEvent, () => armed, show);

  if (doc.readyState === "loading")
    doc.addEventListener("DOMContentLoaded", prefetch, { once: true });
  else prefetch();
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    gestures.stop();
    stopEmptied();
    doc.removeEventListener("DOMContentLoaded", prefetch);
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
