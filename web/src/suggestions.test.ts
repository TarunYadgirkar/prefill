import { afterEach, describe, expect, it, vi } from "vitest";
import type { Choice, TextField } from "./dropdown";
import {
  installSuggestions,
  suggestionOptions,
  type SuggestionOptions,
  type Suggestions,
} from "./suggestions";

const card = (value: string) => ({ value, why: "card" as const });
const address = (street: string, postalCode: string) => ({
  address: { street, city: "Berkeley", state: "CA", postalCode, country: "United States" },
  why: "card" as const,
});

const values: Suggestions = {
  emails: [
    card("alex@work.example.org"),
    card("alex.rivera@example.com"),
    card("alex@work.example.org"),
  ],
  phones: [card("+1 510 555 0100")],
  addresses: [address("2400 Durant Ave\nApt 5", "94704"), address("1 Main St", "94710")],
  name: { given: "Alex", family: "Rivera" },
};

const texts = (offered: readonly { value: string }[]): string[] =>
  offered.map(({ value }) => value);

describe("suggestionOptions", () => {
  it("offers each value once, in the app's order", () => {
    expect(texts(suggestionOptions({ kind: "email", group: "" }, values))).toEqual([
      "alex@work.example.org",
      "alex.rivera@example.com",
    ]);
  });

  it("offers the part of each address and name a field asks for", () => {
    expect(
      texts(suggestionOptions({ kind: "address", part: "street", group: "" }, values)),
    ).toEqual(["2400 Durant Ave", "1 Main St"]);
    expect(
      texts(suggestionOptions({ kind: "address", part: "street2", group: "" }, values)),
    ).toEqual(["Apt 5"]);
    expect(
      texts(suggestionOptions({ kind: "address", part: "city", group: "" }, values)),
    ).toEqual(["Berkeley"]);
    expect(
      texts(suggestionOptions({ kind: "name", part: "full", group: "" }, values)),
    ).toEqual(["Alex Rivera"]);
    expect(
      texts(suggestionOptions({ kind: "name", part: "middle", group: "" }, values)),
    ).toEqual([]);
    expect(
      texts(suggestionOptions({ kind: "phone", part: "partial", group: "" }, values)),
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

  const start = (send: SuggestionOptions["send"]) => {
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
      .fn<SuggestionOptions["send"]>()
      .mockImplementation((request) =>
        Promise.resolve(
          request.type === "picked"
            ? { type: "pickedResult", remembered: true }
            : { type: "contactSuggestionsResult", ...values },
        ),
      );

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

  it("tells the app about a pick that wasn't first, then asks for the new order", async () => {
    document.body.innerHTML = '<input type="email" autocomplete="email">';
    const send = reply();
    const stop = start(send);
    await Promise.resolve();
    const field = firstInput();
    field.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    field.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    const [first, second] = showing.get(field) ?? [];
    expect(first?.onPick).toBeUndefined();
    send.mockClear();
    second?.onPick?.();
    await vi.waitFor(() => {
      expect(send).toHaveBeenCalledTimes(2);
    });
    expect(send.mock.calls.map(([request]) => request.type)).toEqual([
      "picked",
      "contactSuggestions",
    ]);
    expect(send).toHaveBeenCalledWith({
      type: "picked",
      host: "shop.example.net",
      kind: "email",
      value: "alex.rivera@example.com",
    });
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
