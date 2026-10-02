import { installCapture } from "./capture";
import { installContext } from "./context";
import type { ExtensionRequest } from "./messages";

export interface PageEnvironment {
  doc: Document;
  win: Window;
  protocol: string;
  hostname: string;
  isSecureContext: boolean;
  send: (request: ExtensionRequest) => Promise<unknown>;
}

// Runs in the top frame of web pages only. Page context goes out from http and https
// pages, but capture, which can add to the card, needs a secure page, so a network
// attacker on plain http can't feed it values.
export function startPage(env: PageEnvironment): () => void {
  if (env.protocol !== "https:" && env.protocol !== "http:") return () => undefined;
  const host = (): string => env.hostname;
  const stops = [installContext(env.doc, env.win, { host, send: env.send })];
  if (env.isSecureContext) {
    const send = (request: ExtensionRequest): void => {
      env.send(request).catch(() => undefined);
    };
    stops.push(installCapture(env.doc, env.win, { host, send }));
  }
  return () => {
    stops.forEach((stop) => {
      stop();
    });
  };
}
