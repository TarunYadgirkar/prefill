import { classify } from "./classify";
import { attachList } from "./datalist";
import { eventOrigin, fieldElements, isFieldElement } from "./dom";
import { trackGestures } from "./gesture";
import { isContact, type ContactField, type FieldElement, type FieldPart } from "./fieldTypes";
import {
  LIMITS,
  parseExtensionResponse,
  type ContactSuggestionsRequest,
  type ContactSuggestionsResult,
  type FieldKind,
  type PageField,
  type PostalAddress,
} from "./messages";

export type Suggestions = Omit<ContactSuggestionsResult, "type">;
type Name = NonNullable<Suggestions["name"]>;

export interface SuggestionOptions {
  host: () => string;
  send: (request: ContactSuggestionsRequest) => Promise<unknown>;
  // Only events the browser made count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
  now?: () => number;
}

const MAX_INSPECTED = 200;
// Input types a datalist works on; selects and text areas never show one.
const LIST_INPUTS: ReadonlySet<string> = new Set(["text", "email", "tel", "search"]);
const SUGGESTED_KINDS: ReadonlySet<FieldKind> = new Set(["email", "phone", "address", "name"]);

const ADDRESS_PARTS: Partial<Record<FieldPart, (address: PostalAddress) => string>> = {
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

const BY_KIND: Partial<Record<FieldKind, (part: FieldPart | undefined, values: Suggestions) => string[]>> = {
  email: (_part, values) => values.emails,
  phone: (part, values) => (part === "partial" ? [] : values.phones),
  address: (part, values) => {
    const pick = ADDRESS_PARTS[part ?? "street"];
    return pick === undefined ? [] : values.addresses.map(pick);
  },
  name: (part, values) => {
    const pick = NAME_PARTS[part ?? "full"];
    return pick === undefined || values.name === undefined ? [] : [pick(values.name)];
  },
};

// What the browser's dropdown offers a field, best first, each value once.
export function suggestionOptions(field: ContactField, values: Suggestions): string[] {
  const all = BY_KIND[field.kind]?.(field.part, values) ?? [];
  const trimmed = all.map((value) => value.trim()).filter((value) => value.length > 0);
  return [...new Set(trimmed)].slice(0, LIMITS.suggestions);
}

function suggestedField(element: FieldElement): ContactField | undefined {
  if (element.localName !== "input" || !LIST_INPUTS.has((element as HTMLInputElement).type.toLowerCase())) return undefined;
  const field = classify(element);
  return isContact(field) && SUGGESTED_KINDS.has(field.kind) ? field : undefined;
}

// One entry per kind and section, so the request stays small on long forms.
function pageFields(doc: Document): PageField[] {
  const seen = new Map<string, PageField>();
  for (const element of fieldElements(doc, MAX_INSPECTED)) {
    const field = suggestedField(element);
    if (field === undefined) continue;
    const entry: PageField = field.section === undefined ? { kind: field.kind } : { kind: field.kind, section: field.section };
    seen.set(`${entry.kind} ${entry.section ?? ""}`, entry);
  }
  return [...seen.values()].slice(0, LIMITS.pageFields);
}

// Offers the card's emails, phone numbers, addresses and name in the browser's own
// dropdown through a datalist, on browsers whose autofill doesn't read the card (Chrome,
// Arc). The values are fetched when the page loads, ranked for the site, and a field gets
// its list when the person focuses it; the list goes away when the field loses focus. A
// field with a list of its own is left alone.
export function installSuggestions(doc: Document, options: SuggestionOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const gestures = trackGestures(doc, isUserEvent, options.now);
  let known: Suggestions | undefined;
  let detach: (() => void) | undefined;
  let focused: { element: HTMLInputElement; field: ContactField } | undefined;

  const clear = (): void => {
    detach?.();
    detach = undefined;
    focused = undefined;
  };

  const offer = (): void => {
    if (focused === undefined || detach !== undefined || known === undefined) return;
    const choices = suggestionOptions(focused.field, known);
    if (choices.length > 0) detach = attachList(focused.element, choices);
  };

  const fetchValues = (): void => {
    const fields = pageFields(doc);
    if (fields.length === 0) return;
    options
      .send({ type: "contactSuggestions", host: options.host(), fields })
      .then((reply) => {
        const response = parseExtensionResponse(reply);
        if (response?.type !== "contactSuggestionsResult") return;
        known = response;
        offer();
      })
      .catch(() => undefined);
  };

  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || target.hasAttribute("list")) return;
    const field = suggestedField(target);
    const element = target as HTMLInputElement;
    if (field === undefined || !gestures.allows(element)) return;
    clear();
    focused = { element, field };
    offer();
    fetchValues();
  };

  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === focused?.element) clear();
  };

  if (doc.readyState === "loading") doc.addEventListener("DOMContentLoaded", fetchValues, { once: true });
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
