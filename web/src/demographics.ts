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

export function isDemographic(question: string): boolean {
  return DEMOGRAPHIC.test(question);
}

// The option to pick for a demographic question, or -1 to leave it.
export function declineOption(options: readonly Option[]): number {
  const texts = options.map((option) => normalize(option.text || option.value));
  const decline = texts.findIndex((text) => DECLINE.test(text));
  return decline >= 0 ? decline : texts.findIndex((text) => NO.test(text));
}
