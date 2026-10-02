import type { FieldKind, LinkType, SectionHint } from "./messages";

export type AddressPart = "street" | "street2" | "city" | "state" | "postalCode" | "country";
export type NamePart = "full" | "given" | "middle" | "family";
export type FieldPart = AddressPart | NamePart | "partial";

// The kind of control a pattern may apply to, after the input type is read.
export type Control = "text" | "email" | "tel" | "number" | "select" | "textarea" | "url";

export interface ContactField {
  kind: FieldKind;
  part?: FieldPart;
  section?: SectionHint;
  // Fields with the same group belong to the same address: the autocomplete section-*
  // name plus shipping or billing. Empty when the page gave no tokens.
  group: string;
  // For a link field, the kinds of link it asks for, in the order its words name them.
  linkTypes?: readonly LinkType[];
}

export type Classification = ContactField | { kind: "sensitive" } | { kind: "ignored" };

export type FieldElement = HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement;

export const SENSITIVE: Classification = { kind: "sensitive" };
export const IGNORED: Classification = { kind: "ignored" };

export function isContact(classification: Classification): classification is ContactField {
  return classification.kind !== "sensitive" && classification.kind !== "ignored";
}
