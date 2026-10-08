import type { ExtensionRequest, LinkType } from "./messages";
import { fitsWorkQuestion } from "./workQuestion";

// A stand-in for the app that answers the page's three questions with one person's saved
// values, the way the message routers do: every email, phone and address in the card's
// order, every link, and custom answers picked by CustomFieldMatcher's word rule (ported
// below without scopes). Used only to score the held-out forms.

interface Address {
  street: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
}

interface CustomAnswer {
  label: string;
  value: string;
  matchWords?: string[];
}

export interface Person {
  name: { given: string; family: string };
  emails: string[];
  phones: string[];
  addresses: Address[];
  links: { type: LinkType; url: string }[];
  custom: CustomAnswer[];
}

// CustomFieldMatcher.fillers in PrefillKit.
const FILLERS: ReadonlySet<string> = new Set([
  "a", "an", "the", "of", "for", "and", "or", "to", "in", "on", "at", "by", "with", "from",
  "your", "you", "my", "our", "us", "we", "i", "me", "did", "do", "does", "how", "what", "which",
  "where", "when", "who", "is", "are", "was", "were", "be", "please", "enter", "select", "choose",
  "provide", "about", "this", "that", "if", "any", "required", "optional", "e", "g", "eg",
]);
const MAX_OFFERED = 3;
const MIN_PLURAL = 3;

const singular = (word: string): string =>
  word.length > MIN_PLURAL && word.endsWith("s") && !word.endsWith("ss") ? word.slice(0, -1) : word;

export function words(text: string): Set<string> {
  const parts = text.replace(/(\p{Ll})(\p{Lu})/gu, "$1 $2").toLowerCase().split(/[^\p{L}\p{N}]+/u);
  return new Set(parts.filter((part) => part !== "" && !FILLERS.has(part)).map(singular));
}

function score(answer: CustomAnswer, page: ReadonlySet<string>): number {
  const phrases = [answer.label, ...(answer.matchWords ?? [])].map(words);
  const fits = phrases.filter((phrase) => phrase.size > 0 && [...phrase].every((word) => page.has(word)));
  return Math.max(0, ...fits.map((phrase) => phrase.size));
}

// CustomFieldMatcher.examples, .asksForSchool and .asks.
const EXAMPLES = /\(\s*(?:e\.?\s?g\b\.?|for example|for instance|such as|examples?\b)[^)]*\)/giu;
const ASKS_FOR_SCHOOL =
  /\b(?:which|what|name of(?: your| the)?)\s+(?:school|university|college)|\b(?:school|university|college)\s+(?:name|attended)\b|\b(?:attend|attending|enrolled|study at|studying at)\b/iu;
const SCHOOL_LEAD = 4;
const SCHOOL_WORDS: ReadonlySet<string> = new Set(["school", "university", "college"]);

// CustomFieldMatcher.unlisted: a box for a school the list above didn't have.
const UNLISTED = /not (?:see|find)\b.{0,40}\blisted|(?:not|isn.?t|wasn.?t) listed|unlisted|other school|school not (?:listed|found)/iu;

function asks(text: string, answer: CustomAnswer): boolean {
  if (answer.label !== "School") return true;
  if (UNLISTED.test(text)) return false;
  const lead = text.toLowerCase().split(/[^\p{L}]+/u).filter(Boolean).slice(0, SCHOOL_LEAD).map(singular);
  return lead.some((word) => SCHOOL_WORDS.has(word)) || ASKS_FOR_SCHOOL.test(text);
}

export function customValues(person: Person, text: string): CustomAnswer[] {
  const page = words(text.replace(EXAMPLES, " "));
  const scored = person.custom.filter((answer) => asks(text, answer) && fitsWorkQuestion(answer.label, text)).map((answer) => ({ answer, score: score(answer, page) }));
  const best = Math.max(0, ...scored.map((entry) => entry.score));
  if (best === 0) return [];
  const seen = new Set<string>();
  return scored
    .filter((entry) => entry.score === best && !seen.has(entry.answer.value) && seen.add(entry.answer.value))
    .map((entry) => entry.answer)
    .slice(0, MAX_OFFERED);
}

const card = (value: string): { value: string; why: "card" } => ({ value, why: "card" });

export function reply(person: Person, request: ExtensionRequest): unknown {
  switch (request.type) {
    case "contactSuggestions":
      return {
        type: "contactSuggestionsResult",
        emails: person.emails.map(card),
        phones: person.phones.map(card),
        addresses: person.addresses.map((address) => ({ address, why: "card" })),
        name: person.name,
      };
    case "linkSuggestions":
      return { type: "linkSuggestionsResult", links: person.links.map((link) => ({ ...link, why: "card" })) };
    case "customSuggestions":
      return {
        type: "customSuggestionsResult",
        fields: request.fields.map(({ text }) => ({
          values: customValues(person, text).map((answer) => ({ ...card(answer.value), label: answer.label })),
        })),
      };
    default:
      return { type: "error", reason: "unexpected" };
  }
}
