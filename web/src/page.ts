import { isAtsFrame } from "./atsFrames";
import { installCapture } from "./capture";
import { installContext } from "./context";
import { installCustom } from "./custom";
import { attachDatalist } from "./datalist";
import { showDropdown } from "./dropdown";
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
  // page. Chrome and Arc don't read the card, so there Prefill shows its own list of values.
  browser?: "safari" | "chromium";
}

type FrameFacts = Pick<PageEnvironment, "protocol" | "hostname" | "isSecureContext" | "isTopFrame">;

// Runs in the top frame of secure pages, and in a frame only when it shows one of the job
// application forms in atsFrames.ts over https, under that form's own host. So a network
// attacker on plain http or a frame from any other site can't feed the card values or
// reorder it.
export function isPrefillFrame(env: FrameFacts): boolean {
  if (!env.isSecureContext || !isTrustedPage(env.protocol, env.hostname)) return false;
  return env.isTopFrame || isAtsFrame(env.protocol, env.hostname);
}

export function startPage(env: PageEnvironment): () => void {
  if (!isPrefillFrame(env)) return () => undefined;
  const host = (): string => env.hostname;
  const send = (request: ExtensionRequest): void => {
    env.send(request).catch(() => undefined);
  };
  const isChromium = env.browser === "chromium";
  // Chrome mixes a datalist into its own autofill menu, doesn't open it when Tab brings
  // focus, never shows one on a text area, and leaves its values in the page for scripts to
  // read. So there every list is Prefill's own, in a closed shadow root.
  const shown = isChromium ? { attach: showDropdown } : {};
  // In Safari the card's order still follows the page, and values a minimal card left on
  // Prefill's contact come through a datalist for Safari's bar.
  const values = isChromium
    ? [installSuggestions(env.doc, { host, send: env.send })]
    : [
        installContext(env.doc, env.win, { host, send: env.send }),
        installSuggestions(env.doc, { host, send: env.send, attach: attachDatalist, offCard: true }),
      ];
  const stops = [
    ...values,
    installCapture(env.doc, env.win, { host, send }),
    installLinks(env.doc, { host, send: env.send, ...shown }),
    installCustom(env.doc, { host, send: env.send, ...shown, textAreas: isChromium }),
  ];
  return () => {
    stops.forEach((stop) => {
      stop();
    });
  };
}
