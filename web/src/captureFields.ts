import { labelText, placeholderText } from "./dom";
import type { AddressPart, ContactField, FieldElement } from "./fieldTypes";
import {
  HIDDEN_CHARACTERS,
  HIDDEN_EXCEPT_NEWLINE,
  LIMITS, type CaptureRequest, type CaptureTrigger, type CapturedField, type PostalAddress } from "./messages";

export interface FieldDescription {
  autocomplete: string;
  name: string;
  label: string;
}

export interface EditedField {
  field: ContactField;
  description: FieldDescription;
  value: string;
}

interface AddressDraft {
  group: string;
  parts: Partial<Record<AddressPart, string>>;
  members: readonly EditedField[];
}

const clip = (text: string, max: number): string => text.slice(0, max);
const ALL_HIDDEN = new RegExp(HIDDEN_CHARACTERS.source, "gu");

// Soft hyphens and direction marks are common in labels and would fail the whole
// message, so the words used only for classifying lose them.
const visible = (text: string): string => text.replace(/\s+/gu, " ").replace(ALL_HIDDEN, "").trim();

// Read from the DOM when the person types, so a report never touches an element the
// page may have removed since.
export function describeElement(element: FieldElement): FieldDescription {
  return {
    autocomplete: visible(element.getAttribute("autocomplete") ?? ""),
    name: visible(element.getAttribute("name") ?? element.id),
    label: visible(labelText(element) || placeholderText(element)),
  };
}

// A value with hidden characters can't be sent as typed, so its field is left out. A
// street typed in a text area may span lines.
function hasHidden(entry: EditedField): boolean {
  const isStreet = entry.field.part === "street" || entry.field.part === "street2";
  return (isStreet ? HIDDEN_EXCEPT_NEWLINE : HIDDEN_CHARACTERS).test(entry.value);
}

function nonEmpty(entries: Record<string, string>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(entries)
      .map(([key, value]): [string, string] => [key, clip(value, LIMITS.text)])
      .filter(([, value]) => value !== ""),
  );
}

function describe(members: readonly EditedField[]): Pick<CapturedField, "autocomplete" | "name" | "label"> {
  const descriptions = members.map((member) => member.description);
  return nonEmpty({
    autocomplete: descriptions[0]?.autocomplete ?? "",
    name: descriptions
      .map((description) => description.name)
      .filter(Boolean)
      .join(" "),
    label: descriptions
      .map((description) => description.label)
      .filter(Boolean)
      .join(", "),
  });
}

function withSection(field: CapturedField, members: readonly EditedField[]): CapturedField {
  const section = members.find((member) => member.field.section !== undefined)?.field.section;
  return section === undefined ? field : { ...field, section };
}

function single(entry: EditedField): CapturedField[] {
  if (hasHidden(entry)) return [];
  const field: CapturedField = {
    kind: entry.field.kind,
    value: clip(entry.value, LIMITS.value),
    ...describe([entry]),
    userTyped: true,
  };
  return [withSection(field, [entry])];
}

// A repeated part or a different autocomplete section starts the next address, so a
// shipping and a billing block become two addresses.
function startsNew(draft: AddressDraft, entry: EditedField): boolean {
  const part = entry.field.part as AddressPart;
  return draft.group !== entry.field.group || (part !== "street2" && draft.parts[part] !== undefined);
}

function addPart(draft: AddressDraft | undefined, entry: EditedField): AddressDraft {
  const part = entry.field.part as AddressPart;
  const base = draft ?? { group: entry.field.group, parts: {}, members: [] };
  const previous = base.parts[part];
  const value = previous === undefined ? entry.value : `${previous}\n${entry.value}`;
  return { ...base, parts: { ...base.parts, [part]: value }, members: [...base.members, entry] };
}

// An address flushed from a page that was only hidden must have its postal code too, so
// a half-typed one never leaves the page.
function isSendable(draft: AddressDraft, street: string, trigger: CaptureTrigger): boolean {
  const isIncomplete = street === "" || (trigger === "flush" && draft.parts.postalCode === undefined);
  return !isIncomplete && !draft.members.some(hasHidden);
}

function addressField(draft: AddressDraft, trigger: CaptureTrigger): CapturedField[] {
  const { parts } = draft;
  const street = [parts.street, parts.street2].filter(Boolean).join("\n");
  if (!isSendable(draft, street, trigger)) return [];
  const address: PostalAddress = {
    street: clip(street, LIMITS.street),
    city: clip(parts.city ?? "", LIMITS.part),
    state: clip(parts.state ?? "", LIMITS.part),
    postalCode: clip(parts.postalCode ?? "", LIMITS.part),
    country: clip(parts.country ?? "", LIMITS.part),
  };
  return [withSection({ kind: "address", address, ...describe(draft.members), userTyped: true }, draft.members)];
}

function assemble(entries: readonly EditedField[], trigger: CaptureTrigger): CapturedField[] {
  const fields: CapturedField[] = [];
  let draft: AddressDraft | undefined;
  for (const entry of entries) {
    if (entry.field.kind !== "address") {
      fields.push(...single(entry));
      continue;
    }
    if (draft !== undefined && startsNew(draft, entry)) {
      fields.push(...addressField(draft, trigger));
      draft = undefined;
    }
    draft = addPart(draft, entry);
  }
  return draft === undefined ? fields : [...fields, ...addressField(draft, trigger)];
}

export interface CaptureFacts {
  host: string;
  hasPassword: boolean;
  trigger: CaptureTrigger;
}

// Names alone are never saved, so a form with nothing else typed sends nothing.
export function buildCapture(facts: CaptureFacts, entries: readonly EditedField[]): CaptureRequest | undefined {
  const typed = entries.filter((entry) => entry.value !== "");
  const fields = assemble(typed, facts.trigger).slice(0, LIMITS.captureFields);
  if (!fields.some((field) => field.kind !== "name")) return undefined;
  return { type: "capture", host: facts.host, hasPassword: facts.hasPassword, trigger: facts.trigger, fields };
}
