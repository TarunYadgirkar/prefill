import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { classify } from "./classify";
import { isCombobox, isComboboxEmpty } from "./combobox";
import { fieldText } from "./custom";
import { fieldElements } from "./dom";
import { fillForm, findSlots } from "./fill";
import type { ExtensionRequest } from "./messages";
import type { FieldElement } from "./fieldTypes";
import ashbyDecagon from "./fixtures/ats-ashby-decagon.html?raw";
import greenhouseBraeburn from "./fixtures/ats-greenhouse-braeburn.html?raw";
import greenhouseGarner from "./fixtures/ats-greenhouse-garner.html?raw";
import leverKepler from "./fixtures/ats-lever-kepler.html?raw";
import leverRover from "./fixtures/ats-lever-rover.html?raw";
import smartRecruitersBosch from "./fixtures/ats-smartrecruiters-bosch.html?raw";
import workableMindex from "./fixtures/ats-workable-mindex.html?raw";

// Real application forms from five applicant tracking systems; each fixture's header
// comment names the posting it was saved from. Workday renders its form in the browser
// and has no saved copy here.

const FIXTURES = {
  greenhouseGarner,
  greenhouseBraeburn,
  leverKepler,
  leverRover,
  ashbyDecagon,
  workableMindex,
  smartRecruitersBosch,
};
type Fixture = keyof typeof FIXTURES;
// The fixture, the question as the page words it, the field's id or name, and what it is.
type Case = readonly [Fixture, string, string, string];

// innerHTML ignores declarative shadow roots, so attach them the way a browser's parser does.
function attachShadows(root: ParentNode): void {
  for (const template of [...root.querySelectorAll<HTMLTemplateElement>("template[shadowrootmode]")]) {
    const host = template.parentElement;
    if (host === null || host.shadowRoot !== null) continue;
    const shadow = host.attachShadow({ mode: "open" });
    shadow.append(template.content);
    template.remove();
    attachShadows(shadow);
  }
}

function fieldIn(fixture: Fixture, key: string): FieldElement {
  document.body.innerHTML = FIXTURES[fixture];
  attachShadows(document.body);
  const found = fieldElements(document).find((element) => element.id === key || element.getAttribute("name") === key);
  if (found === undefined) throw new Error(`no ${key} in ${fixture}`);
  return found;
}

function summary(element: FieldElement): string {
  const found = classify(element);
  if (found.kind === "sensitive" || found.kind === "ignored") return found.kind;
  return [found.kind, found.part, found.linkTypes?.join(",")].filter(Boolean).join(" ");
}

const RIGHT: readonly Case[] = [
  ["greenhouseGarner", "First Name", "first_name", "name given"],
  ["greenhouseGarner", "Last Name", "last_name", "name family"],
  ["greenhouseGarner", "Email", "email", "email"],
  ["greenhouseGarner", "Phone", "phone", "phone"],
  ["greenhouseGarner", "Location (City)", "candidate-location", "address city"],
  ["greenhouseGarner", "LinkedIn Profile", "question_19964586004", "link linkedin"],
  ["greenhouseGarner", "School", "school--0", "ignored"],
  ["greenhouseGarner", "Degree", "degree--0", "ignored"],
  ["greenhouseGarner", "Are you legally authorized to work in the United States", "question_19964589004", "ignored"],
  ["greenhouseGarner", "Will you now or in the future require sponsorship", "question_19964590004", "ignored"],
  ["greenhouseGarner", "Which state do you currently reside in?", "question_19964592004", "address state"],
  ["greenhouseGarner", "How would you describe your gender identity?", "4005041004", "ignored"],
  ["greenhouseGarner", "How would you describe your racial/ethnic background?", "4005039004", "ignored"],
  ["greenhouseGarner", "Do you have a disability or chronic condition", "4005035004", "ignored"],
  ["greenhouseGarner", "Are you a veteran or active member", "4005033004", "ignored"],
  ["greenhouseBraeburn", "Discipline", "discipline--0", "ignored"],
  ["greenhouseBraeburn", "How did you hear about this job?", "question_37142027002", "ignored"],
  ["greenhouseBraeburn", "Are you presently authorized to work", "question_37142040002", "ignored"],
  ["greenhouseBraeburn", "Will you now or in the future require Braeburn to sponsor you", "question_37142041002", "ignored"],
  ["greenhouseBraeburn", "LinkedIn Profile", "question_37142051002", "link linkedin"],
  ["greenhouseBraeburn", "Gender", "gender", "ignored"],
  ["greenhouseBraeburn", "Are you Hispanic/Latino?", "hispanic_ethnicity", "ignored"],
  ["greenhouseBraeburn", "Veteran Status", "veteran_status", "ignored"],
  ["greenhouseBraeburn", "Disability Status", "disability_status", "ignored"],
  ["leverKepler", "Full name", "name", "name full"],
  ["leverKepler", "Email", "email", "email"],
  ["leverKepler", "Phone", "phone", "phone"],
  ["leverKepler", "Current company", "org", "ignored"],
  ["leverKepler", "Portfolio URL", "urls[Portfolio]", "link website"],
  ["leverKepler", "Website/Blog URL", "urls[Website/Blog]", "link website"],
  ["leverKepler", "What Post-Secondary institution do you attend?", "university-picker-d8b5ec93-e4ee-4c30-9346-e8eaa44c5ff5-0", "ignored"],
  ["leverRover", "How should we refer to you (nickname and/or pronouns)?", "cards[fb5c103c-4111-4530-94b9-07965c4a027e][field1]", "ignored"],
  ["leverRover", "Gender", "eeo[gender]", "ignored"],
  ["leverRover", "Race", "eeo[race]", "ignored"],
  ["leverRover", "Veteran status", "eeo[veteran]", "ignored"],
  ["ashbyDecagon", "Name", "_systemfield_name", "name full"],
  ["ashbyDecagon", "Email", "_systemfield_email", "email"],
  ["ashbyDecagon", "Phone Number", "772658c4-56d5-4642-aaa6-75fb558f07f1", "phone"],
  ["ashbyDecagon", "LinkedIn", "1a070864-d529-4be9-ba9d-718c91412157", "link linkedin"],
  ["ashbyDecagon", "Where did you go for college?", "f9fdfcb8-acbc-4473-a8f5-b323ebad86c8", "ignored"],
  ["ashbyDecagon", "How did you hear about Decagon?", "6ce41167-9534-4fd3-9f85-227edad90d45", "ignored"],
  ["workableMindex", "First name", "firstname", "name given"],
  ["workableMindex", "Last name", "lastname", "name family"],
  ["workableMindex", "Email", "email", "email"],
  ["workableMindex", "Phone", "phone", "phone"],
  ["workableMindex", "Address", "address", "address street"],
  ["workableMindex", "City", "city", "address city"],
  ["workableMindex", "Postcode", "postcode", "address postalCode"],
  ["workableMindex", "Country", "country", "address country"],
  ["workableMindex", "Headline", "headline", "ignored"],
  ["workableMindex", "Where did you see this job posting?", "QA_12457576", "ignored"],
  ["smartRecruitersBosch", "First name", "first-name-input", "name given"],
  ["smartRecruitersBosch", "Last name", "last-name-input", "name family"],
  ["smartRecruitersBosch", "Email", "email-input", "email"],
  ["smartRecruitersBosch", "Confirm your email", "confirm-email-input", "email"],
  ["smartRecruitersBosch", "LinkedIn", "linkedin-input", "link linkedin"],
  ["smartRecruitersBosch", "Website", "website-input", "link website"],
  // Fixed after these fixtures showed them wrong.
  ["greenhouseGarner", "When is your expected graduation date?", "question_19964585004", "ignored"],
  ["greenhouseBraeburn", "Current Address (City – State – ZIP Code)", "question_37142024002", "address street"],
  ["greenhouseBraeburn", "Has your professional license … ever been revoked or suspended", "question_37142046002", "ignored"],
  ["greenhouseBraeburn", "Have you been excluded, debarred, suspended … from … programs", "question_37142047002", "ignored"],
  ["leverKepler", "Current location", "location-input", "address city"],
  ["leverKepler", "LinkedIn URL", "urls[LinkedIn]", "link linkedin"],
  ["leverKepler", "GitHub URL", "urls[GitHub]", "link github"],
  ["leverKepler", "Twitter URL", "urls[Twitter]", "link x"],
  ["leverKepler", "Other website", "urls[Other]", "link other"],
];

// A field the classifier gets wrong goes here as an it.fails case with what it returns
// today, until the rules are fixed and it moves up to RIGHT.

describe("classify on real applicant tracking system forms", () => {
  it.each(RIGHT)("%s: %s (%s) is %s", (fixture, _label, key, expected) => {
    expect(summary(fieldIn(fixture, key))).toBe(expected);
  });
});

// Lever writes each question in a div beside its field, with no <label>.
describe("questions Lever doesn't label", () => {
  beforeEach(() => {
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("reads the question beside a text box and a select", () => {
    expect(fieldText(fieldIn("leverRover", "cards[fb5c103c-4111-4530-94b9-07965c4a027e][field1]"))).toMatch(
      /^How should we refer to you/u,
    );
    expect(fieldText(fieldIn("leverKepler", "cards[d8b5ec93-e4ee-4c30-9346-e8eaa44c5ff5][field0]"))).toMatch(
      /^What Post-Secondary institution do you attend/u,
    );
  });

  it("answers a yes/no question from a saved answer", async () => {
    fieldIn("leverKepler", "email");
    const asked: string[] = [];
    const send = (request: ExtensionRequest): Promise<unknown> => {
      if (request.type !== "customSuggestions") return Promise.resolve({ type: "error", reason: "none" });
      asked.push(...request.fields.map((field) => field.text));
      return Promise.resolve({
        type: "customSuggestionsResult",
        fields: request.fields.map(({ text }) => ({ values: /returning to your studies/u.test(text) ? [{ value: "Yes", why: "card" }] : [] })),
      });
    };
    await fillForm(document, { host: () => "jobs.lever.co", send });
    expect(asked.some((text) => text.startsWith("Will you be returning to your studies after the internship?"))).toBe(true);
    const checked = document.querySelector<HTMLInputElement>('input[name$="[field1]"]:checked');
    expect(checked?.value).toBe("Yes");
  });
});

describe("Greenhouse's searchable dropdowns", () => {
  beforeEach(() => {
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("finds each empty React-Select box and what it asks", () => {
    const auth = fieldIn("greenhouseGarner", "question_19964589004") as HTMLInputElement;
    expect(isCombobox(auth)).toBe(true);
    expect(isComboboxEmpty(auth)).toBe(true);
    const asks = findSlots(document).flatMap((slot) => (slot.control === "combobox" ? [slot.want] : []));
    expect(asks).toContainEqual({ from: "decline" });
    expect(asks).toContainEqual(expect.objectContaining({ from: "custom", text: expect.stringMatching(/^School/u) as string }));
  });

  it("leaves an \"If 'Other' selected\" follow-up alone", () => {
    fieldIn("greenhouseGarner", "email");
    const texts = findSlots(document).flatMap((slot) => (slot.want.from === "custom" ? [slot.want.text] : []));
    expect(texts.some((text) => text.startsWith("If"))).toBe(false);
  });
});
