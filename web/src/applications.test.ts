import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import lever from "./fixtures/ats-lever-kepler.html?raw";
import { collectApplication } from "./applications";

beforeEach(() => {
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
  document.body.innerHTML = lever.replace(/<link[^>]*>/gu, "").replace(/<script[\s\S]*?<\/script>/gu, "");
  document.title = "Kepler Communications - Embedded Software Intern";
});

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

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
    const application = collectApplication(form(), document, "jobs.lever.co");

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

    const answers = collectApplication(form(), document, "jobs.lever.co")?.fields.map((field) => field.answer) ?? [];

    expect(answers).toContain("Alex Rivera");
    expect(answers).not.toContain("Male");
    expect(answers).not.toContain("123-45-6789");
  });

  it("ignores a form that isn't an application", () => {
    document.body.innerHTML = `<form><label>Email <input type="email" value="a@example.com"></label></form>`;
    expect(collectApplication(form(), document, "shop.example.net")).toBeUndefined();
  });
});
