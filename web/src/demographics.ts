import { normalize, type Option } from "./choices";

// Voluntary self-identification questions: gender, race and ethnicity, veteran status,
// disability, sexual orientation. Prefill never answers them for the person: it picks the
// option that declines, or the plain "No" when a question has no way to decline, and
// leaves the question alone when it has neither.
export const DEMOGRAPHIC =
  /\bgender|\bsex\b|\brace\b|racial|ethnic|hispanic|latin[oax]|veteran|military status|disabilit|sexual orientation|transgender|lgbt|self.?identif/iu;

const DECLINE =
  /decline|prefer not|rather not|choose not|not (?:to )?(?:say|answer|disclose|identify|specify)|(?:do not|dont|don t) (?:wish|want) to|wish not|not wish|undisclosed|no answer|not declared/iu;

// "No", "I am not a protected veteran", "No, I do not have a disability".
const NO = /^(?:no\b|none\b|i am not\b|im not\b|i do not have\b|i dont have\b|not a\b)/iu;

// "Yes", "I am a protected veteran", "I identify as...": the other half of a yes/no question.
const YES = /^(?:yes\b|i am\b|im\b|i have\b|i identify\b)/iu;

export function isDemographic(question: string): boolean {
  return DEMOGRAPHIC.test(question);
}

// Whether an answer to a demographic question says nothing about the person: it declines,
// or it's the "No" of a yes/no question.
export function isDecline(text: string): boolean {
  const said = normalize(text);
  return DECLINE.test(said) || NO.test(said);
}

// The option to pick for a demographic question, or -1 to leave it. "No" only answers a
// yes/no question: a race or gender list without a way to decline is left.
export function declineOption(options: readonly Option[]): number {
  const texts = options.map((option) => normalize(option.text || option.value));
  const decline = texts.findIndex((text) => DECLINE.test(text));
  if (decline >= 0 || !texts.some((text) => YES.test(text))) return decline;
  return texts.findIndex((text) => NO.test(text));
}
