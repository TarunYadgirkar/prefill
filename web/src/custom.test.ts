import { afterEach, describe, expect, it, vi } from "vitest";
import { installCustom, isCustomCandidate } from "./custom";
import type { CustomSuggestionsRequest } from "./messages";

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
      .fn<(request: CustomSuggestionsRequest) => Promise<unknown>>()
      .mockResolvedValue({
        type: "customSuggestionsResult",
        fields: [{ values: ["UC Berkeley"] }, { values: ["LinkedIn"] }],
      });
    const stop = installCustom(document, {
      host: () => "boards.example.io",
      send,
      isUserEvent: () => true,
    });
    await Promise.resolve();
    expect(
      send.mock.calls[0]?.[0].fields.map((field) => field.text.split(" ")[0]),
    ).toEqual(["School", "How"]);

    await Promise.resolve();
    const school = document.getElementById("school") as HTMLInputElement;
    school.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    school.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    const list = document.getElementById(school.getAttribute("list") ?? "");
    expect(
      [...(list?.querySelectorAll("option") ?? [])].map(
        (option) => option.value,
      ),
    ).toEqual(["UC Berkeley"]);

    school.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
    expect(school.hasAttribute("list")).toBe(false);
    stop();
  });

  it("stays off sign-in forms", async () => {
    document.body.innerHTML = `<form><label>School</label><input type="text" name="school">
      <input type="password" autocomplete="current-password"></form>`;
    const send = vi
      .fn<(request: CustomSuggestionsRequest) => Promise<unknown>>()
      .mockResolvedValue({});
    const stop = installCustom(document, {
      host: () => "example.net",
      send,
      isUserEvent: () => true,
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
});
