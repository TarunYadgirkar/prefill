import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ExtensionRequest } from "./messages";
import { startPage, type PageEnvironment } from "./page";

let stop: (() => void) | undefined;

beforeEach(() => {
  vi.useFakeTimers();
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(
    new DOMRect(10, 10, 200, 30),
  );
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
    isTopFrame: true,
    send,
    ...overrides,
  });
  await vi.advanceTimersByTimeAsync(5_000);
  return send;
}

function typeAndSubmit(): void {
  const input = document.querySelector("input");
  if (input === null) throw new Error("no input");
  input.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true }));
  input.value = "new.person@example.org";
  input.dispatchEvent(new Event("input", { bubbles: true }));
  document
    .querySelector("form")
    ?.dispatchEvent(new Event("submit", { bubbles: true }));
}

it("tells the app which contact fields a page has", async () => {
  const send = await load('<input type="email" autocomplete="email">');
  expect(send).toHaveBeenCalledWith({
    type: "pageContext",
    host: "shop.example.net",
    fields: [{ kind: "email" }],
  });
});

it("stays silent on a page without contact fields", async () => {
  const send = await load('<input type="search" name="q">');
  expect(send).not.toHaveBeenCalled();
});

it.each(["file:", "about:", "data:", "blob:"])(
  "does nothing on a %s page",
  async (protocol) => {
    const send = await load('<input type="email" autocomplete="email">', {
      protocol,
    });
    expect(send).not.toHaveBeenCalled();
  },
);

it.each([
  ["plain http", { protocol: "http:", isSecureContext: false }],
  [
    "http on another host that claims to be secure",
    { protocol: "http:", hostname: "shop.example.net" },
  ],
  ["a frame", { isTopFrame: false }],
  ["a frame from another site", { isTopFrame: false, hostname: "ads.example.com" }],
  ["a job form frame inside a plain http page", { isTopFrame: false, hostname: "jobs.lever.co", isSecureContext: false }],
  ["a job form frame over plain http", { isTopFrame: false, protocol: "http:", hostname: "jobs.lever.co" }],
  ["a frame on a look-alike host", { isTopFrame: false, hostname: "jobs.lever.co.example.com" }],
])("does nothing on %s", async (_, overrides: Partial<PageEnvironment>) => {
  const send = await load(
    '<form><input type="email" autocomplete="email"></form>',
    overrides,
  );
  expect(send).not.toHaveBeenCalled();
});

it.each(["boards.greenhouse.io", "jobs.ashbyhq.com", "acme.wd5.myworkdayjobs.com"])(
  "runs in a job application frame from %s, under its own host",
  async (hostname) => {
    const send = await load('<input type="email" autocomplete="email">', { isTopFrame: false, hostname });
    expect(send).toHaveBeenCalledWith({ type: "pageContext", host: hostname, fields: [{ kind: "email" }] });
  },
);

it("runs on http only on this device itself", async () => {
  const send = await load('<input type="email" autocomplete="email">', {
    protocol: "http:",
    hostname: "localhost",
  });
  expect(
    send.mock.calls.map(([request]) => (request as { type: string }).type),
  ).toEqual(["contactSuggestions", "pageContext"]);
});

it("asks Safari's app only for values a minimal card left off", async () => {
  const send = await load('<input type="email" autocomplete="email">');
  expect(send).toHaveBeenCalledWith({
    type: "contactSuggestions",
    host: "shop.example.net",
    fields: [{ kind: "email" }],
    offCard: true,
  });
});

it("ignores events the page dispatches itself", async () => {
  const send = await load(
    '<form><input type="email" autocomplete="email"></form>',
  );
  send.mockClear();
  typeAndSubmit();
  expect(send).not.toHaveBeenCalled();
});

it("sends what the person typed as a capture when the form is submitted", async () => {
  // happy-dom leaves isTrusted undefined; a browser sets it on events the person makes.
  Object.defineProperty(Event.prototype, "isTrusted", {
    get: () => true,
    configurable: true,
  });
  Object.defineProperty(navigator, "userActivation", {
    value: { isActive: true },
    configurable: true,
  });
  try {
    const send = await load(
      '<form><input type="email" autocomplete="email"></form>',
    );
    typeAndSubmit();
    expect(send).toHaveBeenLastCalledWith(
      expect.objectContaining({
        type: "capture",
        host: "shop.example.net",
        trigger: "submit",
      }),
    );
  } finally {
    Reflect.deleteProperty(Event.prototype, "isTrusted");
    Reflect.deleteProperty(navigator, "userActivation");
  }
});

it("removes everything it installed when stopped", async () => {
  const send = await load('<div id="app"></div>');
  stop?.();
  stop = undefined;
  document
    .querySelector("#app")
    ?.insertAdjacentHTML(
      "beforeend",
      '<input type="email" autocomplete="email">',
    );
  await vi.advanceTimersByTimeAsync(5_000);
  expect(send).not.toHaveBeenCalled();
});
