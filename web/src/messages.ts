// Wire format shared with Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift
// and described in docs/messages.md. Field names must stay identical on both sides;
// docs/message-examples.json is checked by tests in both languages.

export const FIELD_KINDS = ["email", "phone", "address", "name"] as const;
export const SECTION_HINTS = ["home", "work", "shipping", "billing"] as const;
export const SYNC_STATUSES = ["unchanged", "saved", "failed", "off"] as const;

export type FieldKind = (typeof FIELD_KINDS)[number];
export type SectionHint = (typeof SECTION_HINTS)[number];
export type SyncStatus = (typeof SYNC_STATUSES)[number];

export interface PostalAddress {
  street: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
}

export interface Ping {
  type: "ping";
}

export interface PageField {
  kind: FieldKind;
  section?: SectionHint;
}

export interface PageContextRequest {
  type: "pageContext";
  host: string;
  fields: PageField[];
}

export interface CapturedField {
  kind: FieldKind;
  value?: string;
  address?: PostalAddress;
  autocomplete?: string;
  name?: string;
  label?: string;
  section?: SectionHint;
}

export interface CaptureRequest {
  type: "capture";
  host: string;
  hasPassword: boolean;
  fields: CapturedField[];
}

export type ExtensionRequest = Ping | PageContextRequest | CaptureRequest;

export interface Pong {
  type: "pong";
}

export interface PageContextResult {
  type: "pageContextResult";
  status: SyncStatus;
  reason?: string;
}

export interface CaptureResult {
  type: "captureResult";
  saved: number;
  review: number;
  ignored: number;
}

export interface ErrorResponse {
  type: "error";
  reason: string;
}

export type ExtensionResponse = Pong | PageContextResult | CaptureResult | ErrorResponse;

type Check = (value: unknown) => boolean;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const string: Check = (value) => typeof value === "string";
const boolean: Check = (value) => typeof value === "boolean";
const count: Check = (value) => Number.isInteger(value) && (value as number) >= 0;
const literal =
  (expected: string): Check =>
  (value) =>
    value === expected;
const oneOf =
  (allowed: readonly string[]): Check =>
  (value) =>
    typeof value === "string" && allowed.includes(value);
const optional =
  (check: Check): Check =>
  (value) =>
    value === undefined || check(value);
const arrayOf =
  (check: Check): Check =>
  (value) =>
    Array.isArray(value) && value.every(check);
const shape =
  (checks: Record<string, Check>): Check =>
  (value) =>
    isRecord(value) && Object.entries(checks).every(([key, check]) => check(value[key]));

const fieldKind = oneOf(FIELD_KINDS);
const section = optional(oneOf(SECTION_HINTS));

const postalAddress = shape({ street: string, city: string, state: string, postalCode: string, country: string });

const requestChecks: Record<ExtensionRequest["type"], Check> = {
  ping: shape({ type: literal("ping") }),
  pageContext: shape({
    type: literal("pageContext"),
    host: string,
    fields: arrayOf(shape({ kind: fieldKind, section })),
  }),
  capture: shape({
    type: literal("capture"),
    host: string,
    hasPassword: boolean,
    fields: arrayOf(
      shape({
        kind: fieldKind,
        value: optional(string),
        address: optional(postalAddress),
        autocomplete: optional(string),
        name: optional(string),
        label: optional(string),
        section,
      }),
    ),
  }),
};

const responseChecks: Record<ExtensionResponse["type"], Check> = {
  pong: shape({ type: literal("pong") }),
  pageContextResult: shape({
    type: literal("pageContextResult"),
    status: oneOf(SYNC_STATUSES),
    reason: optional(string),
  }),
  captureResult: shape({ type: literal("captureResult"), saved: count, review: count, ignored: count }),
  error: shape({ type: literal("error"), reason: string }),
};

function matches(checks: Record<string, Check>, message: unknown): boolean {
  if (!isRecord(message) || typeof message.type !== "string") return false;
  const check = Object.hasOwn(checks, message.type) ? checks[message.type] : undefined;
  return check?.(message) ?? false;
}

export function isExtensionRequest(message: unknown): message is ExtensionRequest {
  return matches(requestChecks, message);
}

export function isExtensionResponse(message: unknown): message is ExtensionResponse {
  return matches(responseChecks, message);
}
