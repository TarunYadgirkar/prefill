import { afterEach, expect, it, vi } from "vitest";

afterEach(() => {
  vi.unstubAllGlobals();
});

it("pings the background script when a page loads", async () => {
  const sendMessage = vi.fn().mockResolvedValue({ type: "pong" });
  vi.stubGlobal("browser", { runtime: { sendMessage } });
  await import("./content");
  expect(sendMessage).toHaveBeenCalledWith({ type: "ping" });
});
