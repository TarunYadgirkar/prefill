// The extension's field rules for the Mac app, which reads fields through Accessibility
// and runs this file in JavaScriptCore. It describes a field the way the DOM would, gets
// back what to ask the app's router for, then turns the router's reply into the rows its
// panel shows. Built to web/dist-mac/autofill.js as the global `PrefillAutofill`.
import { parseAutocomplete } from "../autocomplete";
import { classifyDescription, type FieldDescription } from "../classify";
import { CUSTOM_DETAIL, joinFieldText } from "../custom";
import type { Choice } from "../dropdown";
import { isContact, type ContactField } from "../fieldTypes";
import { linkChoices } from "../links";
import { splitNames } from "../dom";
import { takesSavedAnswer } from "../fill";
import { parsePageResponse, type LinkType, type PageField, type PageRequest, type PageResponse } from "../messages";
import { KIND_LABELS, SUGGESTED_KINDS, suggestionOptions } from "../suggestions";

export type Plan =
  | { kind: "contact"; field: ContactField; request: PageRequest }
  | { kind: "link"; linkTypes: LinkType[]; fullUrl: boolean; request: PageRequest }
  | { kind: "custom"; request: PageRequest }
  | { kind: "none" };

export interface Row extends Choice {
  // What the value is, for the panel's symbol: a contact kind, "link" or "custom".
  kind: string;
}

// The inputs each kind of list appears on, as in the extension.
const CONTACT_INPUTS: ReadonlySet<string> = new Set(["text", "email", "tel", "search"]);
const NONE: Plan = { kind: "none" };

function takesText(field: FieldDescription, inputs: ReadonlySet<string>): boolean {
  return field.tag === "textarea" || (field.tag === "input" && inputs.has(field.type.toLowerCase()));
}

function wantsUrl(field: FieldDescription): boolean {
  return parseAutocomplete(field.autocomplete)?.field === "url" || field.type.toLowerCase() === "url";
}

function contactPlan(field: ContactField): Plan {
  const entry: PageField = field.section === undefined ? { kind: field.kind } : { kind: field.kind, section: field.section };
  return { kind: "contact", field, request: { type: "contactSuggestions", host: "", fields: [entry] } };
}

function customPlan(field: FieldDescription): Plan {
  const isCandidate = field.tag === "textarea" || (field.tag === "input" && field.type.toLowerCase() === "text");
  if (!isCandidate || field.signIn || parseAutocomplete(field.autocomplete) !== undefined) return NONE;
  const text = joinFieldText([field.label, field.placeholder, ...splitNames(field.names)]);
  return text === "" ? NONE : { kind: "custom", request: { type: "customSuggestions", host: "", fields: [{ text }] } };
}

export function plan(field: FieldDescription): Plan {
  const found = classifyDescription(field);
  if (found.kind === "link") {
    if (field.tag !== "input") return NONE;
    const linkTypes = [...(found.linkTypes ?? [])];
    return { kind: "link", linkTypes, fullUrl: wantsUrl(field), request: { type: "linkSuggestions", host: "", types: linkTypes } };
  }
  if (isContact(found)) return SUGGESTED_KINDS.has(found.kind) && takesText(field, CONTACT_INPUTS) ? contactPlan(found) : NONE;
  return found.kind === "ignored" ? customPlan(field) : NONE;
}

function contactRows(chosen: Extract<Plan, { kind: "contact" }>, response: PageResponse): Row[] {
  if (response.type !== "contactSuggestionsResult") return [];
  const detail = KIND_LABELS[chosen.field.kind] ?? "";
  return suggestionOptions(chosen.field, response).map((value) => ({ value, detail, kind: chosen.field.kind }));
}

function linkRows(chosen: Extract<Plan, { kind: "link" }>, response: PageResponse): Row[] {
  if (response.type !== "linkSuggestionsResult") return [];
  return linkChoices(chosen.linkTypes, response.links, chosen.fullUrl).map((choice) => ({ ...choice, kind: "link" }));
}

function customRows(response: PageResponse): Row[] {
  if (response.type !== "customSuggestionsResult") return [];
  return (response.fields[0]?.values ?? []).map((value) => ({ value, detail: CUSTOM_DETAIL, kind: "custom" }));
}

export function rows(chosen: Plan, reply: unknown): Row[] {
  const response = parsePageResponse(reply);
  if (response === undefined) return [];
  switch (chosen.kind) {
    case "contact":
      return contactRows(chosen, response);
    case "link":
      return linkRows(chosen, response);
    case "custom":
      return customRows(response);
    case "none":
      return [];
  }
}

// What "Fill form" does with one of the form's fields: the same plan a focused field gets,
// except that a text box asking a demographic or follow-up question is left for the person,
// as in the extension's one-tap fill.
export function fillPlan(field: FieldDescription): Plan {
  const chosen = plan(field);
  if (chosen.kind !== "custom" || chosen.request.type !== "customSuggestions") return chosen;
  return takesSavedAnswer(joinFieldText([field.label, field.placeholder])) ? chosen : NONE;
}

// JSON in and out, so the Swift side needs no knowledge of these types.
const api = {
  plan: (description: string): string => JSON.stringify(plan(JSON.parse(description) as FieldDescription)),
  fillPlan: (description: string): string => JSON.stringify(fillPlan(JSON.parse(description) as FieldDescription)),
  rows: (chosen: string, reply: string): string => JSON.stringify(rows(JSON.parse(chosen) as Plan, JSON.parse(reply))),
};

(globalThis as { PrefillAutofill?: typeof api }).PrefillAutofill = api;
