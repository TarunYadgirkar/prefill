import { CONTACT_KINDS, type ContactKind, type PageNeeds, type PopupStateResult } from "../messages";
import { isTrustedPage } from "../origin";

export interface Site {
  host: string;
  kinds: ContactKind[];
  // Empty fields a one-tap fill would fill on the page.
  fillable: number;
}

export type Opening = { site: Site } | { problem: "private" | "unsupported" };

function trustedHost(url: string | undefined): string | undefined {
  try {
    const parsed = new URL(url ?? "");
    return isTrustedPage(parsed.protocol, parsed.hostname) ? parsed.hostname : undefined;
  } catch {
    return undefined;
  }
}

// The site comes from the tab's address when Safari shares it, otherwise from the page's
// own content script. The sheet only shows the kinds the page asks for, or every kind
// when the page has no contact fields.
export function openingFor(tab: Tab | undefined, needs: PageNeeds | undefined): Opening {
  if (tab?.incognito === true) return { problem: "private" };
  const host = tab?.url === undefined ? needs?.host : trustedHost(tab.url);
  if (host === undefined) return { problem: "unsupported" };
  return { site: { host, kinds: kindsAsked(needs), fillable: fillableIn(needs) } };
}

const fillableIn = (needs: PageNeeds | undefined): number => needs?.fillable ?? 0;

const kindsAsked = (needs: PageNeeds | undefined): ContactKind[] =>
  needs?.kinds.length ? needs.kinds : [...CONTACT_KINDS];

// A reply covers only the kinds it was asked about, so it replaces those and keeps the
// rest. A failed reply keeps what the sheet already shows next to its reason.
export function merge(current: PopupStateResult | undefined, reply: PopupStateResult): PopupStateResult {
  if (current === undefined) return reply;
  if (reply.status === "failed") return { ...current, status: reply.status, ...(reply.reason ? { reason: reply.reason } : {}) };
  const replaced = new Set(reply.kinds.map((entry) => entry.kind));
  const kinds = current.kinds.map((entry) => (replaced.has(entry.kind) ? reply.kinds.find((next) => next.kind === entry.kind) ?? entry : entry));
  const added = reply.kinds.filter((entry) => !current.kinds.some((known) => known.kind === entry.kind));
  return { ...reply, kinds: [...kinds, ...added] };
}
