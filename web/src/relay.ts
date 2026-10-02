import { parseExtensionRequest, parseExtensionResponse, type ErrorResponse, type ExtensionRequest } from "./messages";
import { isTrustedPage } from "./origin";

export type SendNative = (message: unknown) => Promise<unknown>;

const badReply: ErrorResponse = { type: "error", reason: "unreadable reply" };

// The page's host, taken from what Safari says about the sender: this extension's own
// content script, in the top frame of a normal tab showing a secure page. Private
// Browsing tabs never reach the app, so nothing about them is kept. Anything Safari
// leaves out counts as a no.
function senderHost(sender: MessageSender, extensionId: string): string | undefined {
  if (sender.id !== extensionId || sender.frameId !== 0 || sender.tab?.incognito !== false) return undefined;
  try {
    const url = new URL(sender.url ?? "");
    return isTrustedPage(url.protocol, url.hostname) ? url.hostname : undefined;
  } catch {
    return undefined;
  }
}

function boundToSender(request: ExtensionRequest, host: string): ExtensionRequest {
  return request.type === "ping" ? request : { ...request, host };
}

// Only well-formed requests from this extension's pages reach the app, rebuilt from
// their known fields, and only well-formed replies reach the page.
export function relayToNative(
  message: unknown,
  sender: MessageSender,
  extensionId: string,
  sendNative: SendNative,
): Promise<unknown> | undefined {
  const host = senderHost(sender, extensionId);
  if (host === undefined) return undefined;
  const request = parseExtensionRequest(message);
  if (request === undefined) return undefined;
  return sendNative(boundToSender(request, host)).then((reply) => parseExtensionResponse(reply) ?? badReply);
}
