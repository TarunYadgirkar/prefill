import { afterEach, describe, expect, it, vi } from "vitest";
import { listSpot, matching, SAFARI_CONTACT, showDropdown, type Choice } from "./dropdown";

const choices: Choice[] = [
  { value: "+1 510 555 0100", detail: "Phone" },
  { value: "+1 415 555 0199", detail: "Phone" },
];

function setUp(
  isUserEvent: (event: Event) => boolean = () => true,
  offered: Choice[] = choices,
) {
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
  const hide = showDropdown(input, offered, isUserEvent);
  const rows = (): string[] =>
    [...(root?.querySelectorAll(".row .value") ?? [])].map(
      (row) => row.textContent,
    );
  const press = (key: string): void => {
    input.dispatchEvent(
      new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }),
    );
  };
  const guesses = (): string[] =>
    [...(root?.querySelectorAll(".row.guess .value") ?? [])].map((row) => row.textContent);
  return { input, hide, rows, press, events, guesses };
}

describe("showDropdown", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    document.querySelectorAll("prefill-suggestions").forEach((host) => {
      host.remove();
    });
    vi.restoreAllMocks();
  });

  it("draws a guess apart from the person's own values", () => {
    const { guesses, hide } = setUp(undefined, [
      { value: "UC Berkeley", detail: "School" },
      { value: "EECS", detail: "Suggested", tone: "guess" },
    ]);
    expect(guesses()).toEqual(["EECS"]);
    hide();
  });

  it("shows a note that can't be picked, even with nothing else to offer", () => {
    const { input, rows, press, hide } = setUp(undefined, [{ value: "No answer for Canada yet", detail: "", tone: "note" }]);
    const host = document.querySelector<HTMLElement>("prefill-suggestions");
    expect(host?.style.getPropertyValue("display")).toBe("block");
    expect(rows()).toEqual([]);
    press("ArrowDown");
    press("Enter");
    expect(input.value).toBe("");
    press("Escape");
    expect(host?.style.getPropertyValue("display")).toBe("none");
    hide();
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

  it("tells the list's owner which value was picked, once it's in the field", () => {
    const picked: string[] = [];
    const { input, press } = setUp(() => true, [
      { value: "+1 510 555 0100", detail: "Phone" },
      { value: "+1 415 555 0199", detail: "Phone", onPick: () => picked.push(input.value) },
    ]);
    press("ArrowDown");
    press("ArrowDown");
    press("Enter");
    expect(picked).toEqual(["+1 415 555 0199"]);
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

describe("listSpot", () => {
  const field = new DOMRect(16, 231, 234, 45);
  const under = { above: 0, below: 0, preferAbove: false };

  it("puts the list under its field when it fits, else over it", () => {
    expect(listSpot(field, 150, 800, under)).toEqual({ top: 280 });
    expect(listSpot(field, 150, 400, under)).toEqual({ top: 77 });
  });

  it("keeps Safari's list over a contact field, clear of the pill, or past Safari's band", () => {
    expect(listSpot(field, 150, 545, SAFARI_CONTACT)).toEqual({ top: 231 - 4 - 44 - 150 });
    const nearTop = new DOMRect(16, 60, 234, 45);
    expect(listSpot(nearTop, 150, 545, SAFARI_CONTACT)).toEqual({ top: 105 + 4 + 124 });
  });

  it("cuts the list to the side with more room when neither side fits", () => {
    expect(listSpot(field, 190, 487, SAFARI_CONTACT)).toEqual({ top: 0, maxHeight: 183 });
  });
});
