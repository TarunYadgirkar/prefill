import { afterEach, describe, expect, it, vi } from "vitest";
import type { Choice, TextField } from "./dropdown";
import type { ContactSuggestionsRequest } from "./messages";
import {
  installSuggestions,
  suggestionOptions,
  type Suggestions,
} from "./suggestions";

const values: Suggestions = {
  emails: [
    "alex@work.example.org",
    "alex.rivera@example.com",
    "alex@work.example.org",
  ],
  phones: ["+1 510 555 0100"],
  addresses: [
    {
      street: "2400 Durant Ave\nApt 5",
      city: "Berkeley",
      state: "CA",
      postalCode: "94704",
      country: "United States",
    },
    {
      street: "1 Main St",
      city: "Berkeley",
      state: "CA",
      postalCode: "94710",
      country: "United States",
    },
  ],
  name: { given: "Alex", family: "Rivera" },
};

describe("suggestionOptions", () => {
  it("offers each value once, in the app's order", () => {
    expect(suggestionOptions({ kind: "email", group: "" }, values)).toEqual([
      "alex@work.example.org",
      "alex.rivera@example.com",
    ]);
  });

  it("offers the part of each address and name a field asks for", () => {
    expect(
      suggestionOptions({ kind: "address", part: "street", group: "" }, values),
    ).toEqual(["2400 Durant Ave", "1 Main St"]);
    expect(
      suggestionOptions(
        { kind: "address", part: "street2", group: "" },
        values,
      ),
    ).toEqual(["Apt 5"]);
    expect(
      suggestionOptions({ kind: "address", part: "city", group: "" }, values),
    ).toEqual(["Berkeley"]);
    expect(
      suggestionOptions({ kind: "name", part: "full", group: "" }, values),
    ).toEqual(["Alex Rivera"]);
    expect(
      suggestionOptions({ kind: "name", part: "middle", group: "" }, values),
    ).toEqual([]);
    expect(
      suggestionOptions({ kind: "phone", part: "partial", group: "" }, values),
    ).toEqual([]);
  });
});

describe("installSuggestions", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
  });

  // What each field is showing, in place of the dropdown, which draws in a closed shadow root.
  let showing: Map<TextField, readonly Choice[]>;
  const attach = (element: TextField, choices: readonly Choice[]) => {
    showing.set(element, choices);
    return () => showing.delete(element);
  };

  const start = (
    send: (request: ContactSuggestionsRequest) => Promise<unknown>,
  ) => {
    showing = new Map();
    vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(
      new DOMRect(10, 10, 200, 30),
    );
    return installSuggestions(document, {
      host: () => "shop.example.net",
      send,
      isUserEvent: () => true,
      attach,
    });
  };

  const firstInput = (): HTMLInputElement => {
    const input = document.querySelector("input");
    if (input === null) throw new Error("no input");
    return input;
  };

  const optionsOf = (element: TextField): string[] =>
    (showing.get(element) ?? []).map((choice) => choice.value);

  const reply = () =>
    vi
      .fn<(request: ContactSuggestionsRequest) => Promise<unknown>>()
      .mockResolvedValue({ type: "contactSuggestionsResult", ...values });

  it("gives nothing to a field the page focused by itself", async () => {
    document.body.innerHTML = '<input type="email" autocomplete="email">';
    const stop = start(reply());
    await Promise.resolve();
    const field = firstInput();
    field.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(showing.size).toBe(0);
    stop();
  });

  it("asks once per kind and gives a focused field the card's values", async () => {
    document.body.innerHTML =
      '<input type="email" autocomplete="email"><input type="email" name="email2">';
    const send = reply();
    const stop = start(send);
    await Promise.resolve();
    expect(send).toHaveBeenCalledWith({
      type: "contactSuggestions",
      host: "shop.example.net",
      fields: [{ kind: "email" }],
    });

    const field = firstInput();
    field.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    field.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(optionsOf(field)).toEqual([
      "alex@work.example.org",
      "alex.rivera@example.com",
    ]);

    expect(showing.get(field)?.[0]?.detail).toBe("Email");

    field.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
    expect(showing.size).toBe(0);
    stop();
  });

  it("offers a name in a text area, as Airtable asks for one", async () => {
    document.body.innerHTML =
      '<label for="n">Full Name</label><textarea id="n"></textarea>';
    const send = reply();
    const stop = start(send);
    await Promise.resolve();
    const field = document.querySelector("textarea");
    if (field === null) throw new Error("no textarea");
    field.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    field.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    await Promise.resolve();
    expect(optionsOf(field)).toEqual(["Alex Rivera"]);
    stop();
  });
});
