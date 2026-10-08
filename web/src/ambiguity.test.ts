import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { matchOption, pickOption } from "./choices";
import { fillableCount, fillForm, noteFor } from "./fill";
import { fieldsLeft } from "./fillLeft";
import sponsorship from "./fixtures/ats-lever-sponsorship.html?raw";
import type { ExtensionRequest } from "./messages";

const options = (...texts: string[]) => texts.map((text) => ({ text, value: text }));

describe("an answer more than one option says", () => {
  it.each([
    [["Yes, I will require sponsorship now", "Yes, but not now", "No"], "Yes", 2],
    [["Bachelor's Degree", "Bachelor's Degree (in progress)", "Master's Degree"], "Bachelor's", 2],
    [["Yes, I am authorized to work in the US", "No"], "Yes", 1],
    [["Yes", "Yes, but not now"], "Yes", 1],
    [["United States", "USA", "Canada"], "United States", 1],
    [["Arizona", "Alaska"], "California", 0],
  ])("%j with %s fits %i", (texts, answer, fits) => {
    expect(matchOption(options(...texts), answer).fits).toBe(fits);
  });

  it("picks nothing rather than guess between two", () => {
    expect(pickOption(options("Yes, I will require sponsorship now", "Yes, but not now"), "Yes")).toBe(-1);
    expect(pickOption(options("Yes", "Yes, but not now"), "Yes")).toBe(0);
  });
});

// Lever's question cards with a three-way sponsorship question (fixture header says where
// the markup and wording come from).
describe("Fill form on a form whose options don't settle the answer", () => {
  const SPONSOR = 'input[name$="[field0]"]';
  const answers: Record<string, string> = { sponsorship: "Yes", authorized: "Yes", degree: "Bachelor's" };

  const send = (request: ExtensionRequest): Promise<unknown> => {
    if (request.type !== "customSuggestions") return Promise.resolve({ type: "error", reason: "none" });
    const answer = (text: string): string | undefined =>
      Object.entries(answers).find(([word]) => text.toLowerCase().includes(word))?.[1];
    return Promise.resolve({
      type: "customSuggestionsResult",
      fields: request.fields.map(({ text }) => {
        const value = /canada/iu.test(text) ? undefined : answer(text);
        return { values: value === undefined ? [] : [{ value, why: "card" }] };
      }),
    });
  };
  const select = (suffix: string) => document.querySelector<HTMLSelectElement>(`select[name$="${suffix}"]`);

  beforeEach(() => {
    document.body.innerHTML = sponsorship;
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
    answers.sponsorship = "Yes";
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("leaves the lists two options fit, marks them and counts them as need you", async () => {
    const form = document.querySelector("form") as HTMLFormElement;
    expect(await fillableCount(form, { host: () => "jobs.lever.co", send })).toBe(2);
    const result = await fillForm(form, { host: () => "jobs.lever.co", send });
    expect(result.filled).toBe(2);
    expect(select("[field1]")?.value).toBe("Yes");
    expect(select("eeo[gender]")?.value).toBe("Decline to self-identify");
    expect(document.querySelector(`${SPONSOR}:checked`)).toBeNull();
    expect(select("[field3]")?.selectedIndex).toBe(0);
    const sponsor = document.querySelector<HTMLInputElement>(SPONSOR) as HTMLInputElement;
    const degree = select("[field3]") as HTMLSelectElement;
    expect(noteFor(sponsor)).toBe("2 options fit, pick one");
    expect(noteFor(degree)).toBe("2 options fit, pick one");
    expect(degree.style.getPropertyValue("outline")).not.toBe("");
    expect(fieldsLeft(form)).toEqual(expect.arrayContaining([sponsor, degree]));

    result.undo();
    expect(noteFor(degree)).toBeUndefined();
    expect(degree.style.getPropertyValue("outline")).toBe("");
  });

  it("still fills the one option that clearly says the answer", async () => {
    answers.sponsorship = "No";
    await fillForm(document, { host: () => "jobs.lever.co", send });
    expect(document.querySelector<HTMLInputElement>(`${SPONSOR}:checked`)?.value).toBe("No, I will not require sponsorship");
  });

  it("keeps the mark through a page's own change", async () => {
    await fillForm(document, { host: () => "jobs.lever.co", send });
    const degree = select("[field3]") as HTMLSelectElement;
    degree.selectedIndex = 2;
    degree.dispatchEvent(new Event("change", { bubbles: true }));
    expect(noteFor(degree)).toBe("2 options fit, pick one");
  });
});
