// Picks the option of a select or radio group that says the same as a saved answer:
// "CA" for "California", "Yes, I am authorized" for "Yes", "United States of America" for
// "United States". Pure functions, so every rule is easy to test.

export interface Option {
  text: string;
  value: string;
}

const US_STATES: readonly (readonly [string, string])[] = [
  ["AL", "Alabama"], ["AK", "Alaska"], ["AZ", "Arizona"], ["AR", "Arkansas"], ["CA", "California"],
  ["CO", "Colorado"], ["CT", "Connecticut"], ["DE", "Delaware"], ["DC", "District of Columbia"],
  ["FL", "Florida"], ["GA", "Georgia"], ["HI", "Hawaii"], ["ID", "Idaho"], ["IL", "Illinois"],
  ["IN", "Indiana"], ["IA", "Iowa"], ["KS", "Kansas"], ["KY", "Kentucky"], ["LA", "Louisiana"],
  ["ME", "Maine"], ["MD", "Maryland"], ["MA", "Massachusetts"], ["MI", "Michigan"], ["MN", "Minnesota"],
  ["MS", "Mississippi"], ["MO", "Missouri"], ["MT", "Montana"], ["NE", "Nebraska"], ["NV", "Nevada"],
  ["NH", "New Hampshire"], ["NJ", "New Jersey"], ["NM", "New Mexico"], ["NY", "New York"],
  ["NC", "North Carolina"], ["ND", "North Dakota"], ["OH", "Ohio"], ["OK", "Oklahoma"], ["OR", "Oregon"],
  ["PA", "Pennsylvania"], ["PR", "Puerto Rico"], ["RI", "Rhode Island"], ["SC", "South Carolina"],
  ["SD", "South Dakota"], ["TN", "Tennessee"], ["TX", "Texas"], ["UT", "Utah"], ["VT", "Vermont"],
  ["VA", "Virginia"], ["WA", "Washington"], ["WV", "West Virginia"], ["WI", "Wisconsin"], ["WY", "Wyoming"],
];

// Names that mean the same place or answer. The first of each group is only a key.
const SAME: readonly (readonly string[])[] = [
  ["united states", "united states of america", "usa", "us", "u.s.", "u.s.a.", "america"],
  ["united kingdom", "uk", "u.k.", "great britain", "britain", "england"],
  ["canada", "ca"],
  ["india", "in"],
  ["yes", "y", "true"],
  ["no", "n", "false"],
  ...US_STATES.map(([code, name]) => [name.toLowerCase(), code.toLowerCase()]),
];

const PLACEHOLDER = /^(?:-+|select|choose|pick|please (?:select|choose)|select (?:one|an option)|none selected|\.\.\.)\b|^\s*$/iu;

export function normalize(text: string): string {
  return text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[’']/gu, "")
    .replace(/[^\p{L}\p{N}.]+/gu, " ")
    .trim();
}

function words(text: string): string[] {
  return normalize(text).replace(/\./gu, "").split(" ").filter(Boolean);
}

// Every name in every group the text belongs to: "CA" is both Canada and California, and
// the select's own options decide which one the page means.
function synonyms(text: string): readonly string[] {
  const key = normalize(text);
  return [key, ...SAME.filter((group) => group.includes(key)).flat()];
}

// A select's first option is often "Select..." with an empty value: it isn't an answer.
export function isPlaceholder(option: Option): boolean {
  return option.value.trim() === "" || PLACEHOLDER.test(option.text);
}

// How well an option says the answer, from 0 (not at all) to 1 (exactly).
function score(option: Option, answer: string): number {
  const said = synonyms(answer);
  const texts = [option.text, option.value].map(normalize).filter(Boolean);
  if (texts.some((text) => said.includes(text))) return 1;
  // "Yes, I am authorized" starts with the answer "Yes".
  if (texts.some((text) => said.some((name) => text.startsWith(`${name} `)))) return 0.9;
  const wanted = new Set(words(answer));
  if (wanted.size === 0) return 0;
  const best = Math.max(
    ...texts.map((text) => {
      const have = words(text);
      const shared = have.filter((word) => wanted.has(word)).length;
      return shared / Math.max(wanted.size, have.length);
    }),
  );
  return best >= 0.5 ? best * 0.8 : 0;
}

// The index of the option that best says `answer`, or -1 when none says it well enough.
export function pickOption(options: readonly Option[], answer: string): number {
  let found = -1;
  let best = 0;
  options.forEach((option, index) => {
    if (isPlaceholder(option)) return;
    const points = score(option, answer);
    if (points > best) {
      best = points;
      found = index;
    }
  });
  return found;
}

// The first option that matches any of `answers`, in the order the answers come.
export function pickFirst(options: readonly Option[], answers: readonly string[]): number {
  for (const answer of answers) {
    const index = pickOption(options, answer);
    if (index >= 0) return index;
  }
  return -1;
}
