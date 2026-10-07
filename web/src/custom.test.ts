import { afterEach, describe, expect, it, vi } from "vitest";
import type { Choice, TextField } from "./dropdown";
import {
  customChoices,
  fillable,
  installCustom,
  isCustomCandidate,
  type CustomOptions,
} from "./custom";

const GREENHOUSE = `
<form>
  <label for="email">Email *</label><input type="text" id="email" name="job_application[email]">
  <label for="school">School</label><input type="text" id="school" name="job_application[educations][0][school_name_id]">
  <label for="q2">How did you hear about this job?</label><input type="text" id="q2" name="job_application[answers_attributes][2][text_value]">
  <input type="search" name="q">
  <input type="password" autocomplete="new-password">
</form>`;

describe("installCustom", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
  });

  it("asks about unclaimed text fields only and lists the match on a tapped field", async () => {
    document.body.innerHTML = GREENHOUSE;
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(
      new DOMRect(10, 10, 200, 30),
    );
    const send = vi
      .fn<CustomOptions["send"]>()
      .mockResolvedValue({
        type: "customSuggestionsResult",
        fields: [
          { values: [{ value: "UC Berkeley", why: "card" }] },
          { values: [{ value: "LinkedIn", why: "card" }] },
        ],
      });
    const shown = new Map<TextField, string[]>();
    const attach = (element: TextField, choices: readonly Choice[]) => {
      shown.set(element, choices.map((choice) => choice.value));
      return () => shown.delete(element);
    };
    const stop = installCustom(document, {
      host: () => "boards.example.io",
      send,
      isUserEvent: () => true,
      attach,
    });
    await Promise.resolve();
    const asked = send.mock.calls[0]?.[0];
    expect(
      asked?.type === "customSuggestions"
        ? asked.fields.map((field) => field.text.split(" ")[0])
        : [],
    ).toEqual(["School", "How"]);

    await Promise.resolve();
    const school = document.getElementById("school") as HTMLInputElement;
    school.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    school.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(shown.get(school)).toEqual(["UC Berkeley"]);

    school.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
    expect(shown.has(school)).toBe(false);
    stop();
  });

  it("stays off sign-in forms", async () => {
    document.body.innerHTML = `<form><label>School</label><input type="text" name="school">
      <input type="password" autocomplete="current-password"></form>`;
    const send = vi
      .fn<CustomOptions["send"]>()
      .mockResolvedValue({});
    const stop = installCustom(document, {
      host: () => "example.net",
      send,
      isUserEvent: () => true,
      attach: () => () => undefined,
    });
    await Promise.resolve();
    expect(send).not.toHaveBeenCalled();
    stop();
  });

  it("takes text areas only where Prefill draws its own list", () => {
    document.body.innerHTML =
      '<label for="u">University</label><textarea id="u"></textarea>';
    const university = document.getElementById("u") as HTMLTextAreaElement;
    expect(isCustomCandidate(university)).toBe(false);
    expect(isCustomCandidate(university, true)).toBe(true);
  });

  it("offers a text area its saved answers but never a guess", async () => {
    document.body.innerHTML = '<form><textarea id="m" placeholder="Type / for commands"></textarea></form>';
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
    const send = vi.fn<CustomOptions["send"]>().mockResolvedValue({
      type: "customSuggestionsResult",
      fields: [{ values: [], guesses: ["University of California, Berkeley"] }],
    });
    const attach = vi.fn(() => () => undefined);
    const stop = installCustom(document, { host: () => "claude.ai", send, isUserEvent: () => true, textAreas: true, attach });
    await Promise.resolve();
    await Promise.resolve();
    const box = document.getElementById("m") as HTMLTextAreaElement;
    box.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    box.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(send).toHaveBeenCalled();
    expect(attach).not.toHaveBeenCalled();
    stop();
  });
});

describe("customChoices", () => {
  it("hears about a pick of an answer that wasn't first, or of a guess", () => {
    const picked: string[] = [];
    const choices = customChoices(
      {
        values: [
          { value: "UC Berkeley", why: "card" },
          { value: "Berkeley High", why: "card" },
        ],
        guesses: ["EECS"],
      },
      (value) => picked.push(value),
    );
    choices.forEach((choice) => choice.onPick?.());
    expect(choices.map((choice) => choice.detail)).toEqual([
      "Custom field",
      "Custom field",
      "Suggested",
    ]);
    expect(picked).toEqual(["Berkeley High", "EECS"]);
  });

  it("offers an answer for another scope without filling it, and says when there is none for this one", () => {
    const choices = customChoices(
      { values: [], suggested: [{ value: "Yes", why: "card", label: "Work authorization" }], noAnswerFor: "Canada" },
      () => undefined,
    );
    expect(choices.map(({ value, detail, tone }) => [value, detail, tone])).toEqual([
      ["Yes", "Work authorization", "guess"],
      ["No answer for Canada yet", "", "note"],
    ]);
    expect(fillable(choices)).toEqual([]);
  });
});
