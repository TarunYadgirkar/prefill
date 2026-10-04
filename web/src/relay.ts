import {
  parsePageRequest,
  parsePageResponse,
  type ErrorResponse,
  type PageRequest,
  type PageResponse,
} from "./messages";
import { isTrustedPage } from "./origin";

export type SendNative = (message: unknown) => Promise<unknown>;
// Marks Prefill's row in Safari's page menu with the number of values waiting for review.
export type MarkForReview = (tabId: number, count: number) => void;

const badReply: ErrorResponse = { type: "error", reason: "unreadable reply" };

// The page's host, taken from what Safari says about the sender: this extension's own
// content script, in the top frame of a normal tab showing a secure page. Private
// Browsing tabs never reach the app, so nothing about them is kept. Anything Safari
// leaves out counts as a no.
function senderHost(
  sender: MessageSender,
  extensionId: string,
): string | undefined {
  if (
    sender.id !== extensionId ||
    sender.frameId !== 0 ||
    sender.tab?.incognito !== false
  )
    return undefined;
  try {
    const url = new URL(sender.url ?? "");
    return isTrustedPage(url.protocol, url.hostname) ? url.hostname : undefined;
  } catch {
    return undefined;
  }
}

function boundToSender(request: PageRequest, host: string): PageRequest {
  return request.type === "ping" ? request : { ...request, host };
}

// Values saved straight to the card leave no mark, since Undo in the sheet covers them.
function markIfWaiting(
  response: PageResponse,
  sender: MessageSender,
  mark: MarkForReview | undefined,
): void {
  const tabId = sender.tab?.id;
  if (
    response.type !== "captureResult" ||
    response.review === 0 ||
    tabId === undefined
  )
    return;
  mark?.(tabId, response.review);
}

// Only well-formed page requests from this extension's content script reach the app,
// rebuilt from their known fields, and only well-formed page replies come back. The
// sheet's requests, whose replies hold the person's values, are never relayed.
export function relayToNative(
  message: unknown,
  sender: MessageSender,
  extensionId: string,
  sendNative: SendNative,
  markForReview?: MarkForReview,
): Promise<unknown> | undefined {
  const host = senderHost(sender, extensionId);
  if (host === undefined) return undefined;
  const request = parsePageRequest(message);
  if (request === undefined) return undefined;
  return sendNative(boundToSender(request, host)).then((reply) => {
    const response = parsePageResponse(reply) ?? badReply;
    markIfWaiting(response, sender, markForReview);
    return response;
  });
}
