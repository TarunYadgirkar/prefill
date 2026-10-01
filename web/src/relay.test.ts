import { describe, expect, it, vi } from "vitest";
import { relayToNative } from "./relay";

describe("relayToNative", () => {
  it("forwards a ping and returns the native reply", async () => {
    const sendNative = vi.fn().mockResolvedValue({ type: "pong" });
    await expect(relayToNative({ type: "ping" }, sendNative)).resolves.toEqual({ type: "pong" });
    expect(sendNative).toHaveBeenCalledWith({ type: "ping" });
  });

  it("forwards a page context request unchanged", async () => {
    const request = { type: "pageContext", host: "shop.example.net", fields: [{ kind: "email" }] };
    const sendNative = vi.fn().mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(request, sendNative);
    expect(sendNative).toHaveBeenCalledWith(request);
  });

  it.each([null, "ping", { type: "other" }, {}, { type: "capture", host: "example.net" }])("ignores %j", (message) => {
    const sendNative = vi.fn();
    expect(relayToNative(message, sendNative)).toBeUndefined();
    expect(sendNative).not.toHaveBeenCalled();
  });
});
