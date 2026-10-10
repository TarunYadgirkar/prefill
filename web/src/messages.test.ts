import { describe, expect, it } from "vitest";
import examples from "../../docs/message-examples.json" with { type: "json" };
import {
  FIELD_KINDS,
  LINK_TYPES,
  SECTION_HINTS,
  POPUP_STATUSES,
  RECENT_STATES,
  PICK_KINDS,
  WHYS,
  LIMITS,
  isExtensionRequest,
  isExtensionResponse,
  parseExtensionRequest,
  type CaptureRequest,
  type CaptureResult,
  type ErrorResponse,
  type Ping,
  type Pong,
  type PopupStateRequest,
  type PinRequest,
  type PickedRequest,
  type PickedResult,
  type ApplicationRequest,
  type ApplicationResult,
  type UnpinRequest,
  type UndoCaptureRequest,
  type MuteSiteRequest,
  type PopupStateResult,
  type LinkSuggestionsRequest,
  type LinkSuggestionsResult,
  type ContactSuggestionsRequest,
  type ContactSuggestionsResult,
  type AnswersRequest,
  type AnswersResult,
  type CustomSuggestionsRequest,
  type CustomSuggestionsResult,
  parsePageRequest,
} from "./messages";

// The typed literals fail typecheck if a field name drifts from messages.ts, and the
// equality checks fail if docs/message-examples.json (which Swift also reads) drifts.
const ping: Ping = { type: "ping" };

const linkSuggestions: LinkSuggestionsRequest = {
  type: "linkSuggestions",
  host: "boards.example.io",
  types: ["github", "website"],
};

const linkSuggestionsResult: LinkSuggestionsResult = {
  type: "linkSuggestionsResult",
  links: [
    { type: "github", url: "https://github.com/alexrivera", why: "pinned" },
    { type: "website", url: "https://alexrivera.dev", why: "card" },
  ],
};

const contactSuggestions: ContactSuggestionsRequest = {
  type: "contactSuggestions",
  host: "shop.example.net",
  fields: [
    { kind: "email" },
    { kind: "address", section: "shipping" },
    { kind: "name" },
  ],
};

const contactSuggestionsResult: ContactSuggestionsResult = {
  type: "contactSuggestionsResult",
  emails: [
    { value: "alex@work.example.org", why: "pinned", label: "work" },
    { value: "alex.rivera@example.com", why: "used" },
  ],
  phones: [],
  addresses: [
    {
      address: {
        street: "2400 Durant Ave",
        city: "Berkeley",
        state: "CA",
        postalCode: "94704",
        country: "United States",
      },
      why: "card",
      label: "home",
    },
  ],
  name: { given: "Alex", family: "Rivera" },
};

const customSuggestions: CustomSuggestionsRequest = {
  type: "customSuggestions",
  host: "boards.example.io",
  fields: [
    { text: "School job_application[educations][0][school_name_id]" },
    { text: "Cover letter", focused: true },
    { text: "Will you relocate for this role?", heading: "Logistics", options: ["Yes", "No", "Open to discussion"] },
  ],
};

const answers: AnswersRequest = {
  type: "answers",
  host: "boards.example.io",
  action: "learn",
  answers: [
    { question: "school", value: "UC Berkeley" },
    {
      question: "sponsorship",
      value: "No",
      text: "Do you or will you require sponsorship in the future to work in the U.S.?",
      options: ["Yes", "No"],
      changedFill: true,
    },
  ],
};
const answersResult: AnswersResult = { type: "answersResult", saved: 2, updated: ["Work authorization"], ask: ["Sponsorship"] };
const picked: PickedRequest = {
  type: "picked",
  host: "boards.example.io",
  kind: "email",
  value: "alex.rivera@example.com",
};
const pickedResult: PickedResult = { type: "pickedResult", remembered: true };
const application: ApplicationRequest = {
  type: "application",
  id: "6F9619FF-8B86-D011-B42D-00C04FC964FF",
  host: "jobs.lever.co",
  path: "/kepler/2b9c/apply",
  title: "Kepler Communications - Embedded Software Intern",
  fields: [
    { question: "What year of study are you in?", answer: "3rd" },
    { question: "Describe a C or C++ project you've worked on", answer: "I wrote firmware for a CubeSat radio.\nTested it on a bench." },
  ],
  files: [{ question: "Resume/CV", name: "Resume_Fall_2026.pdf" }],
};
const applicationResult: ApplicationResult = { type: "applicationResult", saved: true };
const customSuggestionsResult: CustomSuggestionsResult = {
  type: "customSuggestionsResult",
  fields: [
    { values: [{ value: "UC Berkeley", why: "card", label: "School" }], guesses: [] },
    {
      values: [{ value: "Yes", why: "learned", label: "Work authorization", site: "example.io" }],
      guesses: [],
    },
    { values: [], guesses: ["EECS"] },
    {
      values: [],
      guesses: [],
      suggested: [{ value: "Yes", why: "card", label: "Work authorization" }],
      noAnswerFor: "Canada",
    },
    {
      values: [],
      guesses: [],
      drafts: [{ value: "Dear hiring team,\nI build tools people use every day.", why: "draft", label: "Cover letter" }],
    },
  ],
};

const capture: CaptureRequest = {
  type: "capture",
  host: "shop.example.net",
  hasPassword: true,
  trigger: "submit",
  fields: [
    {
      kind: "name",
      value: "Alex Rivera",
      autocomplete: "name",
      name: "full_name",
      label: "Full name",
      userTyped: true,
    },
    {
      kind: "email",
      value: "alex.new@example.net",
      autocomplete: "email",
      name: "email",
      label: "Email",
      userTyped: true,
    },
    {
      kind: "address",
      section: "shipping",
      userTyped: true,
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
const captureResult: CaptureResult = {
  type: "captureResult",
  saved: 1,
  review: 0,
  ignored: 1,
};
const error: ErrorResponse = { type: "error", reason: "unknown message" };

const WORK = "5E1D7C1A-8C1B-5F0E-9A6B-2C4D6E8F0A1B";
const HOME = "0B3E5A7C-9D1F-5B2A-8C4E-6F8A0B2C4D6E";
const ADDED = "7A9C1E3B-5D7F-5A1C-8E2B-4D6F8A0C2E4A";
const popupState: PopupStateRequest = {
  type: "popupState",
  host: "shop.example.net",
  kinds: ["email"],
};
const pin: PinRequest = {
  type: "pin",
  host: "shop.example.net",
  kind: "email",
  valueID: WORK,
};
const unpin: UnpinRequest = {
  type: "unpin",
  host: "shop.example.net",
  kind: "email",
};
const undoCapture: UndoCaptureRequest = {
  type: "undoCapture",
  host: "shop.example.net",
  valueID: ADDED,
};
const muteSite: MuteSiteRequest = {
  type: "muteSite",
  host: "shop.example.net",
  muted: true,
};
const popupStateResult: PopupStateResult = {
  type: "popupStateResult",
  status: "ready",
  kinds: [
    {
      kind: "email",
      pinnedID: WORK,
      values: [
        { id: WORK, caption: "work", text: "alex@work.example.org" },
        { id: HOME, caption: "home", text: "alex.rivera@example.com" },
      ],
    },
  ],
  recent: [
    {
      kind: "email",
      state: "saved",
      value: { id: ADDED, caption: "email", text: "alex.new@example.net" },
    },
  ],
  muted: false,
};

describe("message contract", () => {
  it("lists every shared value the way Swift does", () => {
    expect(examples.enums).toEqual({
      fieldKind: [...FIELD_KINDS],
      linkType: [...LINK_TYPES],
      sectionHint: [...SECTION_HINTS],
      popupStatus: [...POPUP_STATUSES],
      recentState: [...RECENT_STATES],
      pickKind: [...PICK_KINDS],
      why: [...WHYS],
    });
  });

  it.each([
    ...FIELD_KINDS.map((kind) => ({ kind })),
    ...SECTION_HINTS.map((section) => ({ kind: "address" as const, section })),
  ])("accepts the page field %j", (field) => {
    expect(
      isExtensionRequest({
        type: "contactSuggestions",
        host: "example.net",
        fields: [field],
      }),
    ).toBe(true);
  });

  // Prefill no longer reorders the card for a page, so the old report is an unknown message.
  it("turns away the retired pageContext messages", () => {
    expect(
      isExtensionRequest({ type: "pageContext", host: "example.net", fields: [{ kind: "email" }] }),
    ).toBe(false);
    expect(isExtensionResponse({ type: "pageContextResult", status: "saved" })).toBe(false);
  });

  it.each(
    Object.entries({
      ping,
      capture,
      popupState,
      pin,
      unpin,
      undoCapture,
      muteSite,
      linkSuggestions,
      contactSuggestions,
      customSuggestions,
      answers,
      picked,
      application,
    }),
  )("request %s matches the shared example", (name, typed) => {
    const example: unknown =
      examples.requests[name as keyof typeof examples.requests];
    expect(example).toEqual(typed);
    expect(isExtensionRequest(example)).toBe(true);
  });

  it.each(
    Object.entries({
      pong,
      captureResult,
      popupStateResult,
      linkSuggestionsResult,
      contactSuggestionsResult,
      customSuggestionsResult,
      answersResult,
      pickedResult,
      applicationResult,
      error,
    }),
  )("response %s matches the shared example", (name, typed) => {
    const example: unknown =
      examples.responses[name as keyof typeof examples.responses];
    expect(example).toEqual(typed);
    expect(isExtensionResponse(example)).toBe(true);
  });

  it.each([
    null,
    "ping",
    {},
    { type: "launch" },
    { type: "toString" },
    { type: "contactSuggestions", host: "example.net" },
    { type: "contactSuggestions", host: "example.net", fields: [{ kind: "fax" }] },
    {
      type: "contactSuggestions",
      host: "example.net",
      fields: [{ kind: "email", section: "school" }],
    },
    { type: "capture", host: "example.net", fields: [] },
    {
      type: "capture",
      host: "example.net",
      hasPassword: false,
      trigger: "submit",
      fields: [{ kind: "email", value: 7, userTyped: true }],
    },
    { type: "capture", host: "example.net", hasPassword: false, fields: [] },
    {
      type: "capture",
      host: "example.net",
      hasPassword: false,
      submitted: true,
      fields: [],
    },
    {
      type: "capture",
      host: "example.net",
      hasPassword: false,
      trigger: "script",
      fields: [],
    },
    { type: "contactSuggestions", host: "Example.net/path", fields: [] },
    { type: "popupState", host: "example.net", kinds: ["name"] },
    {
      type: "popupState",
      host: "example.net",
      kinds: ["email", "phone", "address", "email"],
    },
    { type: "pin", host: "example.net", kind: "email", valueID: "not-a-uuid" },
    { type: "muteSite", host: "example.net", muted: "yes" },
    {
      type: "customSuggestions",
      host: "example.net",
      fields: [{ text: "School\u200b" }],
    },
    { type: "answers", host: "example.net", action: "learn", answers: [{ question: "gpa", value: "4", text: "q".repeat(201) }] },
    { type: "answers", host: "example.net", action: "learn", answers: [{ question: "gpa", value: "4", text: "In\u202e Canada" }] },
    {
      type: "answers",
      host: "example.net",
      action: "learn",
      answers: [{ question: "gpa", value: "4", options: Array<string>(11).fill("Yes") }],
    },
    { type: "answers", host: "example.net", action: "learn", answers: [{ question: "gpa", value: "4", options: ["o".repeat(101)] }] },
  ])("rejects the request %j", (message) => {
    expect(isExtensionRequest(message)).toBe(false);
  });

  it.each([
    { type: "captureResult", saved: -1, review: 0, ignored: 0 },
    { type: "error" },
  ])("rejects the response %j", (message) => {
    expect(isExtensionResponse(message)).toBe(false);
  });

  it("drops properties the contract doesn't name", () => {
    const message = {
      ...capture,
      extra: "x",
      fields: [
        { kind: "email", value: "a@example.net", userTyped: true, html: "<b>" },
      ],
    };
    expect(parseExtensionRequest(message)).toEqual({
      ...capture,
      fields: [{ kind: "email", value: "a@example.net", userTyped: true }],
    });
  });
});

describe("message limits, mirrored in MessageLimits.swift", () => {
  const field = (extra: Record<string, unknown>) => ({
    kind: "email",
    value: "a@example.net",
    userTyped: true,
    ...extra,
  });
  const request = (fields: unknown[], host = "shop.example.net") => ({
    type: "capture",
    host,
    hasPassword: false,
    trigger: "submit",
    fields,
  });

  it("accepts a capture right at the limits", () => {
    const full = field({
      value: "a".repeat(LIMITS.value),
      label: "b".repeat(LIMITS.text),
    });
    expect(
      isExtensionRequest(
        request(Array<unknown>(LIMITS.captureFields).fill(full)),
      ),
    ).toBe(true);
  });

  it.each([
    ["a long value", request([field({ value: "a".repeat(LIMITS.value + 1) })])],
    ["a long name", request([field({ name: "n".repeat(LIMITS.text + 1) })])],
    [
      "a long autocomplete",
      request([field({ autocomplete: "x".repeat(LIMITS.text + 1) })]),
    ],
    [
      "too many fields",
      request(Array<unknown>(LIMITS.captureFields + 1).fill(field({}))),
    ],
    ["a long host", request([field({})], "h".repeat(LIMITS.host + 1))],
    [
      "a right-to-left override",
      request([field({ value: "a\u202E@example.net" })]),
    ],
    ["a zero-width space", request([field({ value: "a\u200B@example.net" })])],
    [
      "a newline in an email",
      request([field({ value: "a@example.net\nBcc: b@example.net" })]),
    ],
    [
      "an email sent as an address",
      request([
        {
          kind: "email",
          userTyped: true,
          address: {
            street: "1 Main St",
            city: "",
            state: "",
            postalCode: "",
            country: "",
          },
        },
      ]),
    ],
    [
      "an address sent as one value",
      request([{ kind: "address", value: "1 Main St", userTyped: true }]),
    ],
    [
      "a field without provenance",
      request([{ kind: "email", value: "a@example.net" }]),
    ],
    // eslint-disable-next-line no-sparse-arrays
    ["a sparse field list", request([field({}), , field({})])],
    [
      "a long address part",
      request([
        {
          kind: "address",
          userTyped: true,
          address: {
            street: "1 Main St",
            city: "c".repeat(LIMITS.part + 1),
            state: "",
            postalCode: "",
            country: "",
          },
        },
      ]),
    ],
    [
      "too many page fields",
      {
        type: "contactSuggestions",
        host: "example.net",
        fields: Array<unknown>(LIMITS.pageFields + 1).fill({ kind: "email" }),
      },
    ],
  ])("turns away %s", (_, message) => {
    expect(isExtensionRequest(message)).toBe(false);
  });
});

describe("sheet messages", () => {
  it("are never page requests, so the background script won't relay them", () => {
    for (const message of [popupState, pin, unpin, undoCapture, muteSite])
      expect(parsePageRequest(message)).toBeUndefined();
  });

  it.each([
    [
      "too many values",
      {
        kind: "email",
        values: Array<unknown>(LIMITS.popupValues + 1).fill({
          id: WORK,
          caption: "work",
          text: "a",
        }),
      },
    ],
    [
      "a value over the display limit",
      {
        kind: "email",
        values: [
          { id: WORK, caption: "work", text: "a".repeat(LIMITS.display + 1) },
        ],
      },
    ],
    [
      "a line break in a value",
      { kind: "email", values: [{ id: WORK, caption: "work", text: "a\nb" }] },
    ],
  ])("turns away a reply with %s", (_, kind) => {
    expect(isExtensionResponse({ ...popupStateResult, kinds: [kind] })).toBe(
      false,
    );
  });
});

describe("drafts", () => {
  const reply = (draft: Record<string, unknown>): unknown => ({
    type: "customSuggestionsResult",
    fields: [{ values: [], drafts: [draft] }],
  });

  it("keep their line breaks and their length, and are only ever drafts", () => {
    expect(isExtensionResponse(reply({ value: `Dear team,\n${"a".repeat(1_900)}`, why: "draft", label: "Cover letter" }))).toBe(true);
    expect(isExtensionResponse(reply({ value: "Yes", why: "card" }))).toBe(false);
    expect(isExtensionResponse(reply({ value: "a".repeat(LIMITS.draftValue + 1), why: "draft" }))).toBe(false);
    expect(isExtensionResponse(reply({ value: "a‮b", why: "draft" }))).toBe(false);
  });
});
