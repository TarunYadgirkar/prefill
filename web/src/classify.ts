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
import type { FieldKind, LinkType, SectionHint } from "./messages";
import { LINK_WORDS, NOT_PHONE, OTHER_LINKS, RULES, SENSITIVE as SENSITIVE_PATTERNS, type RuleResult } from "./patterns";

type ControlOrVerdict = Control | "sensitive" | "ignored";

const INPUT_CONTROLS: Readonly<Record<string, ControlOrVerdict>> = {
  text: "text",
  email: "email",
  tel: "tel",
  number: "number",
  password: "sensitive",
  url: "url",
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

// The link types the words name, in the order they name them: "GitHub/Portfolio" asks for
// a GitHub link first, then a website.
function linkTypesIn(texts: readonly string[]): LinkType[] {
  const found = LINK_WORDS.flatMap(([type, pattern]) => {
    const at = Math.min(...texts.map((text) => text.search(pattern)).filter((index) => index >= 0));
    return Number.isFinite(at) ? [{ type, at }] : [];
  });
  return found.sort((first, second) => first.at - second.at).map(({ type }) => type);
}

// Words that name no link type ask for a website, unless they name something else.
function link(texts: readonly string[]): Classification {
  const named = linkTypesIn(texts);
  if (named.length > 0) return { kind: "link", group: "", linkTypes: named };
  return texts.some((text) => OTHER_LINKS.test(text)) ? IGNORED : { kind: "link", group: "", linkTypes: ["website"] };
}

function fromAutocomplete(detail: AutocompleteDetail, control: Control, sources: readonly string[][]): Classification {
  if (detail.field === "url") return link(sources.flat());
  if (SENSITIVE_FIELDS.has(detail.field) || detail.field.startsWith("cc-")) return SENSITIVE;
  if (detail.field === "username") return control === "email" ? contact({ kind: "email" }, detail) : IGNORED;
  const mapped = AUTOCOMPLETE_FIELDS[detail.field];
  return mapped === undefined ? IGNORED : contact(mapped, detail);
}

function fromRule(result: RuleResult, texts: readonly string[]): Classification {
  if (result.kind === "link") return link(texts);
  return result.kind === "ignored" ? IGNORED : contact(result);
}

// A source's texts are its raw and split forms, so a negative that matches any of them
// (the "ext" in "phone ext") rules the source out.
function matchRules(texts: readonly string[], control: Control): Classification | undefined {
  const rule = RULES.find(
    (candidate) =>
      candidate.controls.includes(control) &&
      texts.some((text) => candidate.pattern.test(text)) &&
      !texts.some((text) => candidate.negative?.test(text) === true),
  );
  return rule === undefined ? undefined : fromRule(rule.result, texts);
}

function sourcesOf(el: FieldElement): string[][] {
  return [[labelText(el)], nameTexts(el), [placeholderText(el)]].map((texts) => texts.filter(Boolean));
}

function isSensitiveText(sources: readonly string[][]): boolean {
  return sources.flat().some((text) => SENSITIVE_PATTERNS.some((pattern) => pattern.test(text)));
}

// Label first, then name and id, then placeholder: the first source that matches a
// pattern decides, the way a person reading the form would.
function fromPatterns(sources: readonly string[][], control: Control): Classification | undefined {
  for (const texts of sources) {
    const match = matchRules(texts, control);
    if (match !== undefined) return match;
  }
  return undefined;
}

function positive(el: FieldElement, control: Control, sources: readonly string[][]): Classification {
  const detail = parseAutocomplete(el.getAttribute("autocomplete"));
  if (detail !== undefined) return fromAutocomplete(detail, control, sources);
  if (control === "email") return contact({ kind: "email" });
  return fromPatterns(sources, control) ?? (control === "url" ? link([]) : IGNORED);
}

// Sensitive words first, whatever the tags say, then autocomplete tokens (WHATWG grammar),
// then the input type, then label, name and id patterns. `type=tel` alone proves nothing:
// stores use it for ZIP codes, and banks for account numbers and codes, so a phone also
// needs a tel token or phone words, and none of the words that mark something else.
// Sign-in forms belong to Passwords: Prefill stays off them so Safari's saved logins own
// the bar. Sign-up forms stay in, since that is where new emails and phones show up.
export function isSignIn(el: FieldElement): boolean {
  if (/\bwebauthn\b/iu.test(el.getAttribute("autocomplete") ?? "")) return true;
  return el.form?.querySelector('input[autocomplete~="current-password" i]') != null;
}

export function classify(el: FieldElement): Classification {
  const control = controlOf(el);
  if (control === "sensitive" || control === "ignored") return { kind: control };
  if (isSignIn(el)) return IGNORED;
  const sources = sourcesOf(el);
  if (isSensitiveText(sources)) return SENSITIVE;
  const found = positive(el, control, sources);
  if (found.kind === "phone" && sources.flat().some((text) => NOT_PHONE.test(text))) return SENSITIVE;
  return found;
}
