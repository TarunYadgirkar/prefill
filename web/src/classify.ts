import { parseAutocomplete, type AutocompleteDetail } from "./autocomplete";
import { labelText, nameTexts, placeholderText } from "./dom";
import {
  IGNORED,
  SENSITIVE,
  type Classification,
  type ContactField,
  type Control,
  type FieldElement,
  type FieldPart,
} from "./fieldTypes";
import type { FieldKind, SectionHint } from "./messages";
import { RULES, SENSITIVE as SENSITIVE_PATTERNS, type RuleResult } from "./patterns";

type ControlOrVerdict = Control | "sensitive" | "ignored";

const INPUT_CONTROLS: Readonly<Record<string, ControlOrVerdict>> = {
  text: "text",
  email: "email",
  tel: "tel",
  number: "number",
  password: "sensitive",
};

interface Mapped {
  kind: FieldKind;
  part?: FieldPart;
}

const AUTOCOMPLETE_FIELDS: Readonly<Record<string, Mapped>> = {
  email: { kind: "email" },
  tel: { kind: "phone" },
  "tel-national": { kind: "phone" },
  "tel-country-code": { kind: "phone", part: "partial" },
  "tel-area-code": { kind: "phone", part: "partial" },
  "tel-local": { kind: "phone", part: "partial" },
  "tel-local-prefix": { kind: "phone", part: "partial" },
  "tel-local-suffix": { kind: "phone", part: "partial" },
  "tel-extension": { kind: "phone", part: "partial" },
  name: { kind: "name", part: "full" },
  "given-name": { kind: "name", part: "given" },
  "additional-name": { kind: "name", part: "middle" },
  "family-name": { kind: "name", part: "family" },
  "street-address": { kind: "address", part: "street" },
  "address-line1": { kind: "address", part: "street" },
  "address-line2": { kind: "address", part: "street2" },
  "address-line3": { kind: "address", part: "street2" },
  "address-level2": { kind: "address", part: "city" },
  "address-level1": { kind: "address", part: "state" },
  "postal-code": { kind: "address", part: "postalCode" },
  country: { kind: "address", part: "country" },
  "country-name": { kind: "address", part: "country" },
};

const SENSITIVE_FIELDS: ReadonlySet<string> = new Set(["new-password", "current-password", "one-time-code"]);
const SECTION_CONTACTS: ReadonlySet<string> = new Set(["home", "work"]);

function controlOf(el: FieldElement): ControlOrVerdict {
  if (el.localName === "select") return "select";
  if (el.localName === "textarea") return "textarea";
  return INPUT_CONTROLS[el.type.toLowerCase()] ?? "ignored";
}

function sectionOf(detail: AutocompleteDetail | undefined): SectionHint | undefined {
  if (detail?.contact !== undefined && SECTION_CONTACTS.has(detail.contact)) return detail.contact as SectionHint;
  return detail?.mode;
}

function contact(mapped: Mapped, detail?: AutocompleteDetail): ContactField {
  const section = sectionOf(detail);
  const group = [detail?.section, detail?.mode].filter(Boolean).join(" ");
  return { ...mapped, group, ...(section === undefined ? {} : { section }) };
}

function fromAutocomplete(detail: AutocompleteDetail, control: Control): Classification {
  if (SENSITIVE_FIELDS.has(detail.field) || detail.field.startsWith("cc-")) return SENSITIVE;
  // Sign-in forms tag an email box "username"; it still holds one of the person's emails.
  if (detail.field === "username") return control === "email" ? contact({ kind: "email" }, detail) : IGNORED;
  const mapped = AUTOCOMPLETE_FIELDS[detail.field];
  return mapped === undefined ? IGNORED : contact(mapped, detail);
}

function fromRule(result: RuleResult): Classification {
  return result.kind === "ignored" ? IGNORED : contact(result);
}

function matchRules(texts: readonly string[], control: Control): Classification | undefined {
  const rule = RULES.find(
    (candidate) =>
      candidate.controls.includes(control) &&
      texts.some((text) => candidate.pattern.test(text) && candidate.negative?.test(text) !== true),
  );
  return rule === undefined ? undefined : fromRule(rule.result);
}

// Label first, then name and id, then placeholder: the first source that matches a
// pattern decides, the way a person reading the form would.
function fromPatterns(el: FieldElement, control: Control): Classification | undefined {
  const sources = [[labelText(el)], nameTexts(el), [placeholderText(el)]].map((texts) => texts.filter(Boolean));
  const all = sources.flat();
  if (all.some((text) => SENSITIVE_PATTERNS.some((pattern) => pattern.test(text)))) return SENSITIVE;
  for (const texts of sources) {
    const match = matchRules(texts, control);
    if (match !== undefined) return match;
  }
  return undefined;
}

// Autocomplete tokens first (WHATWG grammar), then the input type, then label, name and
// id patterns. `type=tel` alone is only trusted when no pattern says otherwise, because
// some stores use it for ZIP codes.
export function classify(el: FieldElement): Classification {
  const control = controlOf(el);
  if (control === "sensitive" || control === "ignored") return { kind: control };
  const detail = parseAutocomplete(el.getAttribute("autocomplete"));
  if (detail !== undefined) return fromAutocomplete(detail, control);
  if (control === "email") return contact({ kind: "email" });
  return fromPatterns(el, control) ?? (control === "tel" ? contact({ kind: "phone" }) : IGNORED);
}
