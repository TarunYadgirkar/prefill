import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import formHtml from "../../testbed/form.html?raw";
import { contactFields, installContext } from "./context";
import checkoutTagged from "./fixtures/checkout-tagged.html?raw";
import type { PageContextRequest } from "./messages";

const DEBOUNCE = 300;
let uninstall: (() => void) | undefined;

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  uninstall?.();
  uninstall = undefined;
  document.body.innerHTML = "";
  vi.useRealTimers();
});

function start(reply: Promise<unknown> = new Promise(() => undefined)) {
  const send = vi.fn<(request: PageContextRequest) => Promise<unknown>>().mockReturnValue(reply);
  uninstall = installContext(document, { host: () => "shop.example.net", send, debounceMs: DEBOUNCE });
  return send;
}

function focus(selector: string): void {
  document.querySelector(selector)?.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
}

describe("contactFields", () => {
  it("lists contact kinds and sections in page order, without names or card fields", () => {
    document.body.innerHTML = checkoutTagged;
    expect(contactFields(document)).toEqual([
      { kind: "email" },
      ...Array<unknown>(6).fill({ kind: "address", section: "shipping" }),
      { kind: "phone", section: "shipping" },
      ...Array<unknown>(3).fill({ kind: "address", section: "billing" }),
    ]);
  });
});

describe("installContext", () => {
  it("sends one pageContext after the page settles", async () => {
    document.body.innerHTML = formHtml;
    const send = start();
    expect(send).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0]).toMatchObject({ type: "pageContext", host: "shop.example.net" });
    expect(send.mock.calls[0]?.[0].fields.map((field) => field.kind)).toEqual([
      "email",
      "phone",
      ...Array<string>(4).fill("address"),
      "email",
      "phone",
    ]);
  });

  it("sends nothing from a page without contact fields", async () => {
    document.body.innerHTML = '<form><input name="q" type="search"><input type="password"></form>';
    const send = start();
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    document.body.insertAdjacentHTML("beforeend", "<p>More text</p>");
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    expect(send).not.toHaveBeenCalled();
  });

  it("notices a form an app renders after load", async () => {
    document.body.innerHTML = '<div id="app"></div>';
    const send = start();
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    document.querySelector("#app")?.insertAdjacentHTML("beforeend", '<input type="email" autocomplete="work email">');
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0].fields).toEqual([{ kind: "email", section: "work" }]);
  });

  it("sends again once when a contact field is focused before any reply", async () => {
    document.body.innerHTML = formHtml;
    const send = start();
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    focus("[name=name]");
    expect(send).toHaveBeenCalledTimes(1);
    focus("[name=email]");
    focus("[name=tel]");
    expect(send).toHaveBeenCalledTimes(2);
  });

  it("sends right away when a contact field is focused before the page settles", () => {
    document.body.innerHTML = formHtml;
    const send = start();
    focus("[name=email]");
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("stays quiet on focus once the app has replied", async () => {
    document.body.innerHTML = formHtml;
    const send = start(Promise.resolve({ type: "pageContextResult", status: "unchanged" }));
    await vi.advanceTimersByTimeAsync(DEBOUNCE * 10);
    focus("[name=email]");
    expect(send).toHaveBeenCalledTimes(1);
  });
});
