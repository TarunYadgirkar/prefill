import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import application from "../../testbed/sites/application.html?raw";
import { collectAnswers, installLearn, jobQuestion, savedText } from "./learn";
import type { AnswersRequest } from "./messages";

let uninstall: (() => void) | undefined;

beforeEach(() => {
  // happy-dom lays nothing out, so every element would measure 0 by 0.
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
  // Without the stylesheet link, which happy-dom would try to fetch.
  document.body.innerHTML = application.replace(/<link[^>]*>/gu, "");
});

afterEach(() => {
  uninstall?.();
  uninstall = undefined;
  document.body.innerHTML = "";
  document.querySelector("prefill-saved")?.remove();
  vi.restoreAllMocks();
});

// The person presses the field, then changes it; `byScript` leaves out the press.
function set(selector: string, value: string, byScript = false): void {
  const field = document.querySelector<HTMLInputElement | HTMLSelectElement>(selector);
  if (field === null) throw new Error(`no ${selector}`);
  if (!byScript) field.dispatchEvent(new Event("pointerdown", { bubbles: true, composed: true }));
  if (field instanceof HTMLInputElement && field.type === "radio") field.checked = true;
  else field.value = value;
  field.dispatchEvent(new Event("change", { bubbles: true }));
}

describe("learning answers from an application", () => {
  it("knows the questions applications ask and leaves demographic ones alone", () => {
    expect(jobQuestion("Are you legally authorized to work in the United States?")).toBe("authorization");
    expect(jobQuestion("Will you now or in the future require sponsorship?")).toBe("sponsorship");
    expect(
      jobQuestion("Are you legally able to work in Canada according to the laws and regulations of the province or territory where you live?"),
    ).toBe("authorization");
    expect(jobQuestion("Expected graduation date")).toBe("graduation");
    expect(jobQuestion("Veteran Status")).toBeUndefined();
    expect(jobQuestion("Why do you want to work here?")).toBeUndefined();
  });

  it("sends what the person answered on submit, and offers Undo for what was saved", async () => {
    const send = vi.fn<(request: AnswersRequest) => Promise<unknown>>(() =>
      Promise.resolve({ type: "answersResult", saved: 2, updated: [] }),
    );
    uninstall = installLearn(document, window, { host: () => "boards.example.io", send, isUserEvent: () => true });
    set("#school", "University of California, Berkeley");
    set("input[type=radio][value='1']", "");
    set("#gender", "Male");
    set("#email", "alex@example.com");
    // A script's requestSubmit() makes a submit with no press before it.
    document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
    expect(send).not.toHaveBeenCalled();
    document.querySelector("form button, form input[type=submit]")?.dispatchEvent(new Event("click", { bubbles: true }));
    document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(send).toHaveBeenCalledWith({
      type: "answers",
      host: "boards.example.io",
      action: "learn",
      answers: [
        { question: "school", value: "University of California, Berkeley", text: expect.stringMatching(/^School /u) as string },
        {
          question: "authorization",
          value: "Yes",
          text: "Are you legally authorized to work in the United States?",
          options: ["Yes", "No"],
        },
      ],
    });
    expect(document.querySelector("prefill-saved")).not.toBeNull();
  });

  it("says when a later answer replaced a learned one", () => {
    expect(savedText({ saved: 0, updated: ["School"] })).toBe("Updated your answer to School");
    expect(savedText({ saved: 0, updated: ["School", "Major"] })).toBe("Updated 2 answers");
    expect(savedText({ saved: 2, updated: [] })).toBe("Saved 2 answers");
    expect(savedText({ saved: 1, updated: ["School", "Major"] })).toBe("Saved 1 answer and updated 2");
  });

  it("drops an answer the page changed or relabelled after the person set it", () => {
    const send = vi.fn<(request: AnswersRequest) => Promise<unknown>>(() => Promise.resolve(undefined));
    uninstall = installLearn(document, window, { host: () => "boards.example.io", send, isUserEvent: () => true });
    set("#school", "University of California, Berkeley");
    set("#question_1", "linkedin.com/in/alex");
    const school = document.querySelector<HTMLInputElement>("#school");
    const other = document.querySelector("label[for=question_1]");
    if (school === null || other === null) throw new Error("fixture changed");
    school.value = "Set by the page";
    other.textContent = "Will you require sponsorship?";
    document.querySelector("form button, form input[type=submit]")?.dispatchEvent(new Event("click", { bubbles: true }));
    document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
    expect(send).not.toHaveBeenCalled();
  });

  it("ignores a value a script typed into a field the person never touched", () => {
    const send = vi.fn<(request: AnswersRequest) => Promise<unknown>>(() => Promise.resolve(undefined));
    uninstall = installLearn(document, window, { host: () => "boards.example.io", send, isUserEvent: () => true });
    set("#school", "Set by the page", true);
    document.querySelector("form button, form input[type=submit]")?.dispatchEvent(new Event("click", { bubbles: true }));
    document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
    expect(send).not.toHaveBeenCalled();
  });

  it("reads nothing the person didn't set themselves", () => {
    const school = document.querySelector<HTMLInputElement>("#school");
    if (school !== null) school.value = "Set by the page";
    expect(collectAnswers(document, new WeakMap())).toEqual([]);
  });
});
