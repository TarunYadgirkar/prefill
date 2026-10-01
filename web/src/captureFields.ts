import { labelText, placeholderText } from "./dom";
import type { AddressPart, ContactField, FieldElement } from "./fieldTypes";
import type { CaptureRequest, CapturedField, PostalAddress } from "./messages";

export interface EditedField {
  element: FieldElement;
  field: ContactField;
  value: string;
}

type Description = Pick<CapturedField, "autocomplete" | "name" | "label">;

interface AddressDraft {
  group: string;
  parts: Partial<Record<AddressPart, string>>;
  members: readonly EditedField[];
}

const MAX_VALUE = 256;

function nonEmpty(entries: Record<string, string>): Record<string, string> {
  return Object.fromEntries(Object.entries(entries).filter(([, value]) => value !== ""));
}

function describe(members: readonly EditedField[]): Description {
  const first = members[0]?.element;
  return nonEmpty({
    autocomplete: first?.getAttribute("autocomplete")?.trim() ?? "",
    name: members.map(({ element }) => element.getAttribute("name") ?? element.id).filter(Boolean).join(" "),
    label: members.map(({ element }) => labelText(element) || placeholderText(element)).filter(Boolean).join(", "),
  });
}

function withSection(field: CapturedField, members: readonly EditedField[]): CapturedField {
  const section = members.find((member) => member.field.section !== undefined)?.field.section;
  return section === undefined ? field : { ...field, section };
}

function single(entry: EditedField): CapturedField {
  const field: CapturedField = { kind: entry.field.kind, value: entry.value, ...describe([entry]) };
  return withSection(field, [entry]);
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

function addressField(draft: AddressDraft): CapturedField[] {
  const { parts } = draft;
  const street = [parts.street, parts.street2].filter(Boolean).join("\n");
  if (street === "") return [];
  const address: PostalAddress = {
    street,
    city: parts.city ?? "",
    state: parts.state ?? "",
    postalCode: parts.postalCode ?? "",
    country: parts.country ?? "",
  };
  return [withSection({ kind: "address", address, ...describe(draft.members) }, draft.members)];
}

function assemble(entries: readonly EditedField[]): CapturedField[] {
  const fields: CapturedField[] = [];
  let draft: AddressDraft | undefined;
  for (const entry of entries) {
    if (entry.field.kind !== "address") {
      fields.push(single(entry));
      continue;
    }
    if (draft !== undefined && startsNew(draft, entry)) {
      fields.push(...addressField(draft));
      draft = undefined;
    }
    draft = addPart(draft, entry);
  }
  return draft === undefined ? fields : [...fields, ...addressField(draft)];
}

// Names alone are never saved, so a form with nothing else typed sends nothing.
export function buildCapture(
  host: string,
  hasPassword: boolean,
  entries: readonly EditedField[],
): CaptureRequest | undefined {
  const typed = entries
    .map((entry) => ({ ...entry, value: entry.value.slice(0, MAX_VALUE) }))
    .filter((entry) => entry.value !== "");
  const fields = assemble(typed);
  if (!fields.some((field) => field.kind !== "name")) return undefined;
  return { type: "capture", host, hasPassword, fields };
}
