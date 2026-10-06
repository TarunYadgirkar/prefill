import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { pickOption } from "./choices";
import { declineOption } from "./demographics";
import { choicesFor, fillableCount, fillForm, findSlots } from "./fill";
import { fieldsLeft, nextLeft } from "./fillLeft";
import type { ExtensionRequest } from "./messages";

const options = (...texts: string[]) => texts.map((text) => ({ text, value: text }));

// The option texts are the ones Greenhouse and the OFCCP's forms use.
const APPLICATION = `<form id="app">
  <label for="first_name">First Name *</label><input id="first_name" name="first_name" type="text">
  <label for="last_name">Last Name *</label><input id="last_name" name="last_name" type="text">
  <label for="email">Email *</label><input id="email" name="email" type="text">
  <label for="phone">Phone</label><input id="phone" name="phone" type="text" value="+1 510 555 0100">
  <label for="li">LinkedIn Profile</label><input id="li" type="text">
  <label for="school">School</label><input id="school" type="text">
  <label for="state">State</label>
  <select id="state"><option value="">Select...</option><option value="AZ">Arizona</option><option value="CA">California</option></select>
  <fieldset><legend>Are you legally authorized to work in the United States?</legend>
    <label><input type="radio" name="auth" value="1"> Yes</label>
    <label><input type="radio" name="auth" value="0"> No</label>
  </fieldset>
  <label for="gender">Gender</label>
  <select id="gender"><option value="">Please select</option><option>Male</option><option>Female</option><option>Decline To Self Identify</option></select>
  <label for="hispanic">Are you Hispanic/Latino?</label>
  <select id="hispanic"><option value="">Please select</option><option>Yes</option><option>No</option></select>
  <label for="veteran">Veteran Status</label>
  <select id="veteran"><option value="">Please select</option><option>I am not a protected veteran</option>
    <option>I identify as one or more of the classifications of protected veteran</option><option>I don't wish to answer</option></select>
  <label for="pronouns_text">Gender identity (optional)</label><input id="pronouns_text" type="text">
  <label for="pw">Password</label><input id="pw" type="password">
  <button type="submit">Submit Application</button>
</form>`;

const card = (value: string) => ({ value, why: "card" });

function reply(request: ExtensionRequest): unknown {
  switch (request.type) {
    case "contactSuggestions":
      return {
        type: "contactSuggestionsResult",
        emails: [card("tarun@example.com"), card("tarun@berkeley.edu")],
        phones: [card("+1 510 555 0134")],
        addresses: [
          {
            address: { street: "2400 Durant Ave", city: "Berkeley", state: "CA", postalCode: "94704", country: "United States" },
            why: "card",
          },
        ],
        name: { given: "Tarun", family: "Yadgirkar" },
      };
    case "linkSuggestions":
      return { type: "linkSuggestionsResult", links: [{ type: "linkedin", url: "https://linkedin.com/in/tarun", why: "card" }] };
    case "customSuggestions":
      return {
        type: "customSuggestionsResult",
        fields: request.fields.map(({ text }) => ({
          values: /school/iu.test(text)
            ? [card("University of California, Berkeley")]
            : /authorized/iu.test(text)
              ? [card("Yes")]
              : [],
        })),
      };
    default:
      return { type: "error", reason: "unexpected" };
  }
}

const value = (id: string): string => (document.getElementById(id) as HTMLInputElement | HTMLSelectElement).value;
const selected = (id: string): string =>
  (document.getElementById(id) as HTMLSelectElement).selectedOptions[0]?.text ?? "";

beforeEach(() => {
  document.body.innerHTML = APPLICATION;
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("matching a saved answer to a page's options", () => {
  it.each([
    [["Select...", "Arizona", "California"], "CA", 2],
    [["--", "AZ", "CA"], "California", 2],
    [["Canada", "United States of America"], "United States", 1],
    [["Yes, I am authorized to work in the US", "No"], "Yes", 0],
    [["Bachelor's Degree", "Master's Degree"], "Bachelor's", 0],
    [["Arizona", "Alaska"], "California", -1],
    [["University of Michigan", "Stanford University"], "University of California, Berkeley", -1],
    [["Bachelor of Arts", "Master of Science"], "Bachelor of Science", -1],
    [["-- Select --", "Yes", "No"], "Select", -1],
  ])("%j with %s picks %i", (texts, answer, index) => {
    expect(pickOption(options(...texts), answer)).toBe(index);
  });
});

describe("demographic questions", () => {
  it.each([
    [["Male", "Female", "Decline To Self Identify"], 2],
    [["I am not a protected veteran", "I identify as a protected veteran", "I don't wish to answer"], 2],
    [["Yes, I have a disability", "No, I do not have a disability", "I do not want to answer"], 2],
    [["Yes", "No"], 1],
    [["Male", "Female"], -1],
  ])("%j declines with %i", (texts, index) => {
    expect(declineOption(options(...texts))).toBe(index);
  });
});

describe("one-tap fill", () => {
  it("fills every empty field it can answer, declines demographics and leaves the rest", async () => {
    const send = vi.fn((request: ExtensionRequest) => Promise.resolve(reply(request)));
    const result = await fillForm(document, { host: () => "boards.greenhouse.io", send });
    expect(value("first_name")).toBe("Tarun");
    expect(value("last_name")).toBe("Yadgirkar");
    expect(value("email")).toBe("tarun@example.com");
    expect(value("phone")).toBe("+1 510 555 0100");
    expect(value("li")).toBe("linkedin.com/in/tarun");
    expect(value("school")).toBe("University of California, Berkeley");
    expect(value("state")).toBe("CA");
    expect((document.querySelector("input[name=auth][value='1']") as HTMLInputElement).checked).toBe(true);
    expect(selected("gender")).toBe("Decline To Self Identify");
    expect(selected("hispanic")).toBe("No");
    expect(selected("veteran")).toBe("I don't wish to answer");
    expect(value("pronouns_text")).toBe("");
    expect(value("pw")).toBe("");
    expect(result.filled).toBe(10);
    expect(choicesFor(document.getElementById("email") as HTMLInputElement)?.map((choice) => choice.value)).toEqual([
      "tarun@example.com",
      "tarun@berkeley.edu",
    ]);
  });

  it("puts everything back on undo, keeping what the person typed", async () => {
    const send = vi.fn((request: ExtensionRequest) => Promise.resolve(reply(request)));
    const result = await fillForm(document, { host: () => "boards.greenhouse.io", send });
    result.undo();
    expect(value("email")).toBe("");
    expect(value("phone")).toBe("+1 510 555 0100");
    expect(selected("gender")).toBe("Please select");
    expect(document.querySelector<HTMLInputElement>("input[name=auth]:checked")).toBeNull();
  });

  it("counts the fields it has an answer for, and leaves the rest in page order", async () => {
    const form = document.getElementById("app");
    form?.insertAdjacentHTML("afterbegin", '<label for="why">Why do you want to work here?</label><input id="why" type="text">');
    form?.insertAdjacentHTML("beforeend", '<label for="start">Earliest start date</label><input id="start" type="text">');
    const send = vi.fn((request: ExtensionRequest) => Promise.resolve(reply(request)));
    const options = { host: () => "boards.greenhouse.io", send };
    expect(findSlots(document)).toHaveLength(12);
    expect(await fillableCount(document, options)).toBe(10);
    await fillForm(document, options);
    const left = fieldsLeft(document);
    expect(left.map((field) => field.id)).toEqual(["why", "start"]);
    expect(nextLeft(left, left[0])?.id).toBe("start");
    expect(nextLeft(left, left[1])?.id).toBe("why");
  });

  it("tells the app about a pick from a filled field's list, as any list does", async () => {
    const send = vi.fn((request: ExtensionRequest) =>
      Promise.resolve(request.type === "picked" ? { type: "pickedResult", remembered: true } : reply(request)),
    );
    await fillForm(document, { host: () => "boards.greenhouse.io", send });
    const [first, second] = choicesFor(document.getElementById("email") as HTMLInputElement) ?? [];
    first?.onPick?.();
    second?.onPick?.();
    expect(send).toHaveBeenLastCalledWith({
      type: "picked",
      host: "boards.greenhouse.io",
      kind: "email",
      value: "tarun@berkeley.edu",
    });
    expect(send.mock.calls.filter(([request]) => request.type === "picked")).toHaveLength(1);
  });

  it("stays off sign-in forms", () => {
    document.body.innerHTML =
      '<form><input type="email" name="email"><input type="password" autocomplete="current-password"><button>Sign in</button></form>';
    expect(findSlots(document)).toEqual([]);
  });
});
