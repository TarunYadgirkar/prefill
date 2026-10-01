import { describe, expect, it } from "vitest";
import examples from "../../docs/message-examples.json" with { type: "json" };
import {
  FIELD_KINDS,
  SECTION_HINTS,
  SYNC_STATUSES,
  isExtensionRequest,
  isExtensionResponse,
  type CaptureRequest,
  type CaptureResult,
  type ErrorResponse,
  type PageContextRequest,
  type PageContextResult,
  type Ping,
  type Pong,
} from "./messages";

// The typed literals fail typecheck if a field name drifts from messages.ts, and the
// equality checks fail if docs/message-examples.json (which Swift also reads) drifts.
const ping: Ping = { type: "ping" };

const pageContext: PageContextRequest = {
  type: "pageContext",
  host: "shop.example.net",
  fields: [{ kind: "email", section: "work" }, { kind: "phone" }, { kind: "address", section: "shipping" }],
};

const capture: CaptureRequest = {
  type: "capture",
  host: "shop.example.net",
  hasPassword: true,
  fields: [
    { kind: "name", value: "Alex Rivera", autocomplete: "name", name: "full_name", label: "Full name" },
    { kind: "email", value: "alex.new@example.net", autocomplete: "email", name: "email", label: "Email" },
    {
      kind: "address",
      section: "shipping",
      address: {
        street: "2400 Durant Ave",
        city: "Berkeley",
        state: "CA",
        postalCode: "94704",
        country: "United States",
      },
    },
  ],
};

const pong: Pong = { type: "pong" };
const pageContextResult: PageContextResult = { type: "pageContextResult", status: "saved" };
const pageContextFailed: PageContextResult = {
  type: "pageContextResult",
  status: "failed",
  reason: "Prefill can't reach your contact card. Open Prefill to give it access again.",
};
const captureResult: CaptureResult = { type: "captureResult", saved: 1, review: 0, ignored: 1 };
const error: ErrorResponse = { type: "error", reason: "unknown message" };

describe("message contract", () => {
  it("lists every shared value the way Swift does", () => {
    expect(examples.enums).toEqual({
      fieldKind: [...FIELD_KINDS],
      sectionHint: [...SECTION_HINTS],
      syncStatus: [...SYNC_STATUSES],
    });
  });

  it.each([
    ...FIELD_KINDS.map((kind) => ({ kind })),
    ...SECTION_HINTS.map((section) => ({ kind: "address" as const, section })),
  ])("accepts the page field %j", (field) => {
    expect(isExtensionRequest({ type: "pageContext", host: "example.net", fields: [field] })).toBe(true);
  });

  it.each(SYNC_STATUSES)("accepts the sync status %s", (status) => {
    expect(isExtensionResponse({ type: "pageContextResult", status })).toBe(true);
  });

  it.each(Object.entries({ ping, pageContext, capture }))("request %s matches the shared example", (name, typed) => {
    const example: unknown = examples.requests[name as keyof typeof examples.requests];
    expect(example).toEqual(typed);
    expect(isExtensionRequest(example)).toBe(true);
  });

  it.each(Object.entries({ pong, pageContextResult, pageContextFailed, captureResult, error }))(
    "response %s matches the shared example",
    (name, typed) => {
      const example: unknown = examples.responses[name as keyof typeof examples.responses];
      expect(example).toEqual(typed);
      expect(isExtensionResponse(example)).toBe(true);
    },
  );

  it.each([
    null,
    "ping",
    {},
    { type: "launch" },
    { type: "toString" },
    { type: "pageContext", host: "example.net" },
    { type: "pageContext", host: "example.net", fields: [{ kind: "fax" }] },
    { type: "pageContext", host: "example.net", fields: [{ kind: "email", section: "school" }] },
    { type: "capture", host: "example.net", fields: [] },
    { type: "capture", host: "example.net", hasPassword: false, fields: [{ kind: "email", value: 7 }] },
  ])("rejects the request %j", (message) => {
    expect(isExtensionRequest(message)).toBe(false);
  });

  it.each([
    { type: "pageContextResult", status: "done" },
    { type: "captureResult", saved: -1, review: 0, ignored: 0 },
    { type: "error" },
  ])("rejects the response %j", (message) => {
    expect(isExtensionResponse(message)).toBe(false);
  });
});
