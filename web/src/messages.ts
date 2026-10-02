// Wire format shared with Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift
// and described in docs/messages.md. Field names and limits must stay identical on both
// sides; docs/message-examples.json is checked by tests in both languages. The types are
// derived from the parsers below, so a parser and its type can't drift apart.

export const FIELD_KINDS = ["email", "phone", "address", "name", "link"] as const;
// What a profile or website link is, read from its host by the app.
export const LINK_TYPES = ["github", "website", "linkedin", "x", "other"] as const;
export const SECTION_HINTS = ["home", "work", "shipping", "billing"] as const;
export const SYNC_STATUSES = ["unchanged", "saved", "failed", "off", "notSetUp"] as const;
// "submit" is a form the person sent. "flush" is what they typed before the page was hidden,
// which is never saved straight to the card.
export const CAPTURE_TRIGGERS = ["submit", "flush"] as const;
// Safari's Prefill sheet works with the kinds that can sit on the card.
export const CONTACT_KINDS = ["email", "phone", "address"] as const;
export const POPUP_STATUSES = ["ready", "off", "notSetUp", "failed"] as const;
export const RECENT_STATES = ["saved", "waiting", "removed"] as const;

// Mirrored by MessageLimits in Messages.swift.
export const LIMITS = {
  host: 253,
  pageFields: 40,
  captureFields: 20,
  value: 256,
  text: 100,
  street: 400,
  part: 200,
  reason: 500,
  popupKinds: 3,
  popupValues: 30,
  popupRecent: 5,
  display: 1_000,
  linkTypes: 5,
  links: 10,
} as const;

export type FieldKind = (typeof FIELD_KINDS)[number];
export type LinkType = (typeof LINK_TYPES)[number];
export type SectionHint = (typeof SECTION_HINTS)[number];
export type SyncStatus = (typeof SYNC_STATUSES)[number];
export type CaptureTrigger = (typeof CAPTURE_TRIGGERS)[number];
export type ContactKind = (typeof CONTACT_KINDS)[number];
export type PopupStatus = (typeof POPUP_STATUSES)[number];
export type RecentState = (typeof RECENT_STATES)[number];

const INVALID: unique symbol = Symbol("invalid");
type Parser<T> = (value: unknown) => T | typeof INVALID;
interface Optional<T> {
  optional: Parser<T>;
}
type Field = Parser<unknown> | Optional<unknown>;
type Parsed<P> = P extends Parser<infer T> ? T : never;
type Flat<T> = { [K in keyof T]: T[K] };
type ObjectOf<S extends Record<string, Field>> = Flat<
  { [K in keyof S as S[K] extends Optional<unknown> ? never : K]: Parsed<S[K]> } & {
    [K in keyof S as S[K] extends Optional<unknown> ? K : never]?: S[K] extends Optional<infer T> ? T : never;
  }
>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

// Control, format (bidi overrides, zero-width) and line or paragraph separator characters
// never belong in contact data. A street may span lines, so it keeps plain newlines.
export const HIDDEN_CHARACTERS = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u;
export const HIDDEN_EXCEPT_NEWLINE = /[^\P{Cc}\n]|[\p{Cf}\p{Zl}\p{Zp}]/u;
const HOST = /^[a-z0-9.-]+$/u;
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/iu;

const text =
  (max: number, hidden: RegExp = HIDDEN_CHARACTERS): Parser<string> =>
  (value) =>
    typeof value === "string" && value.length <= max && !hidden.test(value) ? value : INVALID;
const hostName: Parser<string> = (value) =>
  typeof value === "string" && value.length <= LIMITS.host && HOST.test(value) ? value : INVALID;
const uuid: Parser<string> = (value) => (typeof value === "string" && UUID.test(value) ? value : INVALID);
const boolean: Parser<boolean> = (value) => (typeof value === "boolean" ? value : INVALID);
const count: Parser<number> = (value) =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : INVALID;
const literal =
  <T extends string>(expected: T): Parser<T> =>
  (value) =>
    value === expected ? expected : INVALID;
const oneOf =
  <T extends string>(allowed: readonly T[]): Parser<T> =>
  (value) =>
    allowed.find((candidate) => candidate === value) ?? INVALID;
const optional = <T>(parser: Parser<T>): Optional<T> => ({ optional: parser });

const arrayOf =
  <T>(item: Parser<T>, max: number): Parser<T[]> =>
  (value) => {
    if (!Array.isArray(value) || value.length > max) return INVALID;
    // Array.from visits holes too, so a sparse array fails instead of slipping through.
    const items = Array.from(value, item);
    return items.some((parsed) => parsed === INVALID) ? INVALID : (items as T[]);
  };

function parseField(field: Field, raw: unknown): unknown {
  if (typeof field === "function") return field(raw);
  return raw === undefined ? undefined : field.optional(raw);
}

// Rebuilds the object from the known keys only, so nothing extra travels on.
const object =
  <S extends Record<string, Field>>(shape: S): Parser<ObjectOf<S>> =>
  (value) => {
    if (!isRecord(value)) return INVALID;
    const entries = Object.entries(shape).map(([key, field]) => [key, parseField(field, value[key])] as const);
    if (entries.some(([, parsed]) => parsed === INVALID)) return INVALID;
    return Object.fromEntries(entries.filter(([, parsed]) => parsed !== undefined)) as ObjectOf<S>;
  };

const refine =
  <T>(parser: Parser<T>, holds: (parsed: T) => boolean): Parser<T> =>
  (value) => {
    const parsed = parser(value);
    return parsed !== INVALID && holds(parsed) ? parsed : INVALID;
  };

const section = optional(oneOf(SECTION_HINTS));

const postalAddress = object({
  street: text(LIMITS.street, HIDDEN_EXCEPT_NEWLINE),
  city: text(LIMITS.part),
  state: text(LIMITS.part),
  postalCode: text(LIMITS.part),
  country: text(LIMITS.part),
});

const pageField = object({ kind: oneOf(FIELD_KINDS), section });

const WEB_ADDRESS = /^https?:\/\/\S+$/u;
const suggestedLink = object({
  type: oneOf(LINK_TYPES),
  url: refine(text(LIMITS.value), (url) => WEB_ADDRESS.test(url)),
});

// An address arrives in parts and every other kind as one value, never both.
const capturedField = refine(
  object({
    kind: oneOf(FIELD_KINDS),
    value: optional(text(LIMITS.value)),
    address: optional(postalAddress),
    autocomplete: optional(text(LIMITS.text)),
    name: optional(text(LIMITS.text)),
    label: optional(text(LIMITS.text)),
    section,
    userTyped: boolean,
  }),
  (field) =>
    field.kind === "address"
      ? field.address !== undefined && field.value === undefined
      : field.address === undefined && field.value !== undefined,
);

const pageRequests = {
  ping: object({ type: literal("ping") }),
  pageContext: object({
    type: literal("pageContext"),
    host: hostName,
    fields: arrayOf(pageField, LIMITS.pageFields),
  }),
  capture: object({
    type: literal("capture"),
    host: hostName,
    hasPassword: boolean,
    trigger: oneOf(CAPTURE_TRIGGERS),
    fields: arrayOf(capturedField, LIMITS.captureFields),
  }),
  linkSuggestions: object({
    type: literal("linkSuggestions"),
    host: hostName,
    types: arrayOf(oneOf(LINK_TYPES), LIMITS.linkTypes),
  }),
};

const contactKind = oneOf(CONTACT_KINDS);

// Sent only by the extension's own sheet, never relayed from a page.
const sheetRequests = {
  popupState: object({
    type: literal("popupState"),
    host: hostName,
    kinds: arrayOf(contactKind, LIMITS.popupKinds),
  }),
  pin: object({ type: literal("pin"), host: hostName, kind: contactKind, valueID: uuid }),
  unpin: object({ type: literal("unpin"), host: hostName, kind: contactKind }),
  undoCapture: object({ type: literal("undoCapture"), host: hostName, valueID: uuid }),
  muteSite: object({ type: literal("muteSite"), host: hostName, muted: boolean }),
};

const popupValue = object({ id: uuid, caption: text(LIMITS.text), text: text(LIMITS.display) });
const popupKind = object({
  kind: contactKind,
  values: arrayOf(popupValue, LIMITS.popupValues),
  pinnedID: optional(uuid),
});
const popupRecent = object({ value: popupValue, kind: contactKind, state: oneOf(RECENT_STATES) });

const pageResponses = {
  pong: object({ type: literal("pong") }),
  pageContextResult: object({
    type: literal("pageContextResult"),
    status: oneOf(SYNC_STATUSES),
    reason: optional(text(LIMITS.reason)),
  }),
  captureResult: object({ type: literal("captureResult"), saved: count, review: count, ignored: count }),
  linkSuggestionsResult: object({ type: literal("linkSuggestionsResult"), links: arrayOf(suggestedLink, LIMITS.links) }),
  error: object({ type: literal("error"), reason: text(LIMITS.reason) }),
};

const sheetResponses = {
  popupStateResult: object({
    type: literal("popupStateResult"),
    status: oneOf(POPUP_STATUSES),
    reason: optional(text(LIMITS.reason)),
    kinds: arrayOf(popupKind, LIMITS.popupKinds),
    recent: arrayOf(popupRecent, LIMITS.popupRecent),
    muted: boolean,
  }),
  error: pageResponses.error,
};

export type PostalAddress = Parsed<typeof postalAddress>;
export type PageField = Parsed<typeof pageField>;
export type CapturedField = Parsed<typeof capturedField>;
export type Ping = Parsed<typeof pageRequests.ping>;
export type PageContextRequest = Parsed<typeof pageRequests.pageContext>;
export type CaptureRequest = Parsed<typeof pageRequests.capture>;
export type LinkSuggestionsRequest = Parsed<typeof pageRequests.linkSuggestions>;
export type PageRequest = Ping | PageContextRequest | CaptureRequest | LinkSuggestionsRequest;
export type PopupStateRequest = Parsed<typeof sheetRequests.popupState>;
export type PinRequest = Parsed<typeof sheetRequests.pin>;
export type UnpinRequest = Parsed<typeof sheetRequests.unpin>;
export type UndoCaptureRequest = Parsed<typeof sheetRequests.undoCapture>;
export type MuteSiteRequest = Parsed<typeof sheetRequests.muteSite>;
export type SheetRequest = PopupStateRequest | PinRequest | UnpinRequest | UndoCaptureRequest | MuteSiteRequest;
export type ExtensionRequest = PageRequest | SheetRequest;
export type Pong = Parsed<typeof pageResponses.pong>;
export type PageContextResult = Parsed<typeof pageResponses.pageContextResult>;
export type CaptureResult = Parsed<typeof pageResponses.captureResult>;
export type ErrorResponse = Parsed<typeof pageResponses.error>;
export type SuggestedLink = Parsed<typeof suggestedLink>;
export type LinkSuggestionsResult = Parsed<typeof pageResponses.linkSuggestionsResult>;
export type PageResponse = Pong | PageContextResult | CaptureResult | LinkSuggestionsResult | ErrorResponse;
export type PopupValue = Parsed<typeof popupValue>;
export type PopupKind = Parsed<typeof popupKind>;
export type PopupRecent = Parsed<typeof popupRecent>;
export type PopupStateResult = Parsed<typeof sheetResponses.popupStateResult>;
export type SheetResponse = PopupStateResult | ErrorResponse;
export type ExtensionResponse = PageResponse | PopupStateResult;

function parseByType<T>(parsers: Record<string, Parser<T>>, message: unknown): T | undefined {
  if (!isRecord(message) || typeof message.type !== "string") return undefined;
  const parser = Object.hasOwn(parsers, message.type) ? parsers[message.type] : undefined;
  const parsed = parser?.(message);
  return parsed === undefined || parsed === INVALID ? undefined : parsed;
}

export function parseExtensionRequest(message: unknown): ExtensionRequest | undefined {
  return parseByType<ExtensionRequest>({ ...pageRequests, ...sheetRequests }, message);
}

export function parseExtensionResponse(message: unknown): ExtensionResponse | undefined {
  return parseByType<ExtensionResponse>({ ...pageResponses, ...sheetResponses }, message);
}

// What a page may send through the background script, and what may come back to it.
export function parsePageRequest(message: unknown): PageRequest | undefined {
  return parseByType<PageRequest>(pageRequests, message);
}

export function parsePageResponse(message: unknown): PageResponse | undefined {
  return parseByType<PageResponse>(pageResponses, message);
}

export function parseSheetResponse(message: unknown): SheetResponse | undefined {
  return parseByType<SheetResponse>(sheetResponses, message);
}

// Between the sheet and the content script only: what the page in the tab asks for.
const pageNeeds = object({ host: hostName, kinds: arrayOf(contactKind, LIMITS.popupKinds) });
export type PageNeeds = Parsed<typeof pageNeeds>;
export const PAGE_NEEDS_QUERY = { type: "pageNeeds" } as const;

export function parsePageNeeds(message: unknown): PageNeeds | undefined {
  const parsed = pageNeeds(message);
  return parsed === INVALID ? undefined : parsed;
}

export function isContactKind(kind: string): kind is ContactKind {
  return CONTACT_KINDS.some((candidate) => candidate === kind);
}

export function isExtensionRequest(message: unknown): message is ExtensionRequest {
  return parseExtensionRequest(message) !== undefined;
}

export function isExtensionResponse(message: unknown): message is ExtensionResponse {
  return parseExtensionResponse(message) !== undefined;
}
