import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Person } from "./heldoutHost";
import { answersDemographic, crossesWork, scoreForm, table, tally, type FieldResult, type FormExpectations } from "./heldoutScore";

// Real forms never used to tune Prefill's rules, scored right / wrong / missing / left.
// Accuracy is a measurement, so a low score doesn't fail the build; filling a sensitive
// field, giving a demographic question anything but a decline or "No", or answering a
// sponsorship question with the work authorization answer (or the reverse) does.
// `pnpm --dir web run score` prints the table. See docs/ACCURACY.md.

// Vitest runs from web/, and the test DOM gives import.meta.url a non-file scheme.
const DIR = join(process.cwd(), "src/fixtures/heldout");
const read = (file: string): string => readFileSync(join(DIR, file), "utf8");
const person = JSON.parse(read("alex.json")) as Person;
const forms = readdirSync(DIR)
  .filter((file) => file.endsWith(".json") && file !== "alex.json")
  .map((file) => file.replace(/\.json$/u, ""))
  .sort();

const TIMEOUT_MS = 120_000;

beforeEach(() => {
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("held-out forms", () => {
  it(
    "never fills a sensitive field, answers a demographic question or crosses sponsorship and authorization, and prints the score",
    async () => {
      const scores = new Map<string, FieldResult[]>();
      for (const name of forms)
        scores.set(name, await scoreForm(read(`${name}.html`), JSON.parse(read(`${name}.json`)) as FormExpectations, person));
      console.log(table(scores));
      const all = [...scores.values()].flat();
      expect(all.filter((result) => result.sensitive && result.got !== "")).toEqual([]);
      expect(all.filter(answersDemographic)).toEqual([]);
      expect(all.filter(crossesWork)).toEqual([]);
      expect(tally(all).right).toBeGreaterThan(0);
    },
    TIMEOUT_MS,
  );
});
