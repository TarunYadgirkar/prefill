import { parseExtensionRequest, parseExtensionResponse, type ErrorResponse, type ExtensionRequest } from "./messages";

export type SendNative = (message: unknown) => Promise<unknown>;

const badReply: ErrorResponse = { type: "error", reason: "unreadable reply" };

function senderHost(sender: MessageSender): string | undefined {
  try {
    const url = new URL(sender.url ?? "");
    return url.protocol === "https:" || url.protocol === "http:" ? url.hostname : undefined;
  } catch {
    return undefined;
  }
}

// The host the browser says the message came from wins over the one the page reported.
function boundToSender(request: ExtensionRequest, sender: MessageSender): ExtensionRequest {
  const host = senderHost(sender);
  return request.type === "ping" || host === undefined ? request : { ...request, host };
}

// Only well-formed requests from this extension reach the app, rebuilt from their known
// fields, and only well-formed replies reach the page.
export function relayToNative(
  message: unknown,
  sender: MessageSender,
  extensionId: string,
  sendNative: SendNative,
): Promise<unknown> | undefined {
  if (sender.id !== undefined && sender.id !== extensionId) return undefined;
  const request = parseExtensionRequest(message);
  if (request === undefined) return undefined;
  return sendNative(boundToSender(request, sender)).then((reply) => parseExtensionResponse(reply) ?? badReply);
}
