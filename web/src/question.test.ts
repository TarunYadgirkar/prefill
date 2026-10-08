import { afterEach, describe, expect, it, vi } from "vitest";
import { headingOf } from "./custom";
import { fillForm } from "./fill";
import sponsorship from "./fixtures/ats-lever-sponsorship.html?raw";
import type { CustomSuggestionsRequest, ExtensionRequest } from "./messages";

// What the on-device model gets to read with a question on Lever's real question cards:
// the card's heading and each list's options.
describe("the question the app is asked about", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
  });

  it("carries the card's heading and a list's options", async () => {
    document.body.innerHTML = sponsorship;
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
    const asked: CustomSuggestionsRequest["fields"][number][] = [];
    const send = (request: ExtensionRequest): Promise<unknown> => {
      if (request.type === "customSuggestions") asked.push(...request.fields);
      return Promise.resolve({ type: "error", reason: "none" });
    };
    await fillForm(document.querySelector("form") ?? document, { host: () => "jobs.lever.co", send });
    const select = document.querySelector('select[name$="[field1]"]') as HTMLSelectElement;
    expect(headingOf(select)).toBe("Work Eligibility");
    const legal = asked.find((field) => field.options?.join() === "Yes,No");
    expect(legal?.heading).toBe("Work Eligibility");
    const sponsor = asked.find((field) => field.text.includes("sponsorship"));
    expect(sponsor?.options).toEqual([
      "Yes, I will require sponsorship now",
      "Yes, I will require sponsorship in the future",
      "No, I will not require sponsorship",
    ]);
  });

  it("has no heading where the page has none above the field", () => {
    document.body.innerHTML = '<label for="q">Alma mater</label><input id="q"><h2>Later</h2>';
    expect(headingOf(document.getElementById("q") as HTMLElement)).toBeUndefined();
  });
});
