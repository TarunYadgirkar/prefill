import { classify } from "./classify";
import { eventOrigin, hasOwnList, fieldElements, isFieldElement } from "./dom";
import type { Attach, Choice, TextField } from "./dropdown";
import { onEmptied, trackGestures } from "./gesture";
import { reportPick } from "./picks";
import { labelled, whyDetail } from "./why";
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
  // Safari's bar already offers the card's name, so in Safari name fields get no second list.
  skipNames?: boolean;
  // Only events the browser made count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
  now?: () => number;
  // Draws Prefill's list under the field (showDropdown in pages).
  attach: Attach;
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
  // One box for the whole address: "2400 Durant Ave, Berkeley, CA 94704".
  full: (address) =>
    [address.street.split("\n")[0] ?? "", address.city, `${address.state} ${address.postalCode}`.trim()]
      .filter((part) => part.trim() !== "")
      .join(", "),
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

// The list a contact field shows, each value saying why it's there. `onPick` hears about
// a pick worth remembering: one that wasn't first, of a kind the app pins.
export function contactChoices(
  field: ContactField,
  values: Suggestions,
  onPick?: (kind: PickedRequest["kind"], value: string) => void,
): Choice[] {
  const kind = pickKind(field);
  const word = KIND_LABELS[field.kind] ?? "";
  return suggestionOptions(field, values).map((offered, index) => {
    const choice = { value: offered.value, detail: whyDetail(offered, labelled(offered.label, word)) };
    return kind === undefined || onPick === undefined || index === 0
      ? choice
      : { ...choice, onPick: () => { onPick(kind, offered.value); } };
  });
}

function isTextField(element: FieldElement): element is TextField {
  if (element.localName === "textarea") return true;
  return (
    element.localName === "input" &&
    LIST_INPUTS.has((element as HTMLInputElement).type.toLowerCase())
  );
}

function suggestedField(element: FieldElement): ContactField | undefined {
  if (!isTextField(element)) return undefined;
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

// Offers the person's emails, phone numbers, addresses and name in Prefill's own list, from
// the card and Prefill's contact alike, in every browser. The values are fetched when the
// page loads, ranked for the site, and a field gets its list when the person focuses it; the
// list goes away when the field loses focus. A field with a list of its own is left alone.
export function installSuggestions(
  doc: Document,
  options: SuggestionOptions,
): () => void {
  const isUserEvent =
    options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const attach = options.attach;
  // Prefill's own list would sit on top of the page's, so it skips fields that have one.
  const isTaken = (element: FieldElement): boolean =>
    options.skip?.(element) === true || hasOwnList(element);
  const fieldOf = (element: FieldElement): ContactField | undefined => {
    const field = suggestedField(element);
    return field?.kind === "name" && options.skipNames === true ? undefined : field;
  };
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
    const choices = contactChoices(focused.field, known, picked);
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
      })
      .then((reply) => {
        const response = parseExtensionResponse(reply);
        if (response?.type !== "contactSuggestionsResult") return;
        // A pick in Safari's sheet changes the order after the page loaded, so an open list
        // that the fresh reply reorders is drawn again.
        const changed = known !== undefined && JSON.stringify(known) !== JSON.stringify(response);
        known = response;
        if (changed && detach !== undefined) {
          detach();
          detach = undefined;
        }
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

  const show = (target: FieldElement): void => {
    if (detach !== undefined || isTaken(target) || !isTextField(target)) return;
    const field = fieldOf(target);
    if (field === undefined) return;
    clear();
    focused = { element: target, field };
    offer();
    fetchValues();
  };

  // The field the person tapped or tabbed into, even one Prefill filled, so emptying it
  // brings its list back.
  let armed: FieldElement | undefined;
  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || fieldOf(target) === undefined || !gestures.allows(target)) return;
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
    doc.addEventListener("DOMContentLoaded", fetchValues, { once: true });
  else fetchValues();
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    gestures.stop();
    stopEmptied();
    doc.removeEventListener("DOMContentLoaded", fetchValues);
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
