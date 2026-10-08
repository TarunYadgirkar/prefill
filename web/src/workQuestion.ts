// Sponsorship and work authorization answers are usually opposite ("No" and "Yes"), so a
// question must clearly be one of them before either answer goes in. Mirrors
// CustomFieldMatcher.workQuestion in PrefillKit.

export type WorkQuestion = "authorization" | "sponsorship" | "both";

// "require sponsorship", "visa sponsorship", "H-1B".
const SPONSORSHIP = /sponsor|\bh-?1b\b|\bvisa\b/iu;
// "Are you authorized to work", "legally eligible", "the right to work". "Sponsorship for work
// authorization" asks about sponsorship, so "work authorization" alone doesn't count.
const AUTHORIZED = /\b(?:authori[sz]ed|eligible|permitted|entitled|able)\s+to\s+work\b|\bright to work\b|\blegally (?:authori[sz]ed|eligible|permitted)\b/iu;

export function workQuestion(text: string): WorkQuestion | undefined {
  const sponsorship = SPONSORSHIP.test(text);
  const authorized = AUTHORIZED.test(text);
  if (sponsorship && authorized) return "both";
  if (sponsorship) return "sponsorship";
  return authorized ? "authorization" : undefined;
}

// Whether a saved answer with this label may answer the question: Sponsorship only a
// sponsorship question, Work authorization only a question without sponsorship words, and
// neither one that asks both.
export function fitsWorkQuestion(label: string, text: string): boolean {
  const asked = workQuestion(text);
  if (label === "Sponsorship") return asked === "sponsorship";
  if (label === "Work authorization") return asked !== "sponsorship" && asked !== "both";
  return true;
}
