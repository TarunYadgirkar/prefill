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

const PLACEHOLDER = /^\s*(?:(?:select|choose|pick|please (?:select|choose)|none selected)\b|-+|\.\.\.)|^\s*$/iu;

export function normalize(text: string): string {
  return text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[’']/gu, "")
    .replace(/[^\p{L}\p{N}.]+/gu, " ")
    .trim();
}

// Words every school or degree shares, which say nothing about which one is meant.
const FILLER = new Set(["of", "the", "and", "at", "in", "for", "a", "an", "university", "college", "school", "institute"]);

function words(text: string): string[] {
  return normalize(text)
    .replace(/\./gu, "")
    .split(" ")
    .filter((word) => word !== "" && !FILLER.has(word));
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
  // Half is too little: "Bachelor of Arts" isn't "Bachelor of Science".
  return best > 0.5 ? best * 0.8 : 0;
}

// How close two options' scores may be before neither clearly says the answer: "Yes" fits
// "Yes, I will require sponsorship now" and "Yes, but not now" equally, and a guess between
// them could tell an employer the wrong thing.
const AMBIGUOUS_MARGIN = 0.1;

// The option that best says an answer, and how many options say it about as well. More than
// one means the page asks something the answer alone can't settle.
export interface OptionMatch {
  index: number;
  fits: number;
}

const NO_MATCH: OptionMatch = { index: -1, fits: 0 };

export function matchOption(options: readonly Option[], answer: string): OptionMatch {
  const scores = options.map((option) => (isPlaceholder(option) ? 0 : score(option, answer)));
  const best = Math.max(0, ...scores);
  if (best === 0) return datePartMatch(options, answer);
  const index = scores.indexOf(best);
  // An option that says the answer exactly wins outright, even beside others that mean the same.
  if (best === 1) return { index, fits: 1 };
  return { index, fits: scores.filter((points) => points > 0 && best - points < AMBIGUOUS_MARGIN).length };
}

const MONTHS = [
  "january", "february", "march", "april", "may", "june",
  "july", "august", "september", "october", "november", "december",
];
const MONTH_ABBREVIATION = 3;
// "May 2027" or "May 15, 2027": a month name, maybe a day, and a year.
const MONTH_YEAR = /^([a-z]+)\.?\s+(?:\d{1,2},?\s+)?(\d{4})$/u;

// The ways an option may say each part of a dated answer on its own: the year, and the
// month in full or cut to three letters.
function dateParts(answer: string): string[] {
  const [, monthWord = "", year = ""] = MONTH_YEAR.exec(answer.trim().toLowerCase()) ?? [];
  const month = MONTHS.find((name) => monthWord.length >= MONTH_ABBREVIATION && name.startsWith(monthWord));
  return month === undefined ? [] : [year, month, month.slice(0, MONTH_ABBREVIATION)];
}

// Lever asks for a graduation date as a year list and a month list. A saved "May 2027" fills
// the option that says only its year or only its month, when exactly one option does.
function datePartMatch(options: readonly Option[], answer: string): OptionMatch {
  const parts = dateParts(answer);
  if (parts.length === 0) return NO_MATCH;
  const says = (option: Option): boolean =>
    !isPlaceholder(option) && [option.text, option.value].some((text) => parts.includes(normalize(text)));
  const hits = options.flatMap((option, index) => (says(option) ? [index] : []));
  return { index: hits[0] ?? -1, fits: hits.length };
}

// The index of the option that best says `answer`, or -1 when none says it well enough or
// more than one does.
export function pickOption(options: readonly Option[], answer: string): number {
  const { index, fits } = matchOption(options, answer);
  return fits === 1 ? index : -1;
}

// The match for the first of `answers` that any option says, in the order the answers come.
export function chooseOption(options: readonly Option[], answers: readonly string[]): OptionMatch {
  for (const answer of answers) {
    const match = matchOption(options, answer);
    if (match.fits > 0) return match;
  }
  return NO_MATCH;
}
