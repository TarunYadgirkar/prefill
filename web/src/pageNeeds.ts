import { contactFields } from "./context";
import {
  FILL_PAGE,
  isContactKind,
  PAGE_NEEDS_QUERY,
  UNDO_FILL,
  type ContactKind,
  type FillPageResult,
  type PageNeeds,
} from "./messages";
import { isTrustedPage } from "./origin";
import type { PageFill } from "./page";

export interface PageFacts {
  doc: Document;
  protocol: string;
  hostname: string;
  fill?: PageFill;
}

const isType = (message: unknown, type: string): boolean =>
  typeof message === "object" &&
  message !== null &&
  (message as { type?: unknown }).type === type;

const isQuery = (message: unknown): boolean => isType(message, PAGE_NEEDS_QUERY.type);

// Fills the form, or puts back the last fill, when Safari's Prefill sheet asks. Only this
// extension's own pages can ask: a page can't send runtime messages to its content script.
export function answerFill(
  message: unknown,
  sender: MessageSender,
  extensionId: string,
  page: PageFacts,
): Promise<FillPageResult> | undefined {
  const fill = page.fill;
  if (sender.id !== extensionId || fill === undefined || !isTrustedPage(page.protocol, page.hostname)) return undefined;
  if (isType(message, FILL_PAGE.type))
    return fill.fill().then((filled) => ({ type: "fillPageResult", filled }));
  if (!isType(message, UNDO_FILL.type)) return undefined;
  fill.undo();
  return Promise.resolve({ type: "fillPageResult", filled: 0 });
}

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
  const fillable = page.fill?.count();
  return Promise.resolve({
    host: page.hostname,
    kinds: [...kinds],
    ...(fillable === undefined ? {} : { fillable }),
  });
}
