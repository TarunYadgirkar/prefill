import { describe, expect, it } from "vitest";
import { linkOptions } from "./links";
import type { SuggestedLink } from "./messages";

const github: SuggestedLink = {
  type: "github",
  url: "https://github.com/alexrivera",
};
const website: SuggestedLink = {
  type: "website",
  url: "https://alexrivera.dev/",
};
const linkedin: SuggestedLink = {
  type: "linkedin",
  url: "https://www.linkedin.com/in/alexrivera",
};
const links = [linkedin, website, github];

describe("linkOptions", () => {
  it("offers both links in one option first, then each alone", () => {
    expect(linkOptions(["github", "website"], links, false)).toEqual([
      "github.com/alexrivera - alexrivera.dev",
      "github.com/alexrivera",
      "alexrivera.dev",
    ]);
  });

  it("offers a single kind first and whole addresses in a url field", () => {
    expect(linkOptions(["linkedin"], links, false)).toEqual([
      "www.linkedin.com/in/alexrivera",
    ]);
    expect(linkOptions(["github", "website"], links, true)).toEqual([
      "https://github.com/alexrivera",
      "https://alexrivera.dev/",
    ]);
  });
});
