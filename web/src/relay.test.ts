import { describe, expect, it, vi } from "vitest";
import { relayToNative } from "./relay";

const ID = "com.tarunyadgirkar.prefill.Extension";
const fromPage = {
  id: ID,
  url: "https://shop.example.net/checkout",
  frameId: 0,
  tab: { incognito: false },
};

describe("relayToNative", () => {
  it("forwards a ping and returns the native reply", async () => {
    const sendNative = vi.fn().mockResolvedValue({ type: "pong" });
    await expect(
      relayToNative({ type: "ping" }, fromPage, ID, sendNative),
    ).resolves.toEqual({ type: "pong" });
    expect(sendNative).toHaveBeenCalledWith({ type: "ping" });
  });

  it("forwards a page context request rebuilt from its known fields", async () => {
    const request = {
      type: "pageContext",
      host: "shop.example.net",
      fields: [{ kind: "email", extra: 1 }],
      note: "x",
    };
    const sendNative = vi
      .fn()
      .mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(request, fromPage, ID, sendNative);
    expect(sendNative).toHaveBeenCalledWith({
      type: "pageContext",
      host: "shop.example.net",
      fields: [{ kind: "email" }],
    });
  });

  it("uses the host the browser reports for the sender, not the one in the message", async () => {
    const request = {
      type: "pageContext",
      host: "pay.example.com",
      fields: [{ kind: "email" }],
    };
    const sendNative = vi
      .fn()
      .mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(request, fromPage, ID, sendNative);
    expect(sendNative).toHaveBeenCalledWith(
      expect.objectContaining({ host: "shop.example.net" }),
    );
  });

  it.each([
    ["another extension", { ...fromPage, id: "someone.else" }],
    ["a sender with no extension id", { ...fromPage, id: undefined }],
    ["a Private Browsing tab", { ...fromPage, tab: { incognito: true } }],
    ["a tab that doesn't say whether it is private", { ...fromPage, tab: {} }],
    ["a sender outside any tab", { ...fromPage, tab: undefined }],
    ["a frame inside the page", { ...fromPage, frameId: 3 }],
    ["a plain http page", { ...fromPage, url: "http://shop.example.net/" }],
    ["a sender with no web address", { ...fromPage, url: undefined }],
    ["a file", { ...fromPage, url: "file:///Users/alex/form.html" }],
  ])("turns away messages from %s", (_, sender) => {
    const sendNative = vi.fn();
    const request = {
      type: "pageContext",
      host: "shop.example.net",
      fields: [{ kind: "email" }],
    };
    expect(relayToNative(request, sender, ID, sendNative)).toBeUndefined();
    expect(sendNative).not.toHaveBeenCalled();
  });

  it("accepts plain http from this device itself", async () => {
    const request = {
      type: "pageContext",
      host: "localhost",
      fields: [{ kind: "email" }],
    };
    const sendNative = vi
      .fn()
      .mockResolvedValue({ type: "pageContextResult", status: "unchanged" });
    await relayToNative(
      request,
      { ...fromPage, url: "http://localhost:8846/signup.html" },
      ID,
      sendNative,
    );
    expect(sendNative).toHaveBeenCalledWith(
      expect.objectContaining({ host: "localhost" }),
    );
  });

  it("turns a malformed native reply into an error", async () => {
    const sendNative = vi
      .fn()
      .mockResolvedValue({ type: "pageContextResult", status: "maybe" });
    await expect(
      relayToNative({ type: "ping" }, fromPage, ID, sendNative),
    ).resolves.toEqual({
      type: "error",
      reason: "unreadable reply",
    });
  });

  it.each([
    null,
    "ping",
    { type: "other" },
    {},
    { type: "capture", host: "example.net" },
  ])("ignores %j", (message) => {
    const sendNative = vi.fn();
    expect(relayToNative(message, fromPage, ID, sendNative)).toBeUndefined();
    expect(sendNative).not.toHaveBeenCalled();
  });
});

describe("the sheet's messages and the review badge", () => {
  const tab = { incognito: false, id: 7 };

  it("never relays a sheet request from a page, since its reply holds the person's values", () => {
    const sendNative = vi.fn();
    const request = {
      type: "popupState",
      host: "shop.example.net",
      kinds: ["email"],
    };
    expect(relayToNative(request, fromPage, ID, sendNative)).toBeUndefined();
    expect(sendNative).not.toHaveBeenCalled();
  });

  it("never hands a sheet reply to a page", async () => {
    const sendNative = vi.fn().mockResolvedValue({
      type: "popupStateResult",
      status: "ready",
      kinds: [],
      recent: [],
      muted: false,
    });
    await expect(
      relayToNative({ type: "ping" }, fromPage, ID, sendNative),
    ).resolves.toEqual({
      type: "error",
      reason: "unreadable reply",
    });
  });

  it.each([
    [{ saved: 0, review: 2, ignored: 0 }, [[7, 2]]],
    [{ saved: 1, review: 0, ignored: 0 }, []],
  ])(
    "marks the tab only when values wait for review (%j)",
    async (counts, calls) => {
      const sendNative = vi
        .fn()
        .mockResolvedValue({ type: "captureResult", ...counts });
      const mark = vi.fn();
      const capture = {
        type: "capture",
        host: "x",
        hasPassword: false,
        trigger: "submit",
        fields: [],
      };
      await relayToNative(capture, { ...fromPage, tab }, ID, sendNative, mark);
      expect(mark.mock.calls).toEqual(calls);
    },
  );
});
