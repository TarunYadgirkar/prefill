import { describe, expect, it } from "vitest";
import type { FieldDescription } from "../classify";
import { plan, rows } from "./autofill";

function field(overrides: Partial<FieldDescription>): FieldDescription {
  return { tag: "input", type: "text", autocomplete: null, label: "", names: [], placeholder: "", signIn: false, ...overrides };
}

describe("Mac autofill plan", () => {
  it("asks for the card's emails on a field labelled Email", () => {
    expect(plan(field({ label: "Email" }))).toMatchObject({ kind: "contact", request: { type: "contactSuggestions", fields: [{ kind: "email" }] } });
  });

  it("reads a name from a text area, as on Airtable", () => {
    expect(plan(field({ tag: "textarea", label: "Full Name" }))).toMatchObject({ kind: "contact", field: { kind: "name", part: "full" } });
  });

  it("asks for links of the kinds a field names, whole addresses on a url field", () => {
    expect(plan(field({ type: "url", label: "GitHub/Portfolio" }))).toMatchObject({ kind: "link", linkTypes: ["github", "website"], fullUrl: true });
  });

  it("offers nothing on sensitive or sign-in fields", () => {
    expect(plan(field({ label: "Card number" }))).toEqual({ kind: "none" });
    expect(plan(field({ label: "Email", signIn: true }))).toEqual({ kind: "none" });
  });

  it("sends the words of an unclaimed text field for custom values", () => {
    expect(plan(field({ label: "School", names: ["eduSchool"] }))).toEqual({
      kind: "custom",
      request: { type: "customSuggestions", host: "", fields: [{ text: "School eduSchool edu school" }] },
    });
  });

  it("turns the router's reply into rows with a caption", () => {
    const chosen = plan(field({ label: "City" }));
    const reply = {
      type: "contactSuggestionsResult",
      emails: [],
      phones: [],
      addresses: [{ street: "1 Main St", city: "Berkeley", state: "CA", postalCode: "94720", country: "USA" }],
    };
    expect(rows(chosen, reply)).toEqual([{ value: "Berkeley", detail: "Address", kind: "address" }]);
  });

  it("drops a reply of the wrong type", () => {
    expect(rows(plan(field({ label: "Email" })), { type: "pong" })).toEqual([]);
  });
});
