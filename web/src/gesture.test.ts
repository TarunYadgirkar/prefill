import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { trackGestures } from "./gesture";

beforeEach(() => {
  document.body.innerHTML = '<input id="first"><input id="second">';
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(
    new DOMRect(10, 10, 200, 30),
  );
});

afterEach(() => {
  vi.restoreAllMocks();
});

const input = (id: string): HTMLInputElement =>
  document.getElementById(id) as HTMLInputElement;

describe("the click-or-Tab gate", () => {
  it("lets one Tab through to the first field focused after it, and no other", () => {
    const gate = trackGestures(
      document,
      () => true,
      () => 0,
    );
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab" }));
    input("first").dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(gate.allows(input("first"))).toBe(true);
    expect(gate.allows(input("first"))).toBe(true);
    input("second").dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(gate.allows(input("second"))).toBe(false);
    gate.stop();
  });

  it("lets a click through only to the field clicked", () => {
    const gate = trackGestures(
      document,
      () => true,
      () => 0,
    );
    input("first").dispatchEvent(new Event("pointerdown", { bubbles: true }));
    expect(gate.allows(input("first"))).toBe(true);
    expect(gate.allows(input("second"))).toBe(false);
    gate.stop();
  });
});
