import { parseAutocomplete } from "./autocomplete";
import { classify, isSignIn } from "./classify";
import { attachDatalist } from "./datalist";
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
import { trackGestures } from "./gesture";
import {
  HIDDEN_CHARACTERS,
  LIMITS,
  parseExtensionResponse,
  type CustomSuggestionsRequest,
} from "./messages";

export interface CustomOptions {
  host: () => string;
  send: (request: CustomSuggestionsRequest) => Promise<unknown>;
  // Only events the browser made count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
  // How the values are shown: a datalist for Safari's bar unless the caller draws its own
  // list, which also works on text areas.
  attach?: Attach;
  // Fields another of Prefill's lists already serves, such as ones a one-tap fill filled.
  skip?: (element: FieldElement) => boolean;
  textAreas?: boolean;
}

const MAX_INSPECTED = 200;
export const CUSTOM_DETAIL = "Custom field";
export const GUESS_DETAIL = "Suggested";
// A datalist shows on text inputs; text areas and selects never show one, and a search box
// never wants a saved answer.
const LIST_INPUTS: ReadonlySet<string> = new Set(["text"]);
const ALL_HIDDEN = new RegExp(HIDDEN_CHARACTERS.source, "gu");

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

export function joinFieldText(parts: readonly string[]): string {
  const text = parts
    .join(" ")
    .replace(ALL_HIDDEN, " ")
    .replace(/\p{Cs}/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
  return text.slice(0, LIMITS.fieldText).replace(/[\uD800-\uDBFF]$/u, "");
}

// Offers the person's custom field values ("School" = "UC Berkeley") on fields whose words
// match, through a datalist: Safari's bar shows it on fields it doesn't fill from the card,
// and Chrome's dropdown shows it too. The matches are fetched when the page loads, since
// Safari reads the list as the field takes focus, and again on each focus, which covers
// fields a page adds later. The list goes away when the field loses focus.
export function installCustom(
  doc: Document,
  options: CustomOptions,
): () => void {
  const isUserEvent =
    options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const attach = options.attach ?? attachDatalist;
  // Safari's bar takes a datalist's values as typing, which a page's combobox handles;
  // Prefill's own list would sit on top of the page's, so it skips fields that have one.
  const isTaken = (element: FieldElement): boolean =>
    options.skip?.(element) === true ||
    (attach === attachDatalist
      ? element.hasAttribute("list")
      : hasOwnList(element));
  const isCandidate = (element: FieldElement): element is TextField =>
    isCustomCandidate(element, options.textAreas);
  const gestures = trackGestures(doc, isUserEvent);
  const known = new Map<string, readonly Choice[]>();
  let detach: (() => void) | undefined;
  let focused: { element: TextField; text: string } | undefined;

  const clear = (): void => {
    detach?.();
    detach = undefined;
    focused = undefined;
  };

  const offer = (): void => {
    const values = focused === undefined ? undefined : known.get(focused.text);
    if (
      focused === undefined ||
      detach !== undefined ||
      values === undefined ||
      values.length === 0
    )
      return;
    detach = attach(focused.element, [...values]);
  };

  const fetchValues = (texts: readonly string[]): void => {
    if (texts.length === 0) return;
    options
      .send({
        type: "customSuggestions",
        host: options.host(),
        fields: texts.map((text) => ({ text })),
      })
      .then((reply) => {
        const response = parseExtensionResponse(reply);
        if (
          response?.type !== "customSuggestionsResult" ||
          response.fields.length !== texts.length
        )
          return;
        texts.forEach((text, index) => {
          const field = response.fields[index];
          known.set(text, [
            ...(field?.values ?? []).map((value) => ({ value, detail: CUSTOM_DETAIL })),
            ...(field?.guesses ?? []).map((value) => ({ value, detail: GUESS_DETAIL })),
          ]);
        });
        offer();
      })
      .catch(() => undefined);
  };

  const prefetch = (): void => {
    const texts = fieldElements(doc, MAX_INSPECTED)
      .filter(isCandidate)
      .map(fieldText);
    fetchValues(
      [...new Set(texts)].filter(Boolean).slice(0, LIMITS.pageFields),
    );
  };

  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || isTaken(target) || !isCandidate(target))
      return;
    const text = fieldText(target);
    if (text === "" || !gestures.allows(target)) return;
    clear();
    focused = { element: target, text };
    offer();
    fetchValues([text]);
  };

  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === focused?.element) clear();
  };

  if (doc.readyState === "loading")
    doc.addEventListener("DOMContentLoaded", prefetch, { once: true });
  else prefetch();
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    gestures.stop();
    doc.removeEventListener("DOMContentLoaded", prefetch);
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
