import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import application from "../../testbed/sites/application.html?raw";
import { fillForm, noteFor, MISSED_NOTE } from "./fill";
import { fieldsLeft } from "./fillLeft";
import { installLearn } from "./learn";
import type { ExtensionRequest } from "./messages";

const tick = (): Promise<void> => new Promise((resolve) => setTimeout(resolve, 0));
const field = (id: string) => document.getElementById(id) as HTMLInputElement;

// The app knows only the school; every other question goes unanswered.
const reply = (request: ExtensionRequest): Promise<unknown> => {
  if (request.type !== "customSuggestions") return Promise.resolve({ type: "error", reason: "none" });
  return Promise.resolve({
    type: "customSuggestionsResult",
    fields: request.fields.map(({ text }) => ({
      values: /school/iu.test(text) ? [{ value: "UC Berkeley", why: "learned", label: "School" }] : [],
    })),
  });
};

let roots: ShadowRoot[] = [];
const status = (): string | undefined => roots.at(-1)?.querySelector(".status")?.textContent;
const buttons = (): HTMLButtonElement[] => [...(roots.at(-1)?.querySelectorAll("button") ?? [])];

function submitSchool(value: string): void {
  field("school").dispatchEvent(new Event("pointerdown", { bubbles: true }));
  field("school").value = value;
  field("school").dispatchEvent(new Event("change", { bubbles: true }));
  document.querySelector("form button, form input[type=submit]")?.dispatchEvent(new Event("click", { bubbles: true }));
  document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
}

beforeEach(() => {
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
  document.body.innerHTML = application.replace(/<link[^>]*>/gu, "");
  roots = [];
  const { attachShadow } = Object.getOwnPropertyDescriptors(Element.prototype);
  vi.spyOn(Element.prototype, "attachShadow").mockImplementation(function (this: Element, init: ShadowRootInit) {
    const root = (attachShadow.value as (this: Element, init: ShadowRootInit) => ShadowRoot).call(this, init);
    roots.push(root);
    return root;
  });
});

afterEach(() => {
  document.body.innerHTML = "";
  document.querySelectorAll("prefill-saved").forEach((pill) => { pill.remove(); });
  vi.restoreAllMocks();
});

describe("Fill form reads each field back", () => {
  it("counts only a value that stayed, and leaves the rest for the person", async () => {
    const form = (): ParentNode => document.querySelector("form") ?? document;
    const all = await fillForm(form(), { host: () => "boards.example.io", send: reply });
    document.body.innerHTML = application.replace(/<link[^>]*>/gu, "");
    // The page's own script empties the school box right after any change, as a controlled input can.
    field("school").addEventListener("input", () => {
      setTimeout(() => { field("school").value = "Berkeley"; }, 0);
    });
    const result = await fillForm(form(), { host: () => "boards.example.io", send: reply });
    expect(result.filled).toBe(all.filled - 1);
    expect(field("school").value).toBe("Berkeley");
    expect(fieldsLeft(document)).toContain(field("school"));
    expect(noteFor(field("school"))).toBe(MISSED_NOTE);
  });
});

describe("a changed answer Prefill filled", () => {
  it("asks before changing it everywhere, and Just here keeps it for this site", async () => {
    const sent: ExtensionRequest[] = [];
    const send = (request: ExtensionRequest): Promise<unknown> => {
      sent.push(request);
      if (request.type !== "answers") return reply(request);
      if (request.action === "learn") return Promise.resolve({ type: "answersResult", saved: 0, updated: [], ask: ["School"] });
      return Promise.resolve({ type: "answersResult", saved: 1, updated: [] });
    };
    await fillForm(document.querySelector("form") ?? document, { host: () => "boards.example.io", send });
    expect(field("school").value).toBe("UC Berkeley");
    const stop = installLearn(document, window, { host: () => "boards.example.io", send, isUserEvent: () => true });
    submitSchool("Stanford");
    await tick();

    const learn = sent.find((request) => request.type === "answers");
    expect(learn).toMatchObject({ action: "learn", answers: [{ question: "school", value: "Stanford", changedFill: true }] });
    expect(status()).toBe("You changed your answer to School");
    expect(buttons().map((button) => button.textContent)).toEqual(["Update everywhere", "Just here"]);
    buttons()[1]?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    await tick();
    expect(sent.at(-1)).toMatchObject({ type: "answers", action: "keepHere", answers: [{ value: "Stanford", changedFill: true }] });
    expect(status()).toBe("Kept for this site only");
    stop();
  });
});
