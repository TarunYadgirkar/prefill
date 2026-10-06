import { attachDatalist } from "./datalist";
import { classify } from "./classify";
import { eventOrigin, hasOwnList, fieldElements, isFieldElement } from "./dom";
import {
  showDropdown,
  type Attach,
  type Choice,
  type TextField,
} from "./dropdown";
import { trackGestures } from "./gesture";
import { reportPick } from "./picks";
import {
  isContact,
  type ContactField,
  type FieldElement,
  type FieldPart,
} from "./fieldTypes";
import {
  LIMITS,
  parseExtensionResponse,
  type ContactSuggestionsRequest,
  type ContactSuggestionsResult,
  type FieldKind,
  type PageField,
  type PickedRequest,
  type PostalAddress,
  type SuggestedValue,
} from "./messages";

export type Suggestions = Omit<ContactSuggestionsResult, "type">;
type Name = NonNullable<Suggestions["name"]>;

export interface SuggestionOptions {
  host: () => string;
  send: (request: ContactSuggestionsRequest | PickedRequest) => Promise<unknown>;
  // Safari fills contact fields from the card itself, so there Prefill asks only for what a
  // minimal card left on Prefill's contact, shows it through a datalist, and skips text
  // areas, which never show one.
  offCard?: boolean;
  // Only events the browser made count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
  now?: () => number;
  attach?: Attach;
  // Fields another of Prefill's lists already serves, such as ones a one-tap fill filled.
  skip?: (element: FieldElement) => boolean;
}

const MAX_INSPECTED = 200;
// Single-line inputs that take typed contact details. Text areas count too: Prefill draws
// its own list under them, and forms like Airtable's ask for a name or email in one.
const LIST_INPUTS: ReadonlySet<string> = new Set([
  "text",
  "email",
  "tel",
  "search",
]);
export const SUGGESTED_KINDS: ReadonlySet<FieldKind> = new Set([
  "email",
  "phone",
  "address",
  "name",
]);

const ADDRESS_PARTS: Partial<
  Record<FieldPart, (address: PostalAddress) => string>
> = {
  street: (address) => address.street.split("\n")[0] ?? "",
  street2: (address) => address.street.split("\n").slice(1).join(", "),
  city: (address) => address.city,
  state: (address) => address.state,
  postalCode: (address) => address.postalCode,
  country: (address) => address.country,
};

const NAME_PARTS: Partial<Record<FieldPart, (name: Name) => string>> = {
  full: (name) => `${name.given} ${name.family}`,
  given: (name) => name.given,
  family: (name) => name.family,
};

const BY_KIND: Partial<
  Record<
    FieldKind,
    (part: FieldPart | undefined, values: Suggestions) => SuggestedValue[]
  >
> = {
  email: (_part, values) => values.emails,
  phone: (part, values) => (part === "partial" ? [] : values.phones),
  address: (part, values) => {
    const pick = ADDRESS_PARTS[part ?? "street"];
    return pick === undefined
      ? []
      : values.addresses.map(({ address, ...why }) => ({ ...why, value: pick(address) }));
  },
  name: (part, values) => {
    const pick = NAME_PARTS[part ?? "full"];
    return pick === undefined || values.name === undefined
      ? []
      : [{ value: pick(values.name), why: "card" }];
  },
};

// What the browser's dropdown offers a field, best first, each value once, with why it's there.
export function suggestionOptions(
  field: ContactField,
  values: Suggestions,
): SuggestedValue[] {
  const all = BY_KIND[field.kind]?.(field.part, values) ?? [];
  const seen = new Set<string>();
  return all
    .map((offered) => ({ ...offered, value: offered.value.trim() }))
    .filter(({ value }) => value.length > 0 && !seen.has(value) && seen.add(value))
    .slice(0, LIMITS.suggestions);
}

// A pick of a value that wasn't first is worth remembering. An address is remembered by
// its street line, and a name has only one value.
export function pickKind(field: ContactField): PickedRequest["kind"] | undefined {
  if (field.kind === "email" || field.kind === "phone") return field.kind;
  if (field.kind === "address" && (field.part ?? "street") === "street")
    return "address";
  return undefined;
}

export const KIND_LABELS: Partial<Record<FieldKind, string>> = {
  email: "Email",
  phone: "Phone",
  address: "Address",
  name: "Name",
};

function isTextField(
  element: FieldElement,
  textAreas = true,
): element is TextField {
  if (element.localName === "textarea") return textAreas;
  return (
    element.localName === "input" &&
    LIST_INPUTS.has((element as HTMLInputElement).type.toLowerCase())
  );
}

function suggestedField(
  element: FieldElement,
  textAreas = true,
): ContactField | undefined {
  if (!isTextField(element, textAreas)) return undefined;
  const field = classify(element);
  return isContact(field) && SUGGESTED_KINDS.has(field.kind)
    ? field
    : undefined;
}

// One entry per kind and section, so the request stays small on long forms.
function pageFields(
  doc: Document,
  fieldOf: (element: FieldElement) => ContactField | undefined,
): PageField[] {
  const seen = new Map<string, PageField>();
  for (const element of fieldElements(doc, MAX_INSPECTED)) {
    const field = fieldOf(element);
    if (field === undefined) continue;
    const entry: PageField =
      field.section === undefined
        ? { kind: field.kind }
        : { kind: field.kind, section: field.section };
    seen.set(`${entry.kind} ${entry.section ?? ""}`, entry);
  }
  return [...seen.values()].slice(0, LIMITS.pageFields);
}

// Offers the card's emails, phone numbers, addresses and name in Prefill's own dropdown,
// on browsers whose autofill doesn't read the card (Chrome, Arc), and in Safari the values
// a minimal card left on Prefill's contact, through a datalist that Safari's bar shows when
// the card has nothing for the field. The values are fetched when the page loads, ranked
// for the site, and a field gets its list when the person focuses it; the list goes away
// when the field loses focus. A field with a datalist of its own is left alone.
export function installSuggestions(
  doc: Document,
  options: SuggestionOptions,
): () => void {
  const isUserEvent =
    options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const attach = options.attach ?? showDropdown;
  // Safari's bar takes a datalist's values as typing, which a page's combobox handles;
  // Prefill's own list would sit on top of the page's, so it skips fields that have one.
  const isTaken = (element: FieldElement): boolean =>
    options.skip?.(element) === true ||
    (attach === attachDatalist
      ? element.hasAttribute("list")
      : hasOwnList(element));
  const offCard = options.offCard === true;
  const fieldOf = (element: FieldElement): ContactField | undefined =>
    suggestedField(element, !offCard);
  const gestures = trackGestures(doc, isUserEvent, options.now);
  let known: Suggestions | undefined;
  let detach: (() => void) | undefined;
  let focused: { element: TextField; field: ContactField } | undefined;

  const clear = (): void => {
    detach?.();
    detach = undefined;
    focused = undefined;
  };

  const offer = (): void => {
    if (focused === undefined || detach !== undefined || known === undefined)
      return;
    const detail = KIND_LABELS[focused.field.kind] ?? "";
    const kind = pickKind(focused.field);
    const choices: Choice[] = suggestionOptions(focused.field, known).map(
      ({ value }, index) =>
        kind === undefined || index === 0
          ? { value, detail }
          : { value, detail, onPick: () => { picked(kind, value); } },
    );
    if (choices.length > 0) detach = attach(focused.element, choices);
  };

  const fetchValues = (): void => {
    const fields = pageFields(doc, fieldOf);
    if (fields.length === 0) return;
    options
      .send({
        type: "contactSuggestions",
        host: options.host(),
        fields,
        ...(offCard ? { offCard } : {}),
      })
      .then((reply) => {
        const response = parseExtensionResponse(reply);
        if (response?.type !== "contactSuggestionsResult") return;
        known = response;
        offer();
      })
      .catch(() => undefined);
  };

  const picked = (kind: PickedRequest["kind"], value: string): void => {
    reportPick(
      options.send,
      { type: "picked", host: options.host(), kind, value },
      fetchValues,
    );
  };

  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (
      !isFieldElement(target) ||
      isTaken(target) ||
      !isTextField(target, !offCard)
    )
      return;
    const field = fieldOf(target);
    if (field === undefined || !gestures.allows(target)) return;
    clear();
    focused = { element: target, field };
    offer();
    fetchValues();
  };

  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === focused?.element) clear();
  };

  if (doc.readyState === "loading")
    doc.addEventListener("DOMContentLoaded", fetchValues, { once: true });
  else fetchValues();
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    gestures.stop();
    doc.removeEventListener("DOMContentLoaded", fetchValues);
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
