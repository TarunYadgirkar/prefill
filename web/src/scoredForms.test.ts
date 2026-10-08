import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { pickOption } from "./choices";
import { classify, isSensitiveText } from "./classify";
import { fieldText } from "./custom";
import { fieldElements, labelText } from "./dom";
import { declineOption, isDecline, isDemographic } from "./demographics";
import { fillForm, takesSavedAnswer } from "./fill";
import { fitPhones } from "./fillFit";
import type { FieldElement } from "./fieldTypes";
import { customValues, reply, type Person } from "./heldoutHost";
import { scoreForm, type Expectation } from "./heldoutScore";
import greenhouseDatadog from "./fixtures/ats-greenhouse-datadog.html?raw";
import greenhouseRoblox from "./fixtures/ats-greenhouse-roblox.html?raw";
import ashbyOpenAi from "./fixtures/ats-ashby-openai.html?raw";
import tallySfHacks from "./fixtures/tally-sfhacks.html?raw";
import greenhouseStripe from "./fixtures/ats-greenhouse-stripe.html?raw";
import jotformLambOfGodVbs from "./fixtures/jotform-lambofgodvbs.html?raw";
import tallyUvaWics from "./fixtures/tally-uvawics.html?raw";
import { linkOptions } from "./links";
import type { ExtensionRequest, SuggestedLink } from "./messages";
import airtableDormRoomFund from "./fixtures/airtable-dormroomfund.html?raw";
import airtableIbmStartups from "./fixtures/airtable-ibmstartups.html?raw";
import greenhouseFigma from "./fixtures/ats-greenhouse-figma.html?raw";
import leverPalantir from "./fixtures/ats-lever-palantir.html?raw";
import leverShieldAi from "./fixtures/ats-lever-shieldai.html?raw";
import leverVeeva from "./fixtures/ats-lever-veeva.html?raw";
import leverZoox from "./fixtures/ats-lever-zoox.html?raw";
import workableBlueground from "./fixtures/ats-workable-blueground.html?raw";
import workableHuggingFace from "./fixtures/ats-workable-huggingface.html?raw";
import alex from "./fixtures/heldout/alex.json";
import jotformAdaHack from "./fixtures/jotform-adahack.html?raw";
import jotformMyHack from "./fixtures/jotform-myhack.html?raw";
import jotformPocoRunClub from "./fixtures/jotform-pocorunclub.html?raw";
import metaDataScience from "./fixtures/meta-datascience.html?raw";
import metaDfx from "./fixtures/meta-dfx.html?raw";
import tallyExpendite from "./fixtures/tally-expendite.html?raw";
import tallyHackHub from "./fixtures/tally-hackhub.html?raw";

// Forms the held-out accuracy score (docs/ACCURACY.md) caught Prefill getting wrong. Each
// left the held-out set for this one, where its bug stays fixed.

const FIXTURES = {
  greenhouseStripe,
  jotformLambOfGodVbs,
  tallyUvaWics,
  airtableDormRoomFund,
  airtableIbmStartups,
  greenhouseFigma,
  jotformAdaHack,
  jotformMyHack,
  jotformPocoRunClub,
  leverPalantir,
  leverShieldAi,
  leverVeeva,
  leverZoox,
  metaDataScience,
  metaDfx,
  tallyExpendite,
  tallyHackHub,
  workableBlueground,
  workableHuggingFace,
};
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

describe("a saved date against year and month lists", () => {
  it("picks the year or the month when only one option fits", () => {
    const years = ["Select...", "2026", "2027", "2028", "Other"].map((text) => ({ text, value: text === "Select..." ? "" : text }));
    const months = ["Select...", "April", "May", "June"].map((text) => ({ text, value: text === "Select..." ? "" : text }));
    expect(pickOption(years, "May 2027")).toBe(2);
    expect(pickOption(months, "May 2027")).toBe(2);
    expect(pickOption([{ text: "Spring 2027", value: "a" }, { text: "Fall 2027", value: "b" }], "May 2027")).toBe(-1);
    expect(pickOption([{ text: "2027", value: "a" }, { text: "May", value: "b" }], "May 2027")).toBe(-1);
  });

  it("fills Lever's graduation year and month from \"May 2027\"", async () => {
    load("leverPalantir");
    const send = (request: ExtensionRequest): Promise<unknown> => {
      if (request.type !== "customSuggestions") return Promise.resolve({ type: "error", reason: "none" });
      return Promise.resolve({
        type: "customSuggestionsResult",
        fields: request.fields.map(({ text }) => ({ values: /graduation/iu.test(text) ? [{ value: "May 2027", why: "card" }] : [] })),
      });
    };
    await fillForm(document, { host: () => "jobs.lever.co", send });
    const chosen = (name: string): string =>
      document.querySelector<HTMLSelectElement>(`select[name="${name}"]`)?.selectedOptions[0]?.text ?? "";
    expect(chosen("cards[026d7ce7-7ca4-44ed-9db6-1c7857707f0e][field0]")).toBe("2027");
    expect(chosen("cards[c58728ca-3a96-40b6-9622-d70019b01176][field0]")).toBe("May");
  });
});

// Fill form on a whole fixture, answered by the held-out score's stand-in app as Alex Rivera.
async function fillAsAlex(fixture: Fixture): Promise<void> {
  load(fixture);
  const send = (request: ExtensionRequest): Promise<unknown> => Promise.resolve(reply(alex as Person, request));
  await fillForm(document, { host: () => "example.com", send });
}

const valueOf = (id: string): string => document.querySelector<HTMLInputElement>(`[id="${id}"]`)?.value ?? "";
const checkedIn = (name: string): string =>
  document.querySelector<HTMLInputElement>(`input[name="${name}"]:checked`)?.value ?? "";

describe("questions that open with \"If\"", () => {
  it("stand alone unless they follow an earlier answer", () => {
    expect(takesSavedAnswer(fieldText(fieldIn("greenhouseFigma", "question_19835366004")))).toBe(true);
    expect(takesSavedAnswer(fieldText(fieldIn("leverZoox", "cards[18631c8a-d2a4-41d9-ba8a-8fccf4193494][field5]")))).toBe(false);
    expect(takesSavedAnswer("If other, please specify")).toBe(false);
    expect(takesSavedAnswer("If you answered yes, explain")).toBe(false);
  });
});

describe("Jotform's phone box with maxlength 10", () => {
  it("gets the national digits", async () => {
    await fillAsAlex("jotformMyHack");
    expect(valueOf("input_16")).toBe("5105550134");
  });
});

describe("Meta's radio buttons without a name", () => {
  it("are grouped by their radiogroup and declined", async () => {
    await fillAsAlex("metaDfx");
    const groups = [...document.querySelectorAll("[role=radiogroup]")].filter((group) => group.querySelector("input") !== null);
    expect(groups.length).toBe(3);
    for (const group of groups) {
      const checked = group.querySelector<HTMLInputElement>("input:checked");
      expect(checked === null ? -1 : declineOption([{ text: checked.closest("label")?.textContent ?? "", value: checked.value }])).toBe(0);
    }
  });
});

describe("Workable's application", () => {
  it("fills the LinkedIn text area and the one address box, and leaves the hidden helpers", async () => {
    await fillAsAlex("workableBlueground");
    expect(valueOf("QA_12102922")).toBe("www.linkedin.com/in/alex-rivera-example");
    expect(valueOf("address")).toBe("2400 Durant Ave, Berkeley, CA 94704");
    expect(["city", "postcode", "country"].map(valueOf)).toEqual(["", "", ""]);
  });
});

describe("words a question gives only as examples", () => {
  it("don't match a saved answer: \"(e.g., grants, sponsorships)\" isn't a sponsorship question", async () => {
    await fillAsAlex("leverZoox");
    expect(checkedIn("cards[18631c8a-d2a4-41d9-ba8a-8fccf4193494][field6]")).toBe("");
    expect(document.querySelector<HTMLInputElement>('[name="cards[18631c8a-d2a4-41d9-ba8a-8fccf4193494][field2]"]')?.value).toBe("No");
  });
});

describe("names that aren't the person's", () => {
  it("leaves a startup's name alone", () => {
    expect(summary(fieldIn("airtableIbmStartups", "18b55139e215383643e4cb6730abe5e7"))).toBe("ignored");
  });
});

describe("Tally's application", () => {
  it("puts the school only where it's asked for, and fills the phone box that is a combobox", async () => {
    await fillAsAlex("tallyHackHub");
    expect(valueOf("32a51279-3f96-4761-9437-202edaac6f4a")).toBe("University of California, Berkeley");
    expect(valueOf("5ec403ec-b904-487f-b3e4-c1004021762b")).toBe("");
    expect(valueOf("8a04327a-cff6-4e83-8b68-ad54b2a3d259")).toBe("+1 (510) 555-0134");
  });
});

describe("Lever's race radios inside the question's own label", () => {
  it("are declined, never answered", async () => {
    await fillAsAlex("leverShieldAi");
    expect(checkedIn("eeo[race]")).toBe("Decline to self-identify");
  });
});

describe("every fixture's demographic questions", () => {
  // Vitest runs from web/.
  const dir = join(process.cwd(), "src/fixtures");
  const pages = readdirSync(dir).filter((file) => file.endsWith(".html"));
  // Searchable dropdowns without a list wait for one before giving up.
  const SLOW_MS = 90_000;

  function demographicAnswers(): string[] {
    const lists = [...document.querySelectorAll("select")].filter((select) => isDemographic(fieldText(select)));
    const chosen = lists.flatMap((select) => (select.selectedIndex > 0 ? [select.selectedOptions[0]?.text ?? ""] : []));
    const radios = [...document.querySelectorAll<HTMLInputElement>("input[type=radio]:checked")];
    const groups = new Set(radios.map((radio) => radio.closest("[role=radiogroup], fieldset, ul") ?? radio));
    const asked = radios.filter((radio) => isDemographic(groupText(radio, groups)));
    return [...chosen, ...asked.map((radio) => labelText(radio))];
  }

  const groupText = (radio: HTMLInputElement, groups: ReadonlySet<Element>): string =>
    [...groups].find((group) => group.contains(radio))?.parentElement?.textContent.slice(0, 200) ?? "";

  it.each(pages)("%s gets only declines or No", async (page) => {
    document.body.innerHTML = readFileSync(join(dir, page), "utf8");
    const send = (request: ExtensionRequest): Promise<unknown> => Promise.resolve(reply(alex as Person, request));
    await fillForm(document, { host: () => "example.com", send });
    expect(demographicAnswers().filter((text) => !isDecline(text))).toEqual([]);
  }, SLOW_MS);
});

describe("sponsorship and work authorization", () => {
  it("answers a sponsorship question with the sponsorship answer, even when it says \"work authorization\"", async () => {
    await fillAsAlex("leverVeeva");
    expect(checkedIn("cards[88ad61a3-4d5a-4a0b-bf60-ad9f98709476][field0]")).toBe("No");
  });

  it("keeps each answer to its own question, and leaves a question that asks both", () => {
    const labels = (text: string): string[] =>
      customValues(alex as Person, text).map(({ label }) => label);
    expect(labels("Will you now or in the future require sponsorship for work authorization?")).toEqual(["Sponsorship"]);
    expect(labels("Are you legally authorized to work in the United States?")).toEqual(["Work authorization"]);
    expect(labels("Are you authorized to work in the US and will you not require sponsorship?")).toEqual([]);
  });
});

describe("a masked phone box", () => {
  it("gets the national number, or nothing when the number has another country code", async () => {
    await fillAsAlex("jotformAdaHack");
    expect(valueOf("input_8_full")).toBe("(510) 555-0134");
    const box = document.getElementById("input_8_full") as HTMLInputElement;
    expect(fitPhones(box, [{ value: "+44 20 7946 0958", detail: "" }])).toEqual([]);
  });
});

describe("fields about someone else", () => {
  it("leave an emergency contact's name and phone alone, and give the participant's name", async () => {
    await fillAsAlex("jotformPocoRunClub");
    expect(valueOf("input_7")).toBe("");
    expect(valueOf("input_8")).toBe("");
    expect(valueOf("input_2")).toBe("Alex Rivera");
    expect(valueOf("input_20")).toBe("Alex Rivera");
  });
});

describe("Greenhouse's searchable education and location lists", () => {
  const DEGREES = ["High School", "Associate's Degree", "Bachelor's Degree", "Master's Degree", "Doctor of Philosophy (Ph.D.)", "Other"];
  const PLACES = [
    "Berkeley, California, United States",
    "Berkeley Heights, New Jersey, United States",
    "Berkeley, Missouri, United States",
    "San Francisco, California, United States",
  ];
  const fields: Expectation[] = [
    { field: { id: "degree--0" }, want: "fill", accept: ["Bachelor's Degree"], options: DEGREES },
    { field: { id: "candidate-location" }, want: "fill", accept: ["Berkeley, California, United States"], options: PLACES },
  ];

  it("pick a bachelor's degree for a Bachelor of Science, and the city in Alex's state", async () => {
    const results = await scoreForm(greenhouseRoblox, { source: "https://job-boards.greenhouse.io/roblox", fields }, alex as Person);
    expect(results.slice(0, 2).map(({ got }) => got)).toEqual(["Bachelor's Degree", "Berkeley, California, United States"]);
  }, 30_000);

  it("pick the month from a saved \"May 2027\" when typing it shows nothing", async () => {
    const months = ["January", "February", "March", "April", "May", "June"];
    const month: Expectation[] = [{ field: { id: "end-month--0" }, want: "fill", accept: ["May"], options: months }];
    const send = { source: "https://job-boards.greenhouse.io/datadog", fields: month };
    const results = await scoreForm(greenhouseDatadog, send, { ...(alex as Person), custom: [{ label: "End date month", value: "May 2027" }] });
    expect(results[0]?.got).toBe("May");
  }, 30_000);
});

describe("lists outside React-Select", () => {
  const PLACES = ["Berkeley, California, United States", "Berkeley Heights, New Jersey, United States", "San Francisco, California, United States"];

  it("fill Tally's school box and its country buttons", async () => {
    const schools = ["San Francisco State University", "University of California, Berkeley", "Stanford University", "Other"];
    const fields: Expectation[] = [
      { field: { id: "dacf19c1-31c1-42ee-90dd-fa93349f23c7" }, want: "fill", accept: ["University of California, Berkeley"], options: schools },
      { field: { name: "multiple_choice_b6d20b7a-1840-43b2-aa85-9c206dc14f5f" }, want: "fill", accept: ["United States"] },
    ];
    const results = await scoreForm(tallySfHacks, { source: "https://tally.so/r/RG2rP4", fields }, alex as Person);
    expect(results.slice(0, 2).map(({ got }) => got.trim())).toEqual(["University of California, Berkeley", "United States"]);
  }, 30_000);

  it("fill Ashby's \"Where are you currently located?\" box", async () => {
    const fields: Expectation[] = [{ field: { label: "Where are you currently located?" }, want: "fill", accept: [PLACES[0] ?? ""], options: PLACES }];
    const results = await scoreForm(ashbyOpenAi, { source: "https://jobs.ashbyhq.com/openai", fields }, alex as Person);
    expect(results[0]?.got).toBe(PLACES[0]);
  }, 30_000);
});

describe("signatures", () => {
  it("are never filled, even a typed signature tagged as a given and family name", async () => {
    await fillAsAlex("jotformLambOfGodVbs");
    expect(["first_121", "last_121"].map(valueOf)).toEqual(["", ""]);
    expect(summary(fieldIn("jotformLambOfGodVbs", "first_121"))).toBe("sensitive");
  });
});

describe("Stripe's application", () => {
  it("leaves the unlisted-school box, puts city and state in one box, and gives the preferred name", async () => {
    await fillAsAlex("greenhouseStripe");
    expect(valueOf("question_68843617")).toBe("");
    expect(valueOf("question_69458357")).toBe("Berkeley, CA");
    expect(valueOf("question_68581549")).toBe("Alex");
  }, 60_000);
});

describe("Tally's ethnicity checkboxes", () => {
  it("are declined with the box that declines", async () => {
    await fillAsAlex("tallyUvaWics");
    const checked = [...document.querySelectorAll<HTMLInputElement>("input[type=checkbox]:checked")].map((box) => labelText(box));
    expect(checked).toEqual(["Prefer Not to Answer"]);
  }, 60_000);
});
