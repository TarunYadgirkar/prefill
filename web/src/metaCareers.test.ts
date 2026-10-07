import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { classify } from "./classify";
import { isInView } from "./dom";
import { trackGestures } from "./gesture";
import metaCareers from "./fixtures/meta-careers.html?raw";

const field = (label: string): HTMLInputElement => {
  const found = [...document.querySelectorAll("input")].find((input) => input.labels?.[0]?.textContent.trim() === label);
  if (found === undefined) throw new Error(`no ${label}`);
  return found;
};

beforeEach(() => {
  document.body.innerHTML = metaCareers;
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Meta's application form", () => {
  it("reads each field, though the page wraps everything in aria-hidden", () => {
    expect(classify(field("First name"))).toMatchObject({ kind: "name", part: "given" });
    expect(classify(field("Email")).kind).toBe("email");
    expect(classify(field("Phone number")).kind).toBe("phone");
    expect(classify(field("Website (Examples: LinkedIn, GitHub, portfolio)")).kind).toBe("link");
    expect(classify(field("Password")).kind).toBe("sensitive");
  });

  it("counts a field on screen as visible, so a click on it opens Prefill's list", () => {
    const email = field("Email");
    expect(isInView(email)).toBe(true);
    const gate = trackGestures(document, () => true, () => 0);
    email.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    expect(gate.allows(email)).toBe(true);
    gate.stop();
  });
});
