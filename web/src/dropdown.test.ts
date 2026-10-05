import { afterEach, describe, expect, it, vi } from "vitest";
import { matching, showDropdown, type Choice } from "./dropdown";

const choices: Choice[] = [
  { value: "+1 510 555 0100", detail: "Phone" },
  { value: "+1 415 555 0199", detail: "Phone" },
];

function setUp(isUserEvent: (event: Event) => boolean = () => true) {
  document.body.innerHTML = '<input type="tel" id="phone">';
  const input = document.querySelector("input");
  if (input === null) throw new Error("no input");
  // The dropdown's root is closed; the test keeps the handle the page never gets.
  let root: ShadowRoot | undefined;
  const { attachShadow } = Object.getOwnPropertyDescriptors(Element.prototype);
  vi.spyOn(Element.prototype, "attachShadow").mockImplementation(function (
    this: Element,
    init: ShadowRootInit,
  ) {
    root = (
      attachShadow.value as (this: Element, init: ShadowRootInit) => ShadowRoot
    ).call(this, init);
    return root;
  });
  const events: string[] = [];
  input.addEventListener("input", () => events.push(`input ${input.value}`));
  input.addEventListener("change", () => events.push(`change ${input.value}`));
  input.focus();
  const hide = showDropdown(input, choices, isUserEvent);
  const rows = (): string[] =>
    [...(root?.querySelectorAll(".row .value") ?? [])].map(
      (row) => row.textContent,
    );
  const press = (key: string): void => {
    input.dispatchEvent(
      new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
    );
  };
  return { input, hide, rows, press, events };
}

describe("showDropdown", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    document.querySelectorAll("prefill-suggestions").forEach((host) => {
      host.remove();
    });
    vi.restoreAllMocks();
  });

  it("fills the chosen value with input and change events, from the keyboard", () => {
    const { input, rows, press, events, hide } = setUp();
    expect(rows()).toEqual(["+1 510 555 0100", "+1 415 555 0199"]);
    press("ArrowDown");
    press("ArrowDown");
    press("Enter");
    expect(input.value).toBe("+1 415 555 0199");
    expect(events).toEqual(["input +1 415 555 0199", "change +1 415 555 0199"]);
    expect(rows()).toEqual([]);
    hide();
    expect(document.querySelector("prefill-suggestions")).toBeNull();
  });

  it("ignores keys the page made up", () => {
    const { input, press, events } = setUp(() => false);
    press("ArrowDown");
    press("Enter");
    expect(input.value).toBe("");
    expect(events).toEqual([]);
  });

  it("closes on Escape and narrows to what's typed", () => {
    const { input, rows, press } = setUp();
    press("Escape");
    expect(rows()).toEqual([]);
    input.value = "415";
    input.dispatchEvent(new Event("input"));
    expect(rows()).toEqual(["+1 415 555 0199"]);
  });
});

describe("matching", () => {
  it("offers nothing once the field holds a value", () => {
    expect(matching(choices, "+1 510 555 0100")).toEqual([]);
    expect(matching(choices, " ")).toEqual(choices);
  });

  // Partiful's RSVP form holds the number as ten digits with no country code.
  it("reads a phone number by its digits, whatever its format", () => {
    const phones: Choice[] = [
      { value: "+1 (510) 555-0100", detail: "Phone" },
      { value: "+1 415 555 0199", detail: "Phone" },
    ];
    expect(matching(phones, "5105550100")).toEqual([]);
    expect(matching(phones, "415-555")).toEqual([phones[1]]);
    expect(matching(phones, "2025550123")).toEqual([]);
  });
});
