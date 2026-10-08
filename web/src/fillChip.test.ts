import { afterEach, describe, expect, it, vi } from "vitest";
import { installFillChip } from "./fillChip";
import { trackGestures } from "./gesture";

afterEach(() => {
  document.body.innerHTML = "";
  document.querySelectorAll("prefill-fill").forEach((host) => {
    host.remove();
  });
  vi.restoreAllMocks();
});

describe("the Fill form pill", () => {
  it("says what a fill left and moves to each of those fields, unlocking only that one", async () => {
    document.body.innerHTML = '<form><input id="a"><input id="b"><input id="c"></form>';
    const field = (id: string) => document.getElementById(id) as HTMLInputElement;
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
    Element.prototype.scrollIntoView = function (this: Element) {
      document.elementFromPoint = () => this;
    };
    // The pill's root is closed; the test keeps the handle the page never gets.
    let root: ShadowRoot | undefined;
    const { attachShadow } = Object.getOwnPropertyDescriptors(Element.prototype);
    vi.spyOn(Element.prototype, "attachShadow").mockImplementation(function (this: Element, init: ShadowRootInit) {
      root = (attachShadow.value as (this: Element, init: ShadowRootInit) => ShadowRoot).call(this, init);
      return root;
    });
    let clock = 0;
    const now = () => clock;
    const gate = trackGestures(document, () => true, now);
    const list = trackGestures(document, () => true, now);
    const left = () => [field("b"), field("c")].filter((input) => input.value === "");
    const stop = installFillChip(document, window, {
      gate,
      count: () => Promise.resolve(3),
      fill: () => Promise.resolve({ filled: 1, undo: () => undefined }),
      left,
      note: (target) => (target.id === "c" ? "2 options fit, pick one" : undefined),
      isUserEvent: () => true,
      now,
    });
    const press = async (action: string) => {
      clock += 1_000;
      root?.querySelector(`[data-action=${action}]`)?.dispatchEvent(new MouseEvent("click", { bubbles: true, composed: true }));
      await Promise.resolve();
      await Promise.resolve();
    };

    field("a").dispatchEvent(new Event("pointerdown", { bubbles: true }));
    field("a").focus();
    await Promise.resolve();
    await Promise.resolve();
    await press("fill");
    expect(root?.textContent).toContain("2 need you");

    await press("next");
    expect(document.activeElement).toBe(field("b"));
    expect(root?.textContent).toContain("Filled 1");
    expect(root?.textContent).toContain("need you");
    expect(list.allows(field("b"))).toBe(true);
    expect(list.allows(field("c"))).toBe(false);

    field("b").value = "typed";
    await press("next");
    expect(document.activeElement).toBe(field("c"));
    expect(root?.textContent).toContain("1 needs you");
    expect(root?.textContent).toContain("2 options fit, pick one");
    expect(list.allows(field("b"))).toBe(false);
    stop();
    gate.stop();
    list.stop();
  });
});
