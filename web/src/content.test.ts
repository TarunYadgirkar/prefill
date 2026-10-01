import { afterEach, expect, it, vi } from "vitest";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.resetModules();
  vi.useRealTimers();
  document.body.innerHTML = "";
});

async function load(html: string) {
  vi.useFakeTimers();
  document.body.innerHTML = html;
  const sendMessage = vi.fn().mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
  vi.stubGlobal("browser", { runtime: { sendMessage } });
  await import("./content");
  await vi.advanceTimersByTimeAsync(5_000);
  return sendMessage;
}

it("tells the app which contact fields a page has", async () => {
  const sendMessage = await load('<input type="email" autocomplete="email">');
  expect(sendMessage).toHaveBeenCalledWith({
    type: "pageContext",
    host: location.hostname,
    fields: [{ kind: "email" }],
  });
});

it("stays silent on a page without contact fields", async () => {
  const sendMessage = await load('<input type="search" name="q">');
  expect(sendMessage).not.toHaveBeenCalled();
});
