import { installCapture } from "./capture";
import { installContext } from "./context";
import type { ExtensionRequest } from "./messages";
import { isTrustedPage } from "./origin";

export interface PageEnvironment {
  doc: Document;
  win: Window;
  protocol: string;
  hostname: string;
  isSecureContext: boolean;
  isTopFrame: boolean;
  send: (request: ExtensionRequest) => Promise<unknown>;
}

// Runs in the top frame of secure pages only, so a network attacker on plain http or a
// frame from another site can't feed the card values or reorder it.
export function startPage(env: PageEnvironment): () => void {
  if (!env.isTopFrame || !env.isSecureContext || !isTrustedPage(env.protocol, env.hostname)) return () => undefined;
  const host = (): string => env.hostname;
  const send = (request: ExtensionRequest): void => {
    env.send(request).catch(() => undefined);
  };
  const stops = [installContext(env.doc, env.win, { host, send: env.send }), installCapture(env.doc, env.win, { host, send })];
  return () => {
    stops.forEach((stop) => {
      stop();
    });
  };
}
