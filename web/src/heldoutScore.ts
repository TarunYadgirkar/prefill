import { isPlaceholder, normalize } from "./choices";
import { classify } from "./classify";
import { isCombobox } from "./combobox";
import { fieldText } from "./custom";
import { declineOption } from "./demographics";
import { fieldElements, labelText } from "./dom";
import { fillForm } from "./fill";
import type { FieldElement } from "./fieldTypes";
import { fakeComboboxes } from "./heldoutCombobox";
import { reply, type Person } from "./heldoutHost";

// Scores one-tap fill on a held-out form: fills the saved page with a stand-in app that
// answers with the test person's values, then compares each field with what a careful
// person would have put there. See docs/ACCURACY.md.

// A field by its id, its name (a radio or checkbox group shares one), the start of its
// question, or a group of radio buttons that has no name, by the buttons' own labels.
export type Locator = { id: string } | { name: string } | { label: string } | { radios: string[] };

// fill: one of `accept` belongs there. decline: a demographic question, answered with the
// option that declines (or "No"). leave: a field Prefill must not touch (sign-in, consent,
// someone else's details). needYou: the person has no saved answer, so it stays empty.
export type Want = "fill" | "decline" | "leave" | "needYou";

export interface Expectation {
  field: Locator;
  want: Want;
  accept?: string[];
  // A searchable dropdown's options, which the saved page doesn't hold.
  options?: string[];
  sensitive?: boolean;
  note?: string;
}

export interface FormExpectations {
  source: string;
  fields: Expectation[];
}

export type Outcome = "right" | "wrong" | "missing" | "left";

export interface FieldResult {
  field: string;
  want: Want;
  got: string;
  outcome: Outcome;
  sensitive: boolean;
}

type Target = { control: FieldElement } | { group: HTMLInputElement[] };

const squash = (text: string): string => text.replace(/\s+/gu, " ").trim().toLowerCase();

function byLabel(fields: readonly FieldElement[], label: string): Target | undefined {
  const control = fields.find((element) => squash(fieldText(element)).startsWith(squash(label)));
  return control === undefined ? undefined : { control };
}

function byName(fields: readonly FieldElement[], name: string): Target | undefined {
  const named = fields.filter((element) => element.getAttribute("name") === name);
  const first = named[0] as HTMLInputElement | undefined;
  if (first === undefined) return undefined;
  return first.type === "radio" || first.type === "checkbox" ? { group: named as HTMLInputElement[] } : { control: first };
}

function byRadios(fields: readonly FieldElement[], labels: readonly string[]): Target | undefined {
  const radios = fields.filter((element): element is HTMLInputElement => (element as HTMLInputElement).type === "radio");
  const start = radios.findIndex((_, index) =>
    labels.every((label, offset) => squash(labelText(radios[index + offset] as FieldElement)).startsWith(squash(label))),
  );
  return start < 0 ? undefined : { group: radios.slice(start, start + labels.length) };
}

function locate(fields: readonly FieldElement[], locator: Locator): Target | undefined {
  if ("id" in locator) {
    const control = fields.find((element) => element.id === locator.id);
    return control === undefined ? undefined : { control };
  }
  if ("name" in locator) return byName(fields, locator.name);
  if ("label" in locator) return byLabel(fields, locator.label);
  return byRadios(fields, locator.radios);
}

const elementsOf = (target: Target): FieldElement[] => ("control" in target ? [target.control] : target.group);

// What a field holds now, in words: the text, the chosen option, the checked buttons' labels.
const isButton = (input: HTMLInputElement): boolean => input.type === "radio" || input.type === "checkbox";

function buttonState(input: HTMLInputElement): string {
  if (!input.checked) return "";
  const label = labelText(input);
  return label === "" ? input.value : label;
}

function stateOf(element: FieldElement, picked: ReadonlyMap<HTMLInputElement, string>): string {
  const input = element as HTMLInputElement;
  if (isButton(input)) return buttonState(input);
  if (isCombobox(element)) return picked.get(input) ?? "";
  if (element.localName !== "select") return element.value;
  return selectState(element as HTMLSelectElement);
}

function selectState(select: HTMLSelectElement): string {
  const chosen = select.selectedOptions[0];
  return chosen === undefined || isPlaceholder({ text: chosen.text, value: chosen.value }) ? "" : chosen.text.trim();
}

const describe = (locator: Locator): string => Object.values(locator).flat().join(" / ").slice(0, 60);

// A link box may hold the address without its scheme, as Prefill fills a plain text box.
const bare = (text: string): string => text.trim().replace(/^https?:\/\//iu, "").replace(/\/$/u, "");

function same(accepted: string, got: string): boolean {
  const digits = (text: string): string => text.replace(/\D/gu, "");
  const MIN_PHONE = 7;
  if (digits(got).length >= MIN_PHONE && digits(accepted) === digits(got)) return true;
  return normalize(bare(accepted)) === normalize(bare(got));
}

function judge(expectation: Expectation, got: string): Outcome {
  const { want } = expectation;
  if (want === "leave" || want === "needYou") return got === "" ? "left" : "wrong";
  return got === "" ? "missing" : judgeAnswer(expectation, got);
}

function judgeAnswer(expectation: Expectation, got: string): Outcome {
  const { want } = expectation;
  if (want === "decline") return declineOption([{ text: got, value: got }]) === 0 ? "right" : "wrong";
  return (expectation.accept ?? []).some((accepted) => same(accepted, got)) ? "right" : "wrong";
}

function comboOptions(targets: readonly (Target | undefined)[], expectations: readonly Expectation[]): Map<HTMLInputElement, readonly string[]> {
  const options = new Map<HTMLInputElement, readonly string[]>();
  expectations.forEach((expectation, index) => {
    const target = targets[index];
    if (expectation.options !== undefined && target !== undefined && "control" in target)
      options.set(target.control as HTMLInputElement, expectation.options);
  });
  return options;
}

function resolve(fields: readonly FieldElement[], expectations: readonly Expectation[]): Target[] {
  return expectations.map((expectation) => {
    const target = locate(fields, expectation.field);
    if (target === undefined) throw new Error(`no field for ${JSON.stringify(expectation.field)}`);
    return target;
  });
}

const isSensitive = (element: FieldElement): boolean =>
  classify(element).kind === "sensitive" || (element as HTMLInputElement).type === "password";

// Fields Prefill changed that no expectation lists count as wrong: nothing should be filled
// that a person wouldn't have put there.
function unlisted(fields: readonly FieldElement[], listed: ReadonlySet<FieldElement>, before: ReadonlyMap<FieldElement, string>, read: (element: FieldElement) => string): FieldResult[] {
  return fields
    .filter((element) => !listed.has(element) && read(element) !== before.get(element))
    .map((element) => ({
      field: `(unlisted) ${fieldText(element).slice(0, 50)}`,
      want: "leave" as const,
      got: read(element),
      outcome: "wrong" as const,
      sensitive: isSensitive(element),
    }));
}

export async function scoreForm(html: string, form: FormExpectations, person: Person): Promise<FieldResult[]> {
  document.body.innerHTML = html;
  const fields = fieldElements(document, Infinity).filter((element) => (element as HTMLInputElement).type !== "hidden");
  const targets = resolve(fields, form.fields);
  const combos = fakeComboboxes(document, comboOptions(targets, form.fields));
  const read = (element: FieldElement): string => stateOf(element, combos.picked);
  const before = new Map(fields.map((element) => [element, read(element)]));
  await fillForm(document, { host: () => new URL(form.source).hostname, send: (request) => Promise.resolve(reply(person, request)) });
  combos.stop();
  const results = form.fields.map((expectation, index): FieldResult => {
    const elements = elementsOf(targets[index] as Target);
    const got = elements.map(read).filter((text) => text !== "").join(", ").trim();
    return {
      field: describe(expectation.field),
      want: expectation.want,
      got,
      outcome: judge(expectation, got),
      sensitive: expectation.sensitive === true || elements.some(isSensitive),
    };
  });
  return [...results, ...unlisted(fields, new Set(targets.flatMap(elementsOf)), before, read)];
}

const OUTCOMES: readonly Outcome[] = ["right", "wrong", "missing", "left"];

export function tally(results: readonly FieldResult[]): Record<Outcome, number> {
  const counts = { right: 0, wrong: 0, missing: 0, left: 0 };
  for (const result of results) counts[result.outcome] += 1;
  return counts;
}

export function table(scores: ReadonlyMap<string, readonly FieldResult[]>): string {
  const row = (name: string, counts: Record<Outcome, number>): string =>
    [name.padEnd(24), ...OUTCOMES.map((outcome) => String(counts[outcome]).padStart(7))].join(" ");
  const all = [...scores.values()].flat();
  const lines = [
    ["form".padEnd(24), ...OUTCOMES.map((outcome) => outcome.padStart(7))].join(" "),
    ...[...scores].map(([name, results]) => row(name, tally(results))),
    row("total", tally(all)),
    "",
    ...[...scores].flatMap(([name, results]) =>
      results
        .filter((result) => result.outcome === "wrong" || result.outcome === "missing")
        .map((result) => `${result.outcome.padEnd(8)} ${name}: ${result.field} (want ${result.want}, got "${result.got.slice(0, 60)}")`),
    ),
  ];
  return lines.join("\n");
}
