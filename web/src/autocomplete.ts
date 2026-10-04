// The WHATWG autofill detail tokens, read right to left: an optional trailing "webauthn",
// the field name, an optional contact token (only before a tel, email or impp name),
// an optional shipping or billing, then an optional section-* name.
// https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#autofill-detail-tokens

export type ContactToken = "home" | "work" | "mobile" | "fax" | "pager";
export type AddressMode = "shipping" | "billing";

export interface AutocompleteDetail {
  field: string;
  contact?: ContactToken;
  mode?: AddressMode;
  section?: string;
}

const CONTACT_TOKENS: ReadonlySet<string> = new Set([
  "home",
  "work",
  "mobile",
  "fax",
  "pager",
]);

const CONTACT_FIELDS: ReadonlySet<string> = new Set([
  "tel",
  "tel-country-code",
  "tel-national",
  "tel-area-code",
  "tel-local",
  "tel-local-prefix",
  "tel-local-suffix",
  "tel-extension",
  "email",
  "impp",
]);

const OTHER_FIELDS = [
  "name",
  "honorific-prefix",
  "given-name",
  "additional-name",
  "family-name",
  "honorific-suffix",
  "nickname",
  "username",
  "new-password",
  "current-password",
  "one-time-code",
  "organization-title",
  "organization",
  "street-address",
  "address-line1",
  "address-line2",
  "address-line3",
  "address-level4",
  "address-level3",
  "address-level2",
  "address-level1",
  "country",
  "country-name",
  "postal-code",
  "cc-name",
  "cc-given-name",
  "cc-additional-name",
  "cc-family-name",
  "cc-number",
  "cc-exp",
  "cc-exp-month",
  "cc-exp-year",
  "cc-csc",
  "cc-type",
  "transaction-currency",
  "transaction-amount",
  "language",
  "bday",
  "bday-day",
  "bday-month",
  "bday-year",
  "sex",
  "url",
  "photo",
];

const FIELD_NAMES: ReadonlySet<string> = new Set([
  ...OTHER_FIELDS,
  ...CONTACT_FIELDS,
]);

type Step = (
  detail: AutocompleteDetail,
  token: string,
) => AutocompleteDetail | undefined;

const contactStep: Step = (detail, token) =>
  CONTACT_TOKENS.has(token) && CONTACT_FIELDS.has(detail.field)
    ? { ...detail, contact: token as ContactToken }
    : undefined;

const modeStep: Step = (detail, token) =>
  token === "shipping" || token === "billing"
    ? { ...detail, mode: token }
    : undefined;

const sectionStep: Step = (detail, token) =>
  token.startsWith("section-") && token.length > "section-".length
    ? { ...detail, section: token }
    : undefined;

// Each optional token may appear at most once and only in this order, right to left.
const STEPS: readonly Step[] = [contactStep, modeStep, sectionStep];

// Returns undefined for an absent, empty, "on", "off" or otherwise invalid value, which
// sends the field on to the input type and pattern checks.
export function parseAutocomplete(
  raw: string | null,
): AutocompleteDetail | undefined {
  const tokens = (raw ?? "").trim().toLowerCase().split(/\s+/u).filter(Boolean);
  if (tokens.at(-1) === "webauthn") tokens.pop();
  const field = tokens.pop();
  if (field === undefined || !FIELD_NAMES.has(field)) return undefined;
  let detail: AutocompleteDetail = { field };
  let stepIndex = 0;
  for (const token of tokens.reverse()) {
    const next = applyFirstStep(detail, token, stepIndex);
    if (next === undefined) return undefined;
    detail = next.detail;
    stepIndex = next.stepIndex;
  }
  return detail;
}

function applyFirstStep(
  detail: AutocompleteDetail,
  token: string,
  from: number,
): { detail: AutocompleteDetail; stepIndex: number } | undefined {
  for (let index = from; index < STEPS.length; index += 1) {
    const next = STEPS[index]?.(detail, token);
    if (next !== undefined) return { detail: next, stepIndex: index + 1 };
  }
  return undefined;
}
