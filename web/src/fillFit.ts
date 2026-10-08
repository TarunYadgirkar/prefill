import { classify } from "./classify";
import { isRendered } from "./dom";
import type { Choice } from "./dropdown";
import type { FieldElement, FieldPart } from "./fieldTypes";

// How a one-tap fill fits a value to the box a page drew for it.

// A page's helper behind a box the person sees (Workable's city, postcode and country behind
// its one address box): hidden from screen readers and out of the tab order. Only the page
// writes there.
export const isHelper = (element: Element): boolean =>
  element.getAttribute("aria-hidden") === "true" && element.getAttribute("tabindex") === "-1";

// A phone box drawn with a country-code picker (Tally's) calls itself a combobox, but the
// number is typed into it.
export const isPhoneBox = (element: Element): boolean =>
  element.localName === "input" && (element as HTMLInputElement).type === "tel";

function maxLengthOf(element: Element): number {
  const max = Number.parseInt(element.getAttribute("maxlength") ?? "", 10);
  return Number.isNaN(max) || max <= 0 ? Number.POSITIVE_INFINITY : max;
}

// A script's value isn't cut to maxlength, so a box that takes 10 characters gets the number
// as saved when it fits, else without "+1", else digits only; none when nothing fits.
export function fitPhone(value: string, maxLength: number): string | undefined {
  if (value.length <= maxLength) return value;
  const national = value.replace(/^\s*\+1\b\s*/u, "");
  return [national, national.replace(/\D/gu, ""), value.replace(/\D/gu, "")].find(
    (way) => way !== "" && way.length <= maxLength,
  );
}

// A US-style mask ("(000) 000-0000", "XXX-XXX-XXXX") or the "tel-national" token asks for
// the number without its country code.
const NATIONAL_MASK = /^[\s(]*[0X9#]{3}[)\s.-]*[0X9#]{3}[\s.-]*[0X9#]{4}\s*$/iu;

function asksNational(element: Element): boolean {
  const tokens = (element.getAttribute("autocomplete") ?? "").toLowerCase().split(/\s+/u);
  return tokens.includes("tel-national") || NATIONAL_MASK.test(element.getAttribute("placeholder") ?? "");
}

// The number as the country's own: "+1 (510) 555-0134" is "(510) 555-0134". Another country's
// number has no form such a box takes, so it gets none rather than a part of one.
function nationalPhone(value: string): string | undefined {
  if (!value.trim().startsWith("+")) return value;
  const national = value.replace(/^\s*\+1\b\s*/u, "");
  return national.startsWith("+") ? undefined : national;
}

export function fitPhones(element: Element, choices: readonly Choice[]): Choice[] {
  const max = maxLengthOf(element);
  const national = asksNational(element);
  return choices.flatMap((choice) => {
    const local = national ? nationalPhone(choice.value) : choice.value;
    const value = local === undefined ? undefined : fitPhone(local, max);
    return value === undefined ? [] : [{ ...choice, value }];
  });
}

// Boxes that split an address: with one of these on the form, the address box is the street.
const SPLIT_PARTS: ReadonlySet<FieldPart> = new Set(["street2", "city", "state", "postalCode"]);

function addressPart(element: FieldElement): FieldPart | undefined {
  if (!isRendered(element) || isHelper(element)) return undefined;
  const field = classify(element);
  return field.kind === "address" ? (field.part ?? "street") : undefined;
}

// A form with an address box and no city, state or postal code boxes (Workable's) wants the
// whole address in that one box.
export function isOneBoxAddress(elements: readonly FieldElement[]): boolean {
  const parts = elements.flatMap((element) => addressPart(element) ?? []);
  return parts.includes("street") && !parts.some((part) => SPLIT_PARTS.has(part));
}
