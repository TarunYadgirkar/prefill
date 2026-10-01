import { isExtensionRequest, isExtensionResponse, type ErrorResponse } from "./messages";

export type SendNative = (message: unknown) => Promise<unknown>;

const badReply: ErrorResponse = { type: "error", reason: "unreadable reply" };

// Only well-formed requests reach the app, and only well-formed replies reach the page.
export function relayToNative(message: unknown, sendNative: SendNative): Promise<unknown> | undefined {
  if (!isExtensionRequest(message)) return undefined;
  return sendNative(message).then((reply) => (isExtensionResponse(reply) ? reply : badReply));
}
