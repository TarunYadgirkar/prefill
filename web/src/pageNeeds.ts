import { contactFields } from "./context";
import {
  isContactKind,
  PAGE_NEEDS_QUERY,
  type ContactKind,
  type PageNeeds,
} from "./messages";
import { isTrustedPage } from "./origin";

export interface PageFacts {
  doc: Document;
  protocol: string;
  hostname: string;
}

const isQuery = (message: unknown): boolean =>
  typeof message === "object" &&
  message !== null &&
  (message as { type?: unknown }).type === PAGE_NEEDS_QUERY.type;

// Tells Safari's Prefill sheet which kinds of contact fields this page has, so the sheet
// only shows those. Only this extension can ask, and only on pages Prefill works on.
export function answerPageNeeds(
  message: unknown,
  sender: MessageSender,
  extensionId: string,
  page: PageFacts,
): Promise<PageNeeds> | undefined {
  if (
    sender.id !== extensionId ||
    !isQuery(message) ||
    !isTrustedPage(page.protocol, page.hostname)
  )
    return undefined;
  const kinds = new Set<ContactKind>();
  for (const field of contactFields(page.doc)) {
    if (isContactKind(field.kind)) kinds.add(field.kind);
  }
  return Promise.resolve({ host: page.hostname, kinds: [...kinds] });
}
