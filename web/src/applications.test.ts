import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import ashby from "./fixtures/ats-ashby-openai.html?raw";
import greenhouse from "./fixtures/ats-greenhouse-figma.html?raw";
import lever from "./fixtures/ats-lever-kepler.html?raw";
import { collectApplication, installApplications } from "./applications";
import type { ApplicationRequest } from "./messages";

beforeEach(() => {
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
  document.body.innerHTML = lever.replace(/<link[^>]*>/gu, "").replace(/<script[\s\S]*?<\/script>/gu, "");
  document.title = "Kepler Communications - Embedded Software Intern";
});

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

const ID = "6F9619FF-8B86-D011-B42D-00C04FC964FF";

const form = (): HTMLFormElement => {
  const found = document.querySelector("form");
  if (found === null) throw new Error("no form");
  return found;
};

function set(selector: string, value: string): void {
  const field = document.querySelector<HTMLInputElement | HTMLTextAreaElement>(selector);
  if (field === null) throw new Error(`no ${selector}`);
  field.value = value;
}

function attach(name: string): void {
  const input = document.querySelector<HTMLInputElement>("input[type=file]");
  if (input === null) throw new Error("no file input");
  Object.defineProperty(input, "files", { value: [new File(["%PDF"], name)] });
}

function fillIn(): void {
  set("input[name=name]", "Alex Rivera");
  set("input[name=email]", "alex.rivera@example.com");
  set("textarea", "I wrote firmware for a CubeSat radio.\n\tTested it on a bench.");
  const radio = document.querySelector<HTMLInputElement>("input[type=radio][value='3rd']");
  if (radio !== null) radio.checked = true;
  attach("Resume_Fall_2026.pdf");
}

describe("recording a sent application", () => {
  it("keeps each answer, the essay with its lines, and the resume's file name", () => {
    fillIn();
    const application = collectApplication(form(), document, "jobs.lever.co", ID);

    expect(application?.title).toBe("Kepler Communications - Embedded Software Intern");
    expect(application?.path).toBe(window.location.pathname);
    expect(application?.files).toEqual([expect.objectContaining({ name: "Resume_Fall_2026.pdf" })]);
    const answers = application?.fields.map((field) => field.answer) ?? [];
    expect(answers).toContain("Alex Rivera");
    expect(answers).toContain("alex.rivera@example.com");
    expect(answers).toContain("I wrote firmware for a CubeSat radio.\n Tested it on a bench.");
    expect(application?.fields.find((field) => field.answer === "3rd")?.question).toMatch(/year of study/iu);
  });

  it("leaves out demographic questions and sensitive fields", () => {
    form().insertAdjacentHTML(
      "beforeend",
      `<label>Gender <select name="gender"><option>Select</option><option selected>Male</option></select></label>
       <label>Social Security Number <input name="ssn" value="123-45-6789"></label>`,
    );
    set("input[name=name]", "Alex Rivera");

    const answers = collectApplication(form(), document, "jobs.lever.co", ID)?.fields.map((field) => field.answer) ?? [];

    expect(answers).toContain("Alex Rivera");
    expect(answers).not.toContain("Male");
    expect(answers).not.toContain("123-45-6789");
  });

  it("ignores a form that isn't an application", () => {
    document.body.innerHTML = `<form><label>Email <input type="email" value="a@example.com"></label></form>`;
    expect(collectApplication(form(), document, "shop.example.net", ID)).toBeUndefined();
  });
});

describe("recording forms that send without a submit event", () => {
  it("keeps the Yes/No button the person clicked, a typed place and what a searchable list shows", () => {
    vi.useFakeTimers();
    document.body.innerHTML = ashby.replace(/<link[^>]*>/gu, "").replace(/<script[\s\S]*?<\/script>/gu, "");
    const send = vi.fn();
    const { stop } = installApplications(document, window, {
      host: () => "jobs.ashbyhq.com",
      send,
      isUserEvent: () => true,
      newID: () => ID,
    });
    const location = document.querySelector<HTMLInputElement>("input[role=combobox]");
    if (location !== null) location.value = "Berkeley, CA";
    const yes = [...document.querySelectorAll("button")].find((button) => button.textContent.trim() === "Yes");
    yes?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    const submit = [...document.querySelectorAll("button")].find((button) => button.textContent.includes("Submit Application"));
    submit?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    vi.advanceTimersByTime(400);
    stop();
    vi.useRealTimers();

    const sent = send.mock.calls[0]?.[0] as ApplicationRequest | undefined;
    expect(sent?.id).toBe(ID);
    expect(sent?.fields).toContainEqual({ question: expect.stringMatching(/authorized to work/iu) as string, answer: "Yes" });
    expect(sent?.fields).toContainEqual({ question: "Where are you currently located?", answer: "Berkeley, CA" });
  });

  it("reads the choice a React-Select box shows", () => {
    document.body.innerHTML = greenhouse.replace(/<link[^>]*>/gu, "").replace(/<script[\s\S]*?<\/script>/gu, "");
    const placeholder = document.getElementById("react-select-country-placeholder");
    placeholder?.replaceWith(Object.assign(document.createElement("div"), { textContent: "United States" }));
    const scope = document.querySelector("form") ?? document;

    const fields = collectApplication(scope, document, "job-boards.greenhouse.io", ID)?.fields ?? [];

    expect(fields).toContainEqual({ question: "Country*", answer: "United States" });
    expect(fields.filter((field) => field.answer === "United States")).toHaveLength(1);
  });
});
