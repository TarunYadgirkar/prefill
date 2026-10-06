import { parseAutocomplete, type AutocompleteDetail } from "./autocomplete";
import { inferredLabel, isRendered, placeholderText, splitNames } from "./dom";
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
import {
  GENERIC_LINK,
  LINK_WORDS,
  NOT_PHONE,
  OTHER_LINKS,
  RULES,
  SENSITIVE as SENSITIVE_PATTERNS,
  type RuleResult,
} from "./patterns";

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

const SENSITIVE_FIELDS: ReadonlySet<string> = new Set([
  "new-password",
  "current-password",
  "one-time-code",
]);
const SECTION_CONTACTS: ReadonlySet<string> = new Set(["home", "work"]);

// A field as plain data: what the DOM says about it, or what the Mac app reads from the
// field through Accessibility, which has no DOM to ask.
export interface FieldDescription {
  tag: "input" | "select" | "textarea";
  // The input type; ignored for selects and text areas.
  type: string;
  autocomplete: string | null;
  label: string;
  // The name and id as written.
  names: readonly string[];
  placeholder: string;
  signIn: boolean;
}

function controlOf(field: FieldDescription): ControlOrVerdict {
  if (field.tag === "select") return "select";
  if (field.tag === "textarea") return "textarea";
  return INPUT_CONTROLS[field.type.toLowerCase()] ?? "ignored";
}

function sectionOf(
  detail: AutocompleteDetail | undefined,
): SectionHint | undefined {
  if (detail?.contact !== undefined && SECTION_CONTACTS.has(detail.contact))
    return detail.contact as SectionHint;
  return detail?.mode;
}

function contact(mapped: Mapped, detail?: AutocompleteDetail): ContactField {
  const section = sectionOf(detail);
  const group = [detail?.section, detail?.mode].filter(Boolean).join(" ");
  return { ...mapped, group, ...(section === undefined ? {} : { section }) };
}

// The link types the words name, in the order they name them: "GitHub/Portfolio" asks for
// a GitHub link first, then a website.
// "Other website" asks for the other link, so the words "other" claims don't name a website too.
function linkTypesIn(texts: readonly string[]): LinkType[] {
  const other = LINK_WORDS.find(([type]) => type === "other")?.[1];
  const found = LINK_WORDS.flatMap(([type, pattern]) => {
    const searched =
      type === "website" && other !== undefined
        ? texts.map((text) =>
            text.replace(other, (match) => " ".repeat(match.length)),
          )
        : texts;
    const at = Math.min(
      ...searched
        .map((text) => text.search(pattern))
        .filter((index) => index >= 0),
    );
    return Number.isFinite(at) ? [{ type, at }] : [];
  });
  return found
    .sort((first, second) => first.at - second.at)
    .map(({ type }) => type);
}

// Words that name no link type ask for a website, unless they name something else.
function link(texts: readonly string[]): Classification {
  const named = linkTypesIn(texts);
  if (named.length > 0) return { kind: "link", group: "", linkTypes: named };
  const isDocument = texts.some(
    (text) =>
      OTHER_LINKS.test(text) &&
      !GENERIC_LINK.test(text.replace(OTHER_LINKS, "")),
  );
  return isDocument
    ? IGNORED
    : { kind: "link", group: "", linkTypes: ["website"] };
}

function fromAutocomplete(
  detail: AutocompleteDetail,
  control: Control,
  sources: readonly string[][],
): Classification {
  if (detail.field === "url") return link(sources.flat());
  if (SENSITIVE_FIELDS.has(detail.field) || detail.field.startsWith("cc-"))
    return SENSITIVE;
  if (detail.field === "username")
    return control === "email" ? contact({ kind: "email" }, detail) : IGNORED;
  const mapped = AUTOCOMPLETE_FIELDS[detail.field];
  return mapped === undefined ? IGNORED : contact(mapped, detail);
}

function fromRule(
  result: RuleResult,
  texts: readonly string[],
): Classification {
  if (result.kind === "link") return link(texts);
  return result.kind === "ignored" ? IGNORED : contact(result);
}

// A source's texts are its raw and split forms, so a negative that matches any of them
// (the "ext" in "phone ext") rules the source out.
// A label that is a whole question ("Has your license ever been revoked? If yes, state the
// reason") names what it asks for near its start, so a word deep in the sentence doesn't
// make it an address, name or phone field.
const QUESTION_WORDS = 8;
const QUESTION_HEAD = 40;
const PART_KINDS: ReadonlySet<RuleResult["kind"]> = new Set(["address", "name", "phone"]);

function headOf(text: string, kind: RuleResult["kind"]): string {
  const isQuestion = text.split(/\s+/u).length >= QUESTION_WORDS;
  return isQuestion && PART_KINDS.has(kind) ? text.slice(0, QUESTION_HEAD) : text;
}

const WHOLE_ADDRESS_PARTS: ReadonlySet<string> = new Set(["city", "state", "postalCode"]);

// One box for "Address (City – State – ZIP)" takes the whole address, starting at the street.
function isWholeAddress(texts: readonly string[], control: Control): boolean {
  if (control !== "text" && control !== "textarea") return false;
  const parts = RULES.filter(
    (rule) =>
      rule.result.kind === "address" &&
      WHOLE_ADDRESS_PARTS.has(rule.result.part) &&
      texts.some((text) => rule.pattern.test(text)),
  );
  return parts.length >= 2 && texts.some((text) => /address/iu.test(text));
}

function matchRules(
  texts: readonly string[],
  control: Control,
): Classification | undefined {
  if (isWholeAddress(texts, control))
    return contact({ kind: "address", part: "street" });
  const rule = RULES.find(
    (candidate) =>
      candidate.controls.includes(control) &&
      texts.some((text) =>
        candidate.pattern.test(headOf(text, candidate.result.kind)),
      ) &&
      !texts.some((text) => candidate.negative?.test(text) === true),
  );
  return rule === undefined ? undefined : fromRule(rule.result, texts);
}

function sourcesOf(field: FieldDescription): string[][] {
  return [[field.label], splitNames(field.names), [field.placeholder]].map(
    (texts) => texts.filter(Boolean),
  );
}

export function isSensitiveText(sources: readonly string[][]): boolean {
  return sources
    .flat()
    .some((text) => SENSITIVE_PATTERNS.some((pattern) => pattern.test(text)));
}

// Label first, then name and id, then placeholder: the first source that matches a
// pattern decides, the way a person reading the form would.
function fromPatterns(
  sources: readonly string[][],
  control: Control,
): Classification | undefined {
  for (const texts of sources) {
    const match = matchRules(texts, control);
    if (match !== undefined) return match;
  }
  return undefined;
}

function positive(
  field: FieldDescription,
  control: Control,
  sources: readonly string[][],
): Classification {
  const detail = parseAutocomplete(field.autocomplete);
  if (detail !== undefined) return fromAutocomplete(detail, control, sources);
  if (control === "email") return contact({ kind: "email" });
  return (
    fromPatterns(sources, control) ?? (control === "url" ? link([]) : IGNORED)
  );
}

// Sensitive words first, whatever the tags say, then autocomplete tokens (WHATWG grammar),
// then the input type, then label, name and id patterns. `type=tel` alone proves nothing:
// stores use it for ZIP codes, and banks for account numbers and codes, so a phone also
// needs a tel token or phone words, and none of the words that mark something else.
// Sign-in forms belong to Passwords: Prefill stays off them so Safari's saved logins own
// the bar. Sign-up forms stay in, since that is where new emails and phones show up.
// A field outside any form belongs to the nearest few ancestors that hold a password box,
// which is how single-page apps build their sign-in screens.
const SIGN_IN_LEVELS = 5;
const NOT_TYPED =
  /^(?:hidden|checkbox|radio|submit|button|image|reset|file|password)$/iu;
const SIGN_IN_WORDS =
  /sign.?in|log.?in|anmelden|iniciar sesi|connexion|se connecter|ログイン|登录/iu;

function signInScope(el: FieldElement): ParentNode | undefined {
  if (el.form !== null) return el.form;
  let scope = el.parentElement;
  for (let level = 0; scope !== null && level < SIGN_IN_LEVELS; level += 1) {
    if (scope.querySelector("input[type=password]") !== null) return scope;
    scope = scope.parentElement;
  }
  return undefined;
}

const isTypedBox = (field: Element): boolean =>
  field.localName !== "input" ||
  !NOT_TYPED.test((field as HTMLInputElement).type);

// Without tokens: one visible password box beside one other box, under a button that says
// sign in or log in.
function looksLikeSignIn(scope: ParentNode): boolean {
  const passwords = [...scope.querySelectorAll("input[type=password]")].filter(
    isRendered,
  );
  if (
    passwords.length !== 1 ||
    /new-password/iu.test(passwords[0]?.getAttribute("autocomplete") ?? "")
  )
    return false;
  if (
    [...scope.querySelectorAll("input, select, textarea")].filter(isTypedBox)
      .length > 1
  )
    return false;
  return [...scope.querySelectorAll("button, input[type=submit]")].some(
    (button) =>
      SIGN_IN_WORDS.test(
        `${button.textContent} ${button.getAttribute("value") ?? ""}`,
      ),
  );
}

export function isSignIn(el: FieldElement): boolean {
  if (/\bwebauthn\b/iu.test(el.getAttribute("autocomplete") ?? "")) return true;
  const scope = signInScope(el);
  if (scope === undefined) return false;
  return (
    scope.querySelector('input[autocomplete~="current-password" i]') !== null ||
    looksLikeSignIn(scope)
  );
}

export function describe(el: FieldElement): FieldDescription {
  return {
    tag:
      el.localName === "select"
        ? "select"
        : el.localName === "textarea"
          ? "textarea"
          : "input",
    type: el.type,
    autocomplete: el.getAttribute("autocomplete"),
    label: inferredLabel(el),
    names: [el.getAttribute("name") ?? "", el.id].filter(Boolean),
    placeholder: placeholderText(el),
    signIn: isSignIn(el),
  };
}

export function classify(el: FieldElement): Classification {
  return classifyDescription(describe(el));
}

export function classifyDescription(field: FieldDescription): Classification {
  const control = controlOf(field);
  if (control === "sensitive" || control === "ignored")
    return { kind: control };
  if (field.signIn) return IGNORED;
  const sources = sourcesOf(field);
  if (isSensitiveText(sources)) return SENSITIVE;
  const found = positive(field, control, sources);
  if (
    found.kind === "phone" &&
    sources.flat().some((text) => NOT_PHONE.test(text))
  )
    return SENSITIVE;
  return found;
}
