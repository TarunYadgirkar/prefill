import type { Why } from "./messages";

// The line under each value in Prefill's lists, from why the app offered it, so the field's
// list, a filled field's list and the Mac panel all say the same words.

export const GUESS_DETAIL = "Suggested";
export const USED_DETAIL = "Used here";
export const RESUME_DETAIL = "From your resume";

const DETAILS: Readonly<Record<Why, (site: string | undefined) => string | undefined>> = {
  pinned: () => USED_DETAIL,
  used: () => USED_DETAIL,
  card: () => undefined,
  learned: (site) => (site === undefined ? undefined : `From ${site}`),
  guess: () => GUESS_DETAIL,
  resume: () => RESUME_DETAIL,
};

// `plain` says what the value is ("Work email", "LinkedIn", "School"), for a value that's
// simply the person's own.
export function whyDetail(offered: { why: Why; site?: string }, plain: string): string {
  return DETAILS[offered.why](offered.site) ?? plain;
}

// A card value under its label: "Work email", "Home address", "Mobile phone", or "iPhone"
// when the label already says the kind. `kind` is the capitalized kind word, the detail
// for an unlabeled value.
export function labelled(label: string | undefined, kind: string): string {
  const trimmed = label?.trim() ?? "";
  if (trimmed === "") return kind;
  const word = kind.toLowerCase();
  // Contacts' own labels come lowercase ("work"); one with capitals ("iPhone") is kept as written.
  const shown = trimmed === trimmed.toLowerCase() ? trimmed.charAt(0).toUpperCase() + trimmed.slice(1) : trimmed;
  return trimmed.toLowerCase().includes(word) ? shown : `${shown} ${word}`;
}
