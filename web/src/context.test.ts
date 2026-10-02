import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import formHtml from "../../testbed/form.html?raw";
import { contactFields, installContext } from "./context";
import checkoutTagged from "./fixtures/checkout-tagged.html?raw";
import type { PageContextRequest } from "./messages";

const DEBOUNCE = 300;
const MAX_WAIT = 1_000;
const UNCHANGED = { type: "pageContextResult", status: "unchanged" };
let uninstall: (() => void) | undefined;

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  uninstall?.();
  uninstall = undefined;
  document.body.innerHTML = "";
  Reflect.deleteProperty(document, "visibilityState");
  vi.useRealTimers();
});

type Send = (request: PageContextRequest) => Promise<unknown>;

function start(reply: () => Promise<unknown> = () => new Promise(() => undefined), minIntervalMs = 0) {
  const send = vi.fn<Send>().mockImplementation(reply);
  uninstall = installContext(document, window, {
    host: () => "shop.example.net",
    send,
    debounceMs: DEBOUNCE,
    maxWaitMs: MAX_WAIT,
    minIntervalMs,
  });
  return send;
}

function focus(target: Element | null): void {
  target?.dispatchEvent(new FocusEvent("focusin", { bubbles: true, composed: true }));
}

function kinds(send: ReturnType<typeof start>, call: number): string[] {
  return send.mock.calls[call]?.[0].fields.map((field) => field.kind) ?? [];
}

const settle = () => vi.advanceTimersByTimeAsync(DEBOUNCE * 10);

// happy-dom's PageTransitionEvent has no `persisted`.
function pageshow(persisted: boolean): void {
  window.dispatchEvent(Object.assign(new Event("pageshow"), { persisted }));
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

  it("stops at 40 fields", () => {
    document.body.innerHTML = '<input type="email">'.repeat(60);
    expect(contactFields(document)).toHaveLength(40);
  });

  it("finds fields inside open shadow roots", () => {
    document.body.innerHTML = "<x-signup></x-signup>";
    const shadow = document.querySelector("x-signup")?.attachShadow({ mode: "open" });
    if (shadow === undefined) throw new Error("no shadow root");
    shadow.innerHTML = '<input type="email" autocomplete="work email">';
    expect(contactFields(document)).toEqual([{ kind: "email", section: "work" }]);
  });
});

describe("installContext", () => {
  it("sends one pageContext after the page settles", async () => {
    document.body.innerHTML = formHtml;
    const send = start();
    expect(send).not.toHaveBeenCalled();
    await settle();
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0]).toMatchObject({ type: "pageContext", host: "shop.example.net" });
    expect(kinds(send, 0)).toEqual(["email", "phone", ...Array<string>(4).fill("address"), "email", "phone"]);
  });

  it("sends nothing from a page without contact fields", async () => {
    document.body.innerHTML = '<form><input name="q" type="search"><input type="password"></form>';
    const send = start();
    await settle();
    document.body.insertAdjacentHTML("beforeend", "<p>More text</p>");
    await settle();
    expect(send).not.toHaveBeenCalled();
  });

  it("notices a form an app renders after load", async () => {
    document.body.innerHTML = '<div id="app"></div>';
    const send = start();
    await settle();
    document.querySelector("#app")?.insertAdjacentHTML("beforeend", '<input type="email" autocomplete="work email">');
    await settle();
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0].fields).toEqual([{ kind: "email", section: "work" }]);
  });

  it("sends again when a later step adds a new kind of field, and not for more of the same", async () => {
    document.body.innerHTML = '<div id="app"><input type="email" autocomplete="email"></div>';
    const send = start();
    await settle();
    document.querySelector("#app")?.insertAdjacentHTML("beforeend", '<input type="email" name="confirm_email">');
    await settle();
    expect(send).toHaveBeenCalledTimes(1);
    document.querySelector("#app")?.insertAdjacentHTML("beforeend", '<input autocomplete="shipping street-address">');
    await settle();
    expect(send).toHaveBeenCalledTimes(2);
    expect(kinds(send, 1)).toEqual(["email", "email", "address"]);
  });

  it("still sends on a page that never stops changing", async () => {
    document.body.innerHTML = '<input type="email" autocomplete="email"><div id="ticker"></div>';
    const send = start();
    const ticker = document.querySelector("#ticker");
    for (let elapsed = 0; elapsed < 2_000; elapsed += 100) {
      ticker?.replaceChildren(Object.assign(document.createElement("input"), { type: "search" }));
      await vi.advanceTimersByTimeAsync(100);
    }
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("doesn't look again for changes that add no fields", async () => {
    document.body.innerHTML = '<input type="email" autocomplete="email"><p id="clock"></p>';
    const send = start();
    await settle();
    const scheduled = vi.getTimerCount();
    document.querySelector("#clock")?.append(document.createElement("span"), "12:01");
    await Promise.resolve();
    expect(vi.getTimerCount()).toBe(scheduled);
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("sends right away when a contact field is focused before the page settles", async () => {
    document.body.innerHTML = formHtml;
    const send = start();
    focus(document.querySelector("[name=email]"));
    expect(send).toHaveBeenCalledTimes(1);
    await settle();
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("sends again on the first focus of a contact field, even after a reply, since another tab may have reordered the card", async () => {
    document.body.innerHTML = formHtml;
    const send = start(() => Promise.resolve(UNCHANGED));
    await settle();
    focus(document.querySelector("[name=name]"));
    expect(send).toHaveBeenCalledTimes(1);
    focus(document.querySelector("[name=email]"));
    focus(document.querySelector("[name=tel]"));
    await settle();
    expect(send).toHaveBeenCalledTimes(2);
  });

  it.each([
    ["an error", () => Promise.resolve({ type: "error", reason: "unreadable reply" })],
    ["a failure", () => Promise.resolve({ type: "pageContextResult", status: "failed", reason: "no access" })],
    ["a rejection", () => Promise.reject(new Error("no handler"))],
  ])("keeps a focus retry after %s", async (_, reply) => {
    document.body.innerHTML = formHtml;
    const send = start(reply);
    await settle();
    focus(document.querySelector("[name=email]"));
    await settle();
    focus(document.querySelector("[name=tel]"));
    expect(send).toHaveBeenCalledTimes(3);
  });

  it("sends again when the page comes back from the back-forward cache", async () => {
    document.body.innerHTML = formHtml;
    const send = start(() => Promise.resolve(UNCHANGED));
    await settle();
    pageshow(false);
    expect(send).toHaveBeenCalledTimes(1);
    pageshow(true);
    expect(send).toHaveBeenCalledTimes(2);
  });

  it("sends again when the tab comes back into view, then once more on focus", async () => {
    document.body.innerHTML = formHtml;
    const send = start(() => Promise.resolve(UNCHANGED));
    await settle();
    focus(document.querySelector("[name=email]"));
    expect(send).toHaveBeenCalledTimes(2);
    Object.defineProperty(document, "visibilityState", { value: "hidden", configurable: true });
    document.dispatchEvent(new Event("visibilitychange"));
    expect(send).toHaveBeenCalledTimes(2);
    Object.defineProperty(document, "visibilityState", { value: "visible", configurable: true });
    document.dispatchEvent(new Event("visibilitychange"));
    expect(send).toHaveBeenCalledTimes(3);
    focus(document.querySelector("[name=email]"));
    expect(send).toHaveBeenCalledTimes(4);
  });

  it("spaces reports at least two seconds apart and stops after five", async () => {
    document.body.innerHTML = formHtml;
    const send = start(() => Promise.resolve(UNCHANGED), 2_000);
    await settle();
    expect(send).toHaveBeenCalledTimes(1);
    const comeBack = (): void => {
      Object.defineProperty(document, "visibilityState", { value: "visible", configurable: true });
      document.dispatchEvent(new Event("visibilitychange"));
    };
    comeBack();
    expect(send).toHaveBeenCalledTimes(2);
    comeBack();
    comeBack();
    expect(send).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(send).toHaveBeenCalledTimes(3);
    for (let round = 0; round < 10; round += 1) {
      comeBack();
      await vi.advanceTimersByTimeAsync(2_000);
    }
    expect(send).toHaveBeenCalledTimes(5);
  });

  it("hears focus on a field inside an open shadow root", () => {
    document.body.innerHTML = "<x-signup></x-signup>";
    const shadow = document.querySelector("x-signup")?.attachShadow({ mode: "open" });
    if (shadow === undefined) throw new Error("no shadow root");
    shadow.innerHTML = '<input type="email" autocomplete="email">';
    const send = start();
    focus(shadow.querySelector("input"));
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("removes its listeners and observer when uninstalled", async () => {
    document.body.innerHTML = '<div id="app"></div>';
    const send = start();
    uninstall?.();
    uninstall = undefined;
    document.querySelector("#app")?.insertAdjacentHTML("beforeend", '<input type="email" autocomplete="email">');
    focus(document.querySelector("input"));
    pageshow(true);
    await settle();
    expect(send).not.toHaveBeenCalled();
  });
});
