import { describe, expect, it, vi } from "vitest";
import { relayToNative } from "./relay";

const ID = "com.tarunyadgirkar.prefill.Extension";
const fromPage = { id: ID, url: "https://shop.example.net/checkout" };

describe("relayToNative", () => {
  it("forwards a ping and returns the native reply", async () => {
    const sendNative = vi.fn().mockResolvedValue({ type: "pong" });
    await expect(relayToNative({ type: "ping" }, fromPage, ID, sendNative)).resolves.toEqual({ type: "pong" });
    expect(sendNative).toHaveBeenCalledWith({ type: "ping" });
  });

  it("forwards a page context request rebuilt from its known fields", async () => {
    const request = { type: "pageContext", host: "shop.example.net", fields: [{ kind: "email", extra: 1 }], note: "x" };
    const sendNative = vi.fn().mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(request, fromPage, ID, sendNative);
    expect(sendNative).toHaveBeenCalledWith({
      type: "pageContext",
      host: "shop.example.net",
      fields: [{ kind: "email" }],
    });
  });

  it("uses the host the browser reports for the sender, not the one in the message", async () => {
    const request = { type: "pageContext", host: "pay.example.com", fields: [{ kind: "email" }] };
    const sendNative = vi.fn().mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(request, fromPage, ID, sendNative);
    expect(sendNative).toHaveBeenCalledWith(expect.objectContaining({ host: "shop.example.net" }));
  });

  it("keeps the message's host when the sender has no web address", async () => {
    const request = { type: "pageContext", host: "shop.example.net", fields: [{ kind: "email" }] };
    const sendNative = vi.fn().mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(request, { id: ID }, ID, sendNative);
    expect(sendNative).toHaveBeenCalledWith(expect.objectContaining({ host: "shop.example.net" }));
  });

  it("turns away messages from another extension", () => {
    const sendNative = vi.fn();
    expect(relayToNative({ type: "ping" }, { id: "someone.else" }, ID, sendNative)).toBeUndefined();
    expect(sendNative).not.toHaveBeenCalled();
  });

  it("turns a malformed native reply into an error", async () => {
    const sendNative = vi.fn().mockResolvedValue({ type: "pageContextResult", status: "maybe" });
    await expect(relayToNative({ type: "ping" }, fromPage, ID, sendNative)).resolves.toEqual({
      type: "error",
      reason: "unreadable reply",
    });
  });

  it.each([null, "ping", { type: "other" }, {}, { type: "capture", host: "example.net" }])("ignores %j", (message) => {
    const sendNative = vi.fn();
    expect(relayToNative(message, fromPage, ID, sendNative)).toBeUndefined();
    expect(sendNative).not.toHaveBeenCalled();
  });
});
