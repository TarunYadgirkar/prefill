import { describe, expect, it } from "vitest";
import { linkChoices, linkOptions } from "./links";
import type { SuggestedLink } from "./messages";

const github: SuggestedLink = {
  type: "github",
  url: "https://github.com/alexrivera",
  why: "card",
};
const website: SuggestedLink = {
  type: "website",
  url: "https://alexrivera.dev/",
  why: "card",
};
const linkedin: SuggestedLink = {
  type: "linkedin",
  url: "https://www.linkedin.com/in/alexrivera",
  why: "card",
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

describe("linkChoices", () => {
  it("hears about a pick of a single link that wasn't first, never a combined one", () => {
    const picked: string[] = [];
    const choices = linkChoices(["github", "website"], links, false, (value) =>
      picked.push(value),
    );
    choices.forEach((choice) => choice.onPick?.());
    expect(choices.map((choice) => choice.onPick === undefined)).toEqual([
      true,
      false,
      false,
    ]);
    expect(picked).toEqual(["github.com/alexrivera", "alexrivera.dev"]);
  });
});
