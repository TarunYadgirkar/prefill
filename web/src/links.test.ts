import { describe, expect, it } from "vitest";
import { linkChoices, linkOptions, listedLinkTypes } from "./links";
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
      "https://github.com/alexrivera - https://alexrivera.dev/",
      "https://github.com/alexrivera",
      "https://alexrivera.dev/",
    ]);
  });

  it("offers a single kind, and no combined option in a url field", () => {
    expect(linkOptions(["linkedin"], links, false)).toEqual([
      "https://www.linkedin.com/in/alexrivera",
    ]);
    expect(linkOptions(["github", "website"], links, true)).toEqual([
      "https://github.com/alexrivera",
      "https://alexrivera.dev/",
    ]);
  });
});

describe("listedLinkTypes", () => {
  it("offers every link on a field that asks only for a website, the website first", () => {
    const x: SuggestedLink = { type: "x", url: "https://x.com/alexrivera", why: "card" };
    const wanted = listedLinkTypes(["website"]);
    expect(linkChoices(wanted, [...links, x], false).map((choice) => [choice.value, choice.detail])).toEqual([
      ["https://alexrivera.dev/", "Website"],
      ["https://github.com/alexrivera", "GitHub"],
      ["https://www.linkedin.com/in/alexrivera", "LinkedIn"],
      ["https://x.com/alexrivera", "X"],
    ]);
  });

  it("keeps a field that names a kind to that kind", () => {
    expect(listedLinkTypes(["github"])).toEqual(["github"]);
    expect(listedLinkTypes(["github", "website"])).toEqual(["github", "website"]);
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
    expect(picked).toEqual(["https://github.com/alexrivera", "https://alexrivera.dev/"]);
  });
});
