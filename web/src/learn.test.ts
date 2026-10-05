import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import application from "../../testbed/sites/application.html?raw";
import { collectAnswers, installLearn, jobQuestion } from "./learn";
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

function set(selector: string, value: string): void {
  const field = document.querySelector<HTMLInputElement | HTMLSelectElement>(selector);
  if (field === null) throw new Error(`no ${selector}`);
  if (field instanceof HTMLInputElement && field.type === "radio") field.checked = true;
  else field.value = value;
  field.dispatchEvent(new Event("change", { bubbles: true }));
}

describe("learning answers from an application", () => {
  it("knows the questions applications ask and leaves demographic ones alone", () => {
    expect(jobQuestion("Are you legally authorized to work in the United States?")).toBe("authorization");
    expect(jobQuestion("Will you now or in the future require sponsorship?")).toBe("sponsorship");
    expect(jobQuestion("Expected graduation date")).toBe("graduation");
    expect(jobQuestion("Veteran Status")).toBeUndefined();
    expect(jobQuestion("Why do you want to work here?")).toBeUndefined();
  });

  it("sends what the person answered on submit, and offers Undo for what was saved", async () => {
    const send = vi.fn<(request: AnswersRequest) => Promise<unknown>>(() =>
      Promise.resolve({ type: "answersResult", saved: 2 }),
    );
    uninstall = installLearn(document, window, { host: () => "boards.example.io", send, isUserEvent: () => true, hasActivation: () => true });
    set("#school", "University of California, Berkeley");
    set("input[type=radio][value='1']", "");
    set("#gender", "Male");
    set("#email", "alex@example.com");
    document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
    await Promise.resolve();
    await Promise.resolve();
    expect(send).toHaveBeenCalledWith({
      type: "answers",
      host: "boards.example.io",
      action: "learn",
      answers: [
        { question: "school", value: "University of California, Berkeley" },
        { question: "authorization", value: "Yes" },
      ],
    });
    expect(document.querySelector("prefill-saved")).not.toBeNull();
  });

  it("reads nothing the person didn't set themselves", () => {
    const school = document.querySelector<HTMLInputElement>("#school");
    if (school !== null) school.value = "Set by the page";
    expect(collectAnswers(document, new WeakSet())).toEqual([]);
  });
});
