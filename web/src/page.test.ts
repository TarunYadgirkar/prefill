import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ExtensionRequest } from "./messages";
import { startPage, type PageEnvironment } from "./page";

let stop: (() => void) | undefined;

beforeEach(() => {
  vi.useFakeTimers();
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
});

afterEach(() => {
  stop?.();
  stop = undefined;
  document.body.innerHTML = "";
  vi.useRealTimers();
  vi.restoreAllMocks();
});

async function load(html: string, overrides: Partial<PageEnvironment> = {}) {
  document.body.innerHTML = html;
  const send = vi
    .fn<(request: ExtensionRequest) => Promise<unknown>>()
    .mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
  stop = startPage({
    doc: document,
    win: window,
    protocol: "https:",
    hostname: "shop.example.net",
    isSecureContext: true,
    send,
    ...overrides,
  });
  await vi.advanceTimersByTimeAsync(5_000);
  return send;
}

function typeAndSubmit(): void {
  const input = document.querySelector("input");
  if (input === null) throw new Error("no input");
  input.value = "new.person@example.org";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  document.querySelector("form")?.dispatchEvent(new Event("submit", { bubbles: true }));
}

it("tells the app which contact fields a page has", async () => {
  const send = await load('<input type="email" autocomplete="email">');
  expect(send).toHaveBeenCalledWith({ type: "pageContext", host: "shop.example.net", fields: [{ kind: "email" }] });
});

it("stays silent on a page without contact fields", async () => {
  const send = await load('<input type="search" name="q">');
  expect(send).not.toHaveBeenCalled();
});

it.each(["file:", "about:", "data:", "blob:"])("does nothing on a %s page", async (protocol) => {
  const send = await load('<input type="email" autocomplete="email">', { protocol });
  expect(send).not.toHaveBeenCalled();
});

it("listens for submits on a secure page and not on plain http", async () => {
  const html = '<form><input type="email" autocomplete="email"></form>';
  const listening = vi.spyOn(document, "addEventListener");
  await load(html, { protocol: "http:", isSecureContext: false });
  expect(listening.mock.calls.map(([type]) => type)).not.toContain("submit");
  stop?.();
  listening.mockClear();
  await load(html);
  expect(listening.mock.calls.map(([type]) => type)).toContain("submit");
});

it("ignores events the page dispatches itself", async () => {
  const send = await load('<form><input type="email" autocomplete="email"></form>');
  send.mockClear();
  typeAndSubmit();
  expect(send).not.toHaveBeenCalled();
});

it("sends what the person typed as a capture when the form is submitted", async () => {
  // happy-dom leaves isTrusted undefined; a browser sets it on events the person makes.
  Object.defineProperty(Event.prototype, "isTrusted", { get: () => true, configurable: true });
  try {
    const send = await load('<form><input type="email" autocomplete="email"></form>');
    typeAndSubmit();
    expect(send).toHaveBeenLastCalledWith(
      expect.objectContaining({ type: "capture", host: "shop.example.net", submitted: true }),
    );
  } finally {
    Reflect.deleteProperty(Event.prototype, "isTrusted");
  }
});

it("removes everything it installed when stopped", async () => {
  const send = await load('<div id="app"></div>');
  stop?.();
  stop = undefined;
  document.querySelector("#app")?.insertAdjacentHTML("beforeend", '<input type="email" autocomplete="email">');
  await vi.advanceTimersByTimeAsync(5_000);
  expect(send).not.toHaveBeenCalled();
});
