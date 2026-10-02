import { describe, expect, it } from "vitest";
import type { PopupStateResult } from "../messages";
import { merge, openingFor } from "./sheet";

const needs = { host: "shop.example.net", kinds: ["email" as const] };

describe("openingFor", () => {
  it("takes the host from the tab and the kinds from the page", () => {
    expect(openingFor({ url: "https://www.example.net/a", incognito: false }, needs)).toEqual({
      site: { host: "www.example.net", kinds: ["email"] },
    });
  });

  it("uses the page's answer when Safari doesn't share the address", () => {
    expect(openingFor({ incognito: false }, needs)).toEqual({ site: { host: "shop.example.net", kinds: ["email"] } });
  });

  it("shows every kind on a page without contact fields", () => {
    expect(openingFor({ url: "https://example.net/" }, { host: "example.net", kinds: [] })).toEqual({
      site: { host: "example.net", kinds: ["email", "phone", "address"] },
    });
  });

  it.each([
    [{ url: "https://example.net/", incognito: true }, "private"],
    [{ url: "http://example.net/" }, "unsupported"],
    [{ url: "about:blank" }, "unsupported"],
  ])("explains why it can't help on %j", (tab, problem) => {
    expect(openingFor(tab, needs)).toEqual({ problem });
  });

  it("can't help without a tab or an answer from the page", () => {
    expect(openingFor(undefined, undefined)).toEqual({ problem: "unsupported" });
  });
});

describe("merge", () => {
  const value = (id: string) => ({ id: `00000000-0000-5000-8000-00000000000${id}`, caption: "home", text: `${id}@example.net` });
  const state: PopupStateResult = {
    type: "popupStateResult",
    status: "ready",
    kinds: [
      { kind: "email", values: [value("1"), value("2")] },
      { kind: "phone", values: [value("3")] },
    ],
    recent: [],
    muted: false,
  };

  it("replaces the kind the reply covers and keeps the others", () => {
    const reply = { ...state, kinds: [{ kind: "email" as const, values: [value("2"), value("1")] }], muted: true };
    const merged = merge(state, reply);
    expect(merged.kinds.map((entry) => entry.values[0]?.text)).toEqual(["2@example.net", "3@example.net"]);
    expect(merged.muted).toBe(true);
  });

  it("keeps what the sheet shows next to a failure", () => {
    const merged = merge(state, { ...state, status: "failed", reason: "Nope.", kinds: [] });
    expect(merged.kinds).toEqual(state.kinds);
    expect(merged).toMatchObject({ status: "failed", reason: "Nope." });
  });
});
