import { describe, expect, it } from "vitest";
import { labelled, whyDetail } from "./why";

describe("whyDetail", () => {
  it.each([
    [{ why: "pinned" }, "Used here"],
    [{ why: "used" }, "Used here"],
    [{ why: "card" }, "Work email"],
    [{ why: "learned", site: "greenhouse.io" }, "From greenhouse.io"],
    [{ why: "learned" }, "Work email"],
    [{ why: "guess" }, "Suggested"],
    [{ why: "resume" }, "From your resume"],
  ] as const)("says %j as %s", (offered, detail) => {
    expect(whyDetail(offered, "Work email")).toBe(detail);
  });
});

describe("labelled", () => {
  it.each([
    [undefined, "Email", "Email"],
    ["work", "Email", "Work email"],
    ["home", "Address", "Home address"],
    ["iPhone", "Phone", "iPhone"],
    ["  ", "Phone", "Phone"],
  ] as const)("puts %s before %s", (label, kind, detail) => {
    expect(labelled(label, kind)).toBe(detail);
  });
});
