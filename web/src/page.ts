import { installCapture } from "./capture";
import { installContext } from "./context";
import { installLinks } from "./links";
import type { ExtensionRequest } from "./messages";
import { isTrustedPage } from "./origin";
import { installSuggestions } from "./suggestions";

export interface PageEnvironment {
  doc: Document;
  win: Window;
  protocol: string;
  hostname: string;
  isSecureContext: boolean;
  isTopFrame: boolean;
  send: (request: ExtensionRequest) => Promise<unknown>;
  // Safari fills contact fields from the card, so there Prefill reorders the card for the
  // page. Chrome and Arc don't read the card, so there the values go into a datalist.
  browser?: "safari" | "chromium";
}

// Runs in the top frame of secure pages only, so a network attacker on plain http or a
// frame from another site can't feed the card values or reorder it.
export function startPage(env: PageEnvironment): () => void {
  if (!env.isTopFrame || !env.isSecureContext || !isTrustedPage(env.protocol, env.hostname)) return () => undefined;
  const host = (): string => env.hostname;
  const send = (request: ExtensionRequest): void => {
    env.send(request).catch(() => undefined);
  };
  const values =
    env.browser === "chromium"
      ? installSuggestions(env.doc, { host, send: env.send })
      : installContext(env.doc, env.win, { host, send: env.send });
  const stops = [values, installCapture(env.doc, env.win, { host, send }), installLinks(env.doc, { host, send: env.send })];
  return () => {
    stops.forEach((stop) => {
      stop();
    });
  };
}
