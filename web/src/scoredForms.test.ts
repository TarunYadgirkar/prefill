import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { classify, isSensitiveText } from "./classify";
import { fieldText } from "./custom";
import { fieldElements } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { linkOptions } from "./links";
import type { SuggestedLink } from "./messages";
import airtableDormRoomFund from "./fixtures/airtable-dormroomfund.html?raw";
import leverPalantir from "./fixtures/ats-lever-palantir.html?raw";
import workableHuggingFace from "./fixtures/ats-workable-huggingface.html?raw";
import metaDataScience from "./fixtures/meta-datascience.html?raw";
import tallyExpendite from "./fixtures/tally-expendite.html?raw";

// Forms the held-out accuracy score (docs/ACCURACY.md) caught Prefill getting wrong. Each
// left the held-out set for this one, where its bug stays fixed.

const FIXTURES = { airtableDormRoomFund, leverPalantir, workableHuggingFace, metaDataScience, tallyExpendite };
type Fixture = keyof typeof FIXTURES;

function load(fixture: Fixture): void {
  document.body.innerHTML = FIXTURES[fixture];
}

function fieldIn(fixture: Fixture, key: string): FieldElement {
  load(fixture);
  const found = fieldElements(document).find(
    (element) => element.id === key || (element.getAttribute("name") === key && (element as HTMLInputElement).type !== "hidden"),
  );
  if (found === undefined) throw new Error(`no ${key} in ${fixture}`);
  return found;
}

function labeled(fixture: Fixture, label: string): FieldElement {
  load(fixture);
  const found = fieldElements(document).find((element) => fieldText(element).startsWith(label));
  if (found === undefined) throw new Error(`no "${label}" in ${fixture}`);
  return found;
}

function summary(element: FieldElement): string {
  const found = classify(element);
  if (found.kind === "sensitive" || found.kind === "ignored") return found.kind;
  return [found.kind, found.part, found.linkTypes?.join(",")].filter(Boolean).join(" ");
}

const LEVER_CARD = "cards[a69a985a-eae9-4c14-90fb-b5a4b891523e]";

beforeEach(() => {
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("ids that look like card words", () => {
  it("keeps a phone whose id has a digit before cc", () => {
    expect(summary(fieldIn("tallyExpendite", "8019a3b2-28cc-436d-a330-d086b9a50647"))).toBe("phone");
  });

  it("doesn't take a Lever question for a card field because its name says cards[...]", () => {
    expect(isSensitiveText([[fieldText(fieldIn("leverPalantir", `${LEVER_CARD}[field1]`))]])).toBe(false);
    expect(summary(fieldIn("leverPalantir", "cards[037683ac-0e2a-4adf-82d9-49bd682697cc][field0]"))).toBe("ignored");
  });
});

describe("text areas that ask only for a link", () => {
  it("are links; a long text area stays a question", () => {
    expect(summary(fieldIn("workableHuggingFace", "CA_47143"))).toBe("link github");
    expect(summary(fieldIn("workableHuggingFace", "CA_47383"))).toBe("link linkedin");
    expect(summary(fieldIn("workableHuggingFace", "summary"))).toBe("ignored");
    expect(summary(fieldIn("workableHuggingFace", "cover_letter"))).toBe("ignored");
  });
});

describe("questions that aren't the person's own", () => {
  it("leaves a company's website alone", () => {
    expect(summary(fieldIn("airtableDormRoomFund", "e1870bb16c25fe34753e18d54730656d"))).toBe("ignored");
  });

  it("doesn't take a name pronunciation question for the name", () => {
    expect(summary(fieldIn("leverPalantir", `${LEVER_CARD}[field2]`))).toBe("ignored");
  });
});

describe("one Website box with examples", () => {
  const links: SuggestedLink[] = [
    { type: "linkedin", url: "https://www.linkedin.com/in/alexrivera", why: "card" },
    { type: "github", url: "https://github.com/alexrivera", why: "card" },
    { type: "website", url: "https://alexrivera.dev", why: "card" },
  ];

  it("offers the website first and the examples alone, never joined", () => {
    const field = classify(labeled("metaDataScience", "Website (Examples"));
    if (field.kind !== "link") throw new Error(`not a link: ${field.kind}`);
    expect(linkOptions(field.linkTypes ?? [], links, false)).toEqual([
      "alexrivera.dev",
      "www.linkedin.com/in/alexrivera",
      "github.com/alexrivera",
    ]);
  });
});
