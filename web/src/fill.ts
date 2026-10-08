import { parseAutocomplete } from "./autocomplete";
import { chooseOption, isPlaceholder, stateName, type Option, type OptionMatch } from "./choices";
import { classify, isSensitiveText, isSignIn } from "./classify";
import { fillCombobox, isCombobox, isComboboxEmpty } from "./combobox";
import { askedField, customChoices, fieldText, fillable, joinFieldText } from "./custom";
import { declineOption, isDemographic } from "./demographics";
import { eventOrigin, fieldElements, hasOwnList, isFieldElement, isRendered, labelText, nearbyText } from "./dom";
import { fillField, showDropdown, type Attach, type Choice, type TextField } from "./dropdown";
import { isContact, type ContactField, type FieldElement } from "./fieldTypes";
import { fitPhones, isHelper, isOneBoxAddress, isPhoneBox } from "./fillFit";
import type { GestureGate } from "./gesture";
import { linkChoices } from "./links";
import {
  LIMITS,
  parseExtensionResponse,
  type ContactSuggestionsResult,
  type CustomSuggestionsRequest,
  type CustomSuggestionsResult,
  type ExtensionRequest,
  type ExtensionResponse,
  type LinkType,
  type PageField,
  type PickedRequest,
  type SuggestedLink,
} from "./messages";
import { reportPick } from "./picks";
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
// Around a list Prefill left because more than one option fits the answer.
const UNSURE_OUTLINE = "2px dashed rgb(255 159 10 / 0.9)";

// Tells the app about a pick from a filled field's list, as the field's own list would.
type Report = (pick: Pick<PickedRequest, "kind" | "value" | "question">) => void;
const NO_REPORT: Report = () => undefined;

function reporter(options: FillOptions): Report {
  return (pick) => {
    reportPick(options.send, { type: "picked", host: options.host(), ...pick });
  };
}

// The values Prefill put in each field and the other choices it had, so a tap on a filled
// field can still offer the rest.
const filledChoices = new WeakMap<FieldElement, Choice[]>();

export function choicesFor(element: FieldElement): readonly Choice[] | undefined {
  return filledChoices.get(element);
}

// Lists a fill left because more than one option fits the answer, with what the pill says
// when "need you" reaches them.
const unsure = new WeakMap<FieldElement, string>();

export function noteFor(element: FieldElement): string | undefined {
  return unsure.get(element);
}

export const unsureNote = (fits: number): string => `${String(fits)} options fit, pick one`;
export const MISSED_NOTE = "This one didn’t take, check it";

// Fields a fill set that didn't keep the value (the page put it back or changed it), from the
// last fill: they count as "need you" even when they aren't empty.
let missed: FieldElement[] = [];

export function missedFields(scope: ParentNode): FieldElement[] {
  return missed.filter((field) => field.isConnected && scope.contains(field));
}

// What a fill put in a field from a saved answer, as the field shows it (a list's option
// text, a radio button's label), so a submit can tell when the person changed it.
const filledAnswers = new WeakMap<FieldElement, string>();

export function filledAnswer(element: FieldElement): string | undefined {
  return filledAnswers.get(element);
}

// One field a fill set: what puts it back, and whether it still holds what Prefill put there.
interface Filled {
  field: FieldElement;
  undo: () => void;
  took: () => boolean;
  // The answer as the field shows it, for a custom answer only.
  shown?: string | undefined;
}

// A field the person emptied is theirs again, and gets the lists any field gets.
export function isFilled(element: FieldElement): boolean {
  if ((element as HTMLInputElement).value === "") filledChoices.delete(element);
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
// "If other, please specify" and "If you answered yes, explain" follow another answer, so
// they're left for the person. "If you are enrolled, when do you graduate?" stands alone.
const FOLLOW_UP =
  /^\W*if\W+(?:(?:yes|no|other|so|not|applicable|any|none|unsure|selected|checked)\b|you\s+(?:answered|selected|chose|checked|said|responded|marked|picked)\b|(?:the|your)\s+answer\b)/iu;

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
  if (element.localName === "select") return undefined;
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
  isEditable(element) && isEmpty(element) && isRendered(element) && (isPhoneBox(element) || !hasOwnList(element)) && isFillableControl(element);

function slotOf(element: FieldElement): Slot | undefined {
  if (isHelper(element)) return undefined;
  if (isCombobox(element) && !isPhoneBox(element)) return comboboxSlot(element as HTMLInputElement);
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

// The smallest element holding every button of a group.
function groupBox(inputs: readonly HTMLInputElement[]): HTMLElement | null {
  let container = inputs[0]?.parentElement ?? null;
  while (container !== null && !inputs.every((input) => container?.contains(input) === true))
    container = container.parentElement;
  return container;
}

// The words before the group: Lever puts the question in a div beside the list of buttons.
function nearbyWords(inputs: readonly HTMLInputElement[]): string[] {
  const container = groupBox(inputs);
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

const isRadio = (element: FieldElement): element is HTMLInputElement =>
  element.localName === "input" && (element as HTMLInputElement).type === "radio";

// The question a radio button belongs to: its name within its form, since same-named radios
// in two forms are two questions, or for a button without a name (Meta's) the radiogroup or
// fieldset around it.
function radioKey(radio: HTMLInputElement, forms: Map<HTMLFormElement | null, number>): string | Element | undefined {
  if (radio.name === "") return radio.parentElement?.closest("[role=radiogroup], fieldset") ?? undefined;
  if (!forms.has(radio.form)) forms.set(radio.form, forms.size);
  return `${String(forms.get(radio.form))} ${radio.name}`;
}

function radioGroups(elements: readonly FieldElement[]): HTMLInputElement[][] {
  const groups = new Map<string | Element, HTMLInputElement[]>();
  const forms = new Map<HTMLFormElement | null, number>();
  for (const radio of elements.filter(isRadio)) {
    const key = radioKey(radio, forms);
    if (key !== undefined) groups.set(key, [...(groups.get(key) ?? []), radio]);
  }
  return [...groups.values()];
}

function radioSlots(elements: readonly FieldElement[]): Slot[] {
  return radioGroups(elements).flatMap((inputs) => {
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
  return [...(isOneBoxAddress(elements) ? fields.map(wholeAddress) : fields), ...radioSlots(elements)];
}

// The street box of a form with no other address boxes takes the address on one line.
function wholeAddress(slot: Slot): Slot {
  if (slot.control !== "text" || slot.want.from !== "contact") return slot;
  const { field } = slot.want;
  if (field.kind !== "address" || (field.part ?? "street") !== "street") return slot;
  return { ...slot, want: { from: "contact", field: { ...field, part: "full" } } };
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

// What a list offers, as the app's request carries it: each option's text, without the placeholder.
function optionTexts(slot: Slot): string[] {
  const options =
    slot.control === "select" ? [...slot.element.options].map(optionOf).filter((option) => !isPlaceholder(option))
    : slot.control === "radio" ? radioOptions(slot.inputs)
    : [];
  return options.map((option) => joinFieldText([option.text], LIMITS.text)).filter(Boolean);
}

// Each question once, with the heading above its first field and a list's options.
function customFields(slots: readonly Slot[], texts: readonly string[]): CustomSuggestionsRequest["fields"] {
  return texts.map((text) => {
    const slot = slots.find((candidate) => candidate.want.from === "custom" && candidate.want.text === text);
    const element = slot === undefined ? undefined : slotField(slot);
    return slot === undefined || element === undefined ? { text } : askedField(text, element, optionTexts(slot));
  });
}

// The three questions to the app, each only when some field needs it.
function requests(slots: readonly Slot[], host: string): (ExtensionRequest | undefined)[] {
  const fields = contactRequest(slots);
  const types = linkTypesWanted(slots);
  const texts = customTexts(slots);
  return [
    fields.length > 0 ? { type: "contactSuggestions", host, fields } : undefined,
    types.length > 0 ? { type: "linkSuggestions", host, types } : undefined,
    texts.length > 0 ? { type: "customSuggestions", host, fields: customFields(slots, texts) } : undefined,
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
function choicesOf(want: Want, answers: Answers, report: Report = NO_REPORT): Choice[] {
  switch (want.from) {
    case "contact":
      return answers.contact === undefined
        ? []
        : contactChoices(want.field, answers.contact, (kind, value) => { report({ kind, value }); });
    case "link":
      return linkChoices(want.types, answers.links, want.fullUrl, (value) => { report({ kind: "link", value }); });
    case "custom":
      return fillable(customChoices(answers.custom.get(want.text), (value) => {
        report({ kind: "custom", value, question: want.text });
      }));
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

// Sets one style on an element until the person changes it, and returns what takes it off.
function highlight(element: HTMLElement, property: string, value: string, until: string, onClear?: () => void): () => void {
  const before = element.style.getPropertyValue(property);
  const priority = element.style.getPropertyPriority(property);
  element.style.setProperty(property, value, "important");
  let done = false;
  const clear = (): void => {
    if (done) return;
    done = true;
    element.style.setProperty(property, before, priority);
    element.removeEventListener(until, onChange, true);
    onClear?.();
  };
  const onChange = (event: Event): void => {
    if (event.isTrusted) clear();
  };
  element.addEventListener(until, onChange, true);
  return clear;
}

// Tints a filled field until the person changes it, like Safari's AutoFill does.
const tint = (element: HTMLElement): (() => void) => highlight(element, "background-color", TINT, "input");

// Outlines a list Prefill left for the person, and notes it for the pill, until they choose.
// A searchable dropdown's box is too small to outline, so it only gets the note.
function markUnsure(field: FieldElement, box: HTMLElement | undefined, fits: number): () => void {
  unsure.set(field, unsureNote(fits));
  const forget = (): void => {
    unsure.delete(field);
  };
  return box === undefined ? forget : highlight(box, "outline", UNSURE_OUTLINE, "change", forget);
}

// Undo takes off these marks as well as the values.
type Marks = (() => void)[];

// A page may reformat what it's given ("5105550134" as "(510) 555-0134", trimmed, upper-cased),
// which still took. A phone-like value compares by its digits.
const PHONE_LIKE = /^[\d\s()+.-]{7,}$/u;
function sameValue(shown: string, filled: string): boolean {
  const plain = (text: string): string => text.trim().replace(/\s+/gu, " ").toLowerCase();
  if (PHONE_LIKE.test(filled.trim()) && PHONE_LIKE.test(shown.trim())) return shown.replace(/\D/gu, "") === filled.replace(/\D/gu, "");
  return plain(shown) === plain(filled);
}

function applyText(element: TextField, choices: readonly Choice[]): Filled | undefined {
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
  const undo = (): void => {
    clear();
    if (element.value === value) fillField(element, "");
    filledChoices.delete(element);
  };
  return { field: element, undo, took: () => sameValue(element.value, value), shown: value.trim() };
}

// Which option to choose. A demographic question has one answer, the decline, so only a saved
// answer can fit more than one option.
function optionMatch(want: Want, options: readonly Option[], values: readonly string[]): OptionMatch {
  if (want.from !== "decline") return chooseOption(options, values);
  const index = declineOption(options);
  return { index, fits: index < 0 ? 0 : 1 };
}

const isClear = (match: OptionMatch): boolean => match.index >= 0 && match.fits === 1;

function applySelect(select: HTMLSelectElement, want: Want, values: readonly string[], marks: Marks): Filled | undefined {
  const match = optionMatch(want, [...select.options].map(optionOf), values);
  if (!select.isConnected || !isEmpty(select)) return undefined;
  if (match.fits > 1) marks.push(markUnsure(select, select, match.fits));
  if (!isClear(match)) return undefined;
  const { index } = match;
  const before = select.selectedIndex;
  setSelect(select, index);
  const clear = tint(select);
  const undo = (): void => {
    clear();
    if (select.selectedIndex === index) setSelect(select, before);
  };
  return { field: select, undo, took: () => select.selectedIndex === index, shown: select.options[index]?.text.trim() };
}

const radioOptions = (inputs: readonly HTMLInputElement[]): Option[] =>
  inputs.map((input) => ({ text: labelText(input), value: input.value }));

function applyRadio(inputs: readonly HTMLInputElement[], want: Want, values: readonly string[], marks: Marks): Filled | undefined {
  const match = optionMatch(want, radioOptions(inputs), values);
  const [first] = inputs;
  if (first === undefined || !first.isConnected || inputs.some((input) => input.checked)) return undefined;
  if (match.fits > 1) marks.push(markUnsure(first, groupBox(inputs) ?? first, match.fits));
  const radio = isClear(match) ? inputs[match.index] : undefined;
  if (radio === undefined) return undefined;
  clickOnly(radio, inputs);
  return { field: first, undo: () => { uncheck(radio); }, took: () => radio.checked, shown: radioText(radio) };
}

// Lever wraps a question's buttons in the question's own label, so a click on one can bubble
// to that label and check its first button. The fill keeps only the button it chose: a
// demographic question must never end up on a real answer.
function clickOnly(radio: HTMLInputElement, inputs: readonly HTMLInputElement[]): void {
  radio.click();
  if (radio.checked) return;
  for (const other of inputs) uncheck(other);
  radio.checked = true;
  radio.dispatchEvent(new Event("input", { bubbles: true }));
  radio.dispatchEvent(new Event("change", { bubbles: true }));
}

function uncheck(radio: HTMLInputElement): void {
  if (!radio.checked) return;
  radio.checked = false;
  radio.dispatchEvent(new Event("change", { bubbles: true }));
}

// A radio button's answer as learning reads it: its first label's text.
const radioText = (radio: HTMLInputElement): string | undefined => radio.labels?.[0]?.textContent.trim();

// Types the answer to narrow the list, or opens it with the down arrow to decline.
// `values` are what the box is searched with; `matchOn` what its options are compared with.
async function applyCombobox(input: HTMLInputElement, want: Want, values: readonly string[], marks: Marks, matchOn = values): Promise<Filled | undefined> {
  if (want.from !== "decline" && values[0] === undefined) return undefined;
  const search = want.from === "decline" ? undefined : values[0];
  let fits = 0;
  const undo = await fillCombobox(input, (options) => {
    const match = optionMatch(want, options, matchOn);
    fits = match.fits;
    return isClear(match) ? match.index : -1;
  }, search);
  if (fits > 1) marks.push(markUnsure(input, undefined, fits));
  return undo === undefined ? undefined : { field: input, undo, took: () => !isComboboxEmpty(input) };
}

const isPhoneWant = (want: Want): boolean => want.from === "contact" && want.field.kind === "phone";

// Fills one slot and says what it did, or undefined when nothing fit.
function apply(slot: Slot, answers: Answers, report: Report, marks: Marks): Filled | undefined {
  const choices = choicesOf(slot.want, answers, report);
  if (slot.control === "text") return applyText(slot.element, isPhoneWant(slot.want) ? fitPhones(slot.element, choices) : choices);
  const values = valuesOf(choices);
  if (slot.control === "select") return applySelect(slot.element, slot.want, values, marks);
  if (slot.control === "radio") return applyRadio(slot.inputs, slot.want, values, marks);
  return undefined;
}

// A searchable place list ("Berkeley, California, United States") is searched by the city and
// compared with the whole place, so the city in the person's own state wins.
function placesOf(want: Want, answers: Answers): string[] | undefined {
  if (want.from !== "contact" || want.field.kind !== "address" || want.field.part !== "city") return undefined;
  return (answers.contact?.addresses ?? []).flatMap(({ address }) => [
    [address.city, stateName(address.state), address.country].filter(Boolean).join(", "),
    [address.city, address.state].filter(Boolean).join(", "),
  ]);
}

// Searchable dropdowns open one at a time, after the rest of the form is filled.
async function applyComboboxes(slots: readonly Slot[], answers: Answers, marks: Marks): Promise<Filled[]> {
  const undos: Filled[] = [];
  for (const slot of slots) {
    if (slot.control !== "combobox") continue;
    // The person may have picked one while earlier boxes were filling.
    if (!slot.element.isConnected || !isComboboxEmpty(slot.element)) continue;
    const values = valuesOf(choicesOf(slot.want, answers));
    const undo = await applyCombobox(slot.element, slot.want, values, marks, placesOf(slot.want, answers) ?? values).catch(() => undefined);
    if (undo !== undefined) undos.push(undo);
  }
  return undos;
}

// Whether a fill would put something in the slot: a value the field takes, one option that
// clearly says it, or for a demographic list the option that declines.
function hasAnswer(slot: Slot, answers: Answers): boolean {
  if (slot.control === "combobox") return slot.want.from === "decline" || choicesOf(slot.want, answers).length > 0;
  const values = valuesOf(choicesOf(slot.want, answers));
  if (slot.control === "text") return values.length > 0;
  const options = slot.control === "select" ? [...slot.element.options].map(optionOf) : radioOptions(slot.inputs);
  return isClear(optionMatch(slot.want, options, values));
}

// How many empty fields of the form a fill would fill, from the same answers it would use.
export async function fillableCount(scope: ParentNode, options: FillOptions): Promise<number> {
  const slots = findSlots(scope);
  if (slots.length === 0) return 0;
  const answers = await gather(slots, options);
  return slots.filter((slot) => hasAnswer(slot, answers)).length;
}

// The field a slot is: the box, the list, or a group's first button.
export function slotField(slot: Slot): FieldElement | undefined {
  return slot.control === "radio" ? slot.inputs[0] : slot.element;
}

// A page's own script can put a field back or change it right after a fill (a controlled
// React input, a select that resets its neighbour), so a fill reads each field back once the
// page has had its turn.
const settle = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

// The fields that kept their value count as filled; the rest are put back as they were,
// noted for the pill and counted as "need you".
function verify(filled: readonly Filled[], slots: readonly Slot[]): Filled[] {
  const kept = filled.filter((entry) => entry.took());
  missed = filled.filter((entry) => !kept.includes(entry)).map((entry) => entry.field);
  for (const entry of filled) {
    if (!kept.includes(entry)) {
      entry.undo();
      forgetAnswer(entry, slots);
      unsure.set(entry.field, MISSED_NOTE);
    }
  }
  for (const entry of kept) rememberAnswer(entry, slots);
  return kept;
}

// The field a slot is, and for a radio group every button, since the person may check another.
function answerFields(entry: Filled, slots: readonly Slot[]): { slot: Slot | undefined; fields: FieldElement[] } {
  const slot = slots.find((candidate) => slotField(candidate) === entry.field);
  return { slot, fields: slot?.control === "radio" ? slot.inputs : [entry.field] };
}

// A custom answer's field keeps what the fill showed, so a submit can tell it was changed.
function rememberAnswer(entry: Filled, slots: readonly Slot[]): void {
  const { slot, fields } = answerFields(entry, slots);
  if (slot?.want.from !== "custom" || entry.shown === undefined) return;
  for (const field of fields) filledAnswers.set(field, entry.shown);
}

// After Undo or a value that didn't take, what the person types there is their own answer.
function forgetAnswer(entry: Filled, slots: readonly Slot[]): void {
  for (const field of answerFields(entry, slots).fields) filledAnswers.delete(field);
}

// Fills every empty field of the form the person is in, in page order, and returns how
// many it filled and what takes them all back. Only fields that kept the value count.
export async function fillForm(scope: ParentNode, options: FillOptions): Promise<FillResult> {
  missed = [];
  const slots = findSlots(scope);
  if (slots.length === 0) return { filled: 0, undo: () => undefined };
  const answers = await gather(slots, options);
  const report = reporter(options);
  const marks: Marks = [];
  const filled = [
    ...slots.flatMap((slot) => apply(slot, answers, report, marks) ?? []),
    ...(await applyComboboxes(slots, answers, marks)),
  ];
  await settle();
  const kept = verify(filled, slots);
  return {
    filled: kept.length,
    undo: () => {
      const undos = kept.map((entry) => () => {
        entry.undo();
        forgetAnswer(entry, slots);
      });
      [...undos, ...marks].reverse().forEach((undo) => {
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
  // How a field's list is drawn: Safari places a contact field's list clear of its bubble.
  attachFor: (element: TextField) => Attach = () => (element, choices) => showDropdown(element, choices, isUserEvent),
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
    detach = attachFor(target as TextField)(target as TextField, choices);
  };
  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === current) clear();
  };
  const onInput = (event: Event): void => {
    if (current !== undefined && eventOrigin(event) === current && !isFilled(current)) clear();
  };
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  doc.addEventListener("input", onInput, true);
  return () => {
    clear();
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
    doc.removeEventListener("input", onInput, true);
  };
}
