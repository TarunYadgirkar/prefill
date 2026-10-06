import { parseAutocomplete } from "./autocomplete";
import { isPlaceholder, pickFirst, type Option } from "./choices";
import { classify, isSensitiveText, isSignIn } from "./classify";
import { fillCombobox, isCombobox, isComboboxEmpty } from "./combobox";
import { customChoices, fieldText, joinFieldText } from "./custom";
import { declineOption, isDemographic } from "./demographics";
import { eventOrigin, fieldElements, hasOwnList, isFieldElement, isRendered, labelText, nearbyText } from "./dom";
import { fillField, showDropdown, type Choice, type TextField } from "./dropdown";
import { isContact, type ContactField, type FieldElement } from "./fieldTypes";
import type { GestureGate } from "./gesture";
import { linkChoices } from "./links";
import {
  LIMITS,
  parseExtensionResponse,
  type ContactSuggestionsResult,
  type CustomSuggestionsResult,
  type ExtensionRequest,
  type ExtensionResponse,
  type LinkType,
  type PageField,
  type SuggestedLink,
} from "./messages";
import { SUGGESTED_KINDS, contactChoices } from "./suggestions";

// One tap fills a whole form, the way Safari's AutoFill Contact does: every visible, empty
// field Prefill can answer, from the card, the links and the custom answers. Voluntary
// self-identification questions always get the option that declines, or "No".

export interface FillOptions {
  host: () => string;
  send: (request: ExtensionRequest) => Promise<unknown>;
}

export interface FillResult {
  filled: number;
  undo: () => void;
}

type Want =
  | { from: "contact"; field: ContactField }
  | { from: "link"; types: readonly LinkType[]; fullUrl: boolean }
  | { from: "custom"; text: string }
  | { from: "decline" };

type Slot =
  | { control: "text"; element: TextField; want: Want }
  | { control: "select"; element: HTMLSelectElement; want: Want }
  | { control: "radio"; inputs: HTMLInputElement[]; want: Want }
  | { control: "combobox"; element: HTMLInputElement; want: Want };

interface Answers {
  contact: Omit<ContactSuggestionsResult, "type"> | undefined;
  links: readonly SuggestedLink[];
  custom: ReadonlyMap<string, CustomSuggestionsResult["fields"][number]>;
}

const MAX_INSPECTED = 300;
const TEXT_INPUTS: ReadonlySet<string> = new Set(["text", "email", "tel", "url", "number"]);
// Safari's AutoFill yellow, light enough to read through.
const TINT = "rgb(255 214 10 / 0.22)";
const NO_PICK = (): void => undefined;

// The values Prefill put in each field and the other choices it had, so a tap on a filled
// field can still offer the rest.
const filledChoices = new WeakMap<FieldElement, Choice[]>();

export function choicesFor(element: FieldElement): readonly Choice[] | undefined {
  return filledChoices.get(element);
}

export function isFilled(element: FieldElement): boolean {
  return filledChoices.has(element);
}

function isEditable(element: FieldElement): boolean {
  const control = element as Partial<HTMLInputElement>;
  return control.disabled !== true && control.readOnly !== true;
}

function isEmpty(element: FieldElement): boolean {
  if (element.localName !== "select") return element.value.trim() === "";
  const select = element as HTMLSelectElement;
  const chosen = select.selectedOptions[0];
  return chosen === undefined || isPlaceholder(optionOf(chosen));
}

const optionOf = (option: HTMLOptionElement): Option => ({ text: option.text, value: option.value });

// Where a field's words come from when nothing else claims it: a custom answer, unless
// the field asks a demographic question, which is declined.
// "If other, please specify" follows another answer, so it's left for the person.
const FOLLOW_UP = /^\W*if\b/iu;

// Whether a one-tap fill may put a saved answer in a text box that asks this: not a
// follow-up, and not a demographic question, which only a list of choices can decline.
export function takesSavedAnswer(text: string): boolean {
  return text !== "" && !FOLLOW_UP.test(text) && !isDemographic(text);
}

function freeWant(text: string): Want | undefined {
  if (text === "" || FOLLOW_UP.test(text) || isSensitiveText([[text]])) return undefined;
  return isDemographic(text) ? { from: "decline" } : { from: "custom", text };
}

function linkWant(element: FieldElement, types: readonly LinkType[] | undefined): Want | undefined {
  if (element.localName !== "input") return undefined;
  return { from: "link", types: types ?? ["website"], fullUrl: (element as HTMLInputElement).type === "url" };
}

// A field with an autofill token the card doesn't hold (organization, bday) isn't a question
// for a custom answer, and a text box asking for gender or race is left for the person.
function otherWant(element: FieldElement): Want | undefined {
  if (parseAutocomplete(element.getAttribute("autocomplete")) !== undefined) return undefined;
  const want = freeWant(fieldText(element));
  const hasChoices = element.localName === "select" || isCombobox(element);
  return want?.from === "decline" && !hasChoices ? undefined : want;
}

function wantOf(element: FieldElement): Want | undefined {
  const field = classify(element);
  if (field.kind === "sensitive") return undefined;
  if (field.kind === "link") return linkWant(element, field.linkTypes);
  if (isContact(field)) return SUGGESTED_KINDS.has(field.kind) ? { from: "contact", field } : undefined;
  return otherWant(element);
}

function isFillableControl(element: FieldElement): boolean {
  if (element.localName === "input") return TEXT_INPUTS.has((element as HTMLInputElement).type.toLowerCase());
  return element.localName !== "select" || !(element as HTMLSelectElement).multiple;
}

function comboboxSlot(element: HTMLInputElement): Slot | undefined {
  if (!isEditable(element) || !isRendered(element) || !isComboboxEmpty(element)) return undefined;
  const want = wantOf(element);
  return want === undefined ? undefined : { control: "combobox", element, want };
}

const isOpen = (element: FieldElement): boolean =>
  isEditable(element) && isEmpty(element) && isRendered(element) && !hasOwnList(element) && isFillableControl(element);

function slotOf(element: FieldElement): Slot | undefined {
  if (isCombobox(element)) return comboboxSlot(element as HTMLInputElement);
  if (!isOpen(element)) return undefined;
  const want = wantOf(element);
  if (want === undefined) return undefined;
  return element.localName === "select"
    ? { control: "select", element: element as HTMLSelectElement, want }
    : { control: "text", element: element as TextField, want };
}

// The question a group of radio buttons answers: its fieldset's legend, its radiogroup's
// label, or the words around the buttons that aren't the buttons' own labels.
function groupLabel(first: HTMLInputElement): string {
  const legend = first.closest("fieldset")?.querySelector("legend")?.textContent ?? "";
  if (legend.trim() !== "") return legend;
  const group = first.closest("[role=radiogroup]");
  return group === null ? "" : (group.getAttribute("aria-label") ?? labelledBy(group));
}

// The words before the group: Lever puts the question in a div beside the list of buttons.
function nearbyWords(inputs: readonly HTMLInputElement[]): string[] {
  let container = inputs[0]?.parentElement ?? null;
  while (container !== null && !inputs.every((input) => container?.contains(input) === true))
    container = container.parentElement;
  const text = container === null ? "" : nearbyText(container);
  return text === "" ? [] : [text];
}

export function questionOf(inputs: readonly HTMLInputElement[]): string {
  const first = inputs[0];
  if (first === undefined) return "";
  const label = groupLabel(first);
  return joinFieldText(label.trim() !== "" ? [label] : nearbyWords(inputs));
}

function labelledBy(element: Element): string {
  const ids = (element.getAttribute("aria-labelledby") ?? "").split(/\s+/u).filter(Boolean);
  return ids.map((id) => element.ownerDocument.getElementById(id)?.textContent ?? "").join(" ");
}

function radioSlots(elements: readonly FieldElement[]): Slot[] {
  const groups = new Map<string, HTMLInputElement[]>();
  // Same-named radios in two forms are two questions.
  const forms = new Map<HTMLFormElement | null, number>();
  for (const element of elements) {
    if (element.localName !== "input" || (element as HTMLInputElement).type !== "radio") continue;
    const radio = element as HTMLInputElement;
    if (radio.name === "") continue;
    if (!forms.has(radio.form)) forms.set(radio.form, forms.size);
    const key = `${String(forms.get(radio.form))} ${radio.name}`;
    groups.set(key, [...(groups.get(key) ?? []), radio]);
  }
  return [...groups.values()].flatMap((inputs) => {
    if (inputs.length < 2 || inputs.some((input) => input.checked || !isEditable(input))) return [];
    // Pages often draw their own circles and hide the real buttons, so the labels show it's there.
    if (!inputs.some((input) => isRendered(input) || [...(input.labels ?? [])].some(isRendered))) return [];
    if (isSignIn(inputs[0] as HTMLInputElement)) return [];
    const want = freeWant(questionOf(inputs));
    return want === undefined ? [] : [{ control: "radio" as const, inputs, want }];
  });
}

// The form the person is in, or the whole page when they aren't in one.
export function fillScope(doc: Document, anchor?: Element | null): ParentNode {
  const field = anchor ?? doc.activeElement;
  return field instanceof HTMLElement ? (field.closest("form") ?? doc) : doc;
}

export function findSlots(scope: ParentNode): Slot[] {
  const elements = fieldElements(scope, MAX_INSPECTED);
  const fields = elements.filter((element) => !isSignIn(element)).flatMap((element) => slotOf(element) ?? []);
  return [...fields, ...radioSlots(elements)];
}

function contactRequest(slots: readonly Slot[]): PageField[] {
  const seen = new Map<string, PageField>();
  for (const slot of slots) {
    if (slot.want.from !== "contact") continue;
    const { kind, section } = slot.want.field;
    seen.set(`${kind} ${section ?? ""}`, section === undefined ? { kind } : { kind, section });
  }
  return [...seen.values()].slice(0, LIMITS.pageFields);
}

const linkTypesWanted = (slots: readonly Slot[]): LinkType[] => [
  ...new Set(slots.flatMap((slot) => (slot.want.from === "link" ? slot.want.types : []))),
];

const customTexts = (slots: readonly Slot[]): string[] =>
  [...new Set(slots.flatMap((slot) => (slot.want.from === "custom" ? [slot.want.text] : [])))].slice(
    0,
    LIMITS.pageFields,
  );

// The three questions to the app, each only when some field needs it.
function requests(slots: readonly Slot[], host: string): (ExtensionRequest | undefined)[] {
  const fields = contactRequest(slots);
  const types = linkTypesWanted(slots);
  const texts = customTexts(slots);
  return [
    fields.length > 0 ? { type: "contactSuggestions", host, fields } : undefined,
    types.length > 0 ? { type: "linkSuggestions", host, types } : undefined,
    texts.length > 0 ? { type: "customSuggestions", host, fields: texts.map((text) => ({ text })) } : undefined,
  ];
}

async function gather(slots: readonly Slot[], options: FillOptions): Promise<Answers> {
  const texts = customTexts(slots);
  const ask = async (request: ExtensionRequest | undefined): Promise<ExtensionResponse | undefined> =>
    request === undefined
      ? undefined
      : options
          .send(request)
          .then(parseExtensionResponse)
          .catch(() => undefined);
  const [contact, links, custom] = await Promise.all(requests(slots, options.host()).map(ask));
  const answers = new Map<string, CustomSuggestionsResult["fields"][number]>();
  if (custom?.type === "customSuggestionsResult")
    texts.forEach((text, index) => {
      const field = custom.fields[index];
      if (field !== undefined) answers.set(text, field);
    });
  return {
    contact: contact?.type === "contactSuggestionsResult" ? contact : undefined,
    links: links?.type === "linkSuggestionsResult" ? links.links : [],
    custom: answers,
  };
}

// What a field could take, best first, as its own list would offer it. Guesses are never filled.
function choicesOf(want: Want, answers: Answers): Choice[] {
  switch (want.from) {
    case "contact":
      return answers.contact === undefined ? [] : contactChoices(want.field, answers.contact);
    case "link":
      return linkChoices(want.types, answers.links, want.fullUrl);
    case "custom":
      return customChoices(answers.custom.get(want.text), NO_PICK).filter((choice) => choice.tone !== "guess");
    case "decline":
      return [];
  }
}

const valuesOf = (choices: readonly Choice[]): string[] => choices.map(({ value }) => value);

function setSelect(select: HTMLSelectElement, index: number): void {
  Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "selectedIndex")?.set?.call(select, index);
  select.dispatchEvent(new Event("input", { bubbles: true }));
  select.dispatchEvent(new Event("change", { bubbles: true }));
}

// Tints a filled field until the person changes it, like Safari's AutoFill does.
function tint(element: HTMLElement): () => void {
  const before = element.style.getPropertyValue("background-color");
  const priority = element.style.getPropertyPriority("background-color");
  element.style.setProperty("background-color", TINT, "important");
  let done = false;
  const clear = (): void => {
    if (done) return;
    done = true;
    element.style.setProperty("background-color", before, priority);
    element.removeEventListener("input", onInput, true);
  };
  const onInput = (event: Event): void => {
    if (event.isTrusted) clear();
  };
  element.addEventListener("input", onInput, true);
  return clear;
}

function applyText(element: TextField, choices: readonly Choice[]): (() => void) | undefined {
  const value = choices[0]?.value;
  if (value === undefined || !element.isConnected || !isEmpty(element)) return undefined;
  fillField(element, value);
  // A number box or a maxlength can refuse or cut the value; that field isn't filled.
  if (element.value !== value) {
    fillField(element, "");
    return undefined;
  }
  filledChoices.set(element, [...choices]);
  const clear = tint(element);
  return () => {
    clear();
    if (element.value === value) fillField(element, "");
    filledChoices.delete(element);
  };
}

const optionIndex = (want: Want, options: readonly Option[], values: readonly string[]): number =>
  want.from === "decline" ? declineOption(options) : pickFirst(options, values);

function applySelect(select: HTMLSelectElement, want: Want, values: readonly string[]): (() => void) | undefined {
  const index = optionIndex(want, [...select.options].map(optionOf), values);
  if (index < 0 || !select.isConnected || !isEmpty(select)) return undefined;
  const before = select.selectedIndex;
  setSelect(select, index);
  const clear = tint(select);
  return () => {
    clear();
    if (select.selectedIndex === index) setSelect(select, before);
  };
}

function applyRadio(inputs: readonly HTMLInputElement[], want: Want, values: readonly string[]): (() => void) | undefined {
  const options = inputs.map((input) => ({ text: labelText(input), value: input.value }));
  const radio = inputs[optionIndex(want, options, values)];
  if (radio === undefined || !radio.isConnected || inputs.some((input) => input.checked)) return undefined;
  radio.click();
  return () => {
    if (!radio.checked) return;
    radio.checked = false;
    radio.dispatchEvent(new Event("change", { bubbles: true }));
  };
}

// Types the answer to narrow the list, or opens it with the down arrow to decline.
function applyCombobox(input: HTMLInputElement, want: Want, values: readonly string[]): Promise<(() => void) | undefined> {
  if (want.from !== "decline" && values[0] === undefined) return Promise.resolve(undefined);
  const search = want.from === "decline" ? undefined : values[0];
  return fillCombobox(input, (options) => optionIndex(want, options, values), search);
}

// Fills one slot and returns what puts it back, or undefined when nothing fit.
function apply(slot: Slot, answers: Answers): (() => void) | undefined {
  const choices = choicesOf(slot.want, answers);
  if (slot.control === "text") return applyText(slot.element, choices);
  const values = valuesOf(choices);
  if (slot.control === "select") return applySelect(slot.element, slot.want, values);
  if (slot.control === "radio") return applyRadio(slot.inputs, slot.want, values);
  return undefined;
}

// Searchable dropdowns open one at a time, after the rest of the form is filled.
async function applyComboboxes(slots: readonly Slot[], answers: Answers): Promise<(() => void)[]> {
  const undos: (() => void)[] = [];
  for (const slot of slots) {
    if (slot.control !== "combobox") continue;
    // The person may have picked one while earlier boxes were filling.
    if (!slot.element.isConnected || !isComboboxEmpty(slot.element)) continue;
    const values = valuesOf(choicesOf(slot.want, answers));
    const undo = await applyCombobox(slot.element, slot.want, values).catch(() => undefined);
    if (undo !== undefined) undos.push(undo);
  }
  return undos;
}

// Fills every empty field of the form the person is in, in page order, and returns how
// many it filled and what takes them all back.
export async function fillForm(scope: ParentNode, options: FillOptions): Promise<FillResult> {
  const slots = findSlots(scope);
  if (slots.length === 0) return { filled: 0, undo: () => undefined };
  const answers = await gather(slots, options);
  const undos = [...slots.flatMap((slot) => apply(slot, answers) ?? []), ...(await applyComboboxes(slots, answers))];
  return {
    filled: undos.length,
    undo: () => {
      [...undos].reverse().forEach((undo) => {
        undo();
      });
    },
  };
}

// A tap on a field Prefill filled shows the other values it could have used, so the person
// can switch with one more tap; Prefill's other lists leave those fields to this one.
export function installFilledPicker(
  doc: Document,
  gate: GestureGate,
  isUserEvent: (event: Event) => boolean = (event) => event.isTrusted,
): () => void {
  let detach: (() => void) | undefined;
  let current: FieldElement | undefined;
  const clear = (): void => {
    detach?.();
    detach = undefined;
    current = undefined;
  };
  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || target === current) return;
    const choices = choicesFor(target);
    if (choices === undefined || choices.length < 2 || target.localName === "select" || !gate.allows(target)) return;
    clear();
    current = target;
    detach = showDropdown(target as TextField, choices, isUserEvent);
  };
  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === current) clear();
  };
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
