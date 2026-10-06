import { isAtsFrame } from "./atsFrames";
import { installCapture } from "./capture";
import { installContext } from "./context";
import { installCustom } from "./custom";
import { SAFARI_CONTACT, showDropdown, type Attach } from "./dropdown";
import type { FieldElement } from "./fieldTypes";
import { fillForm, fillScope, findSlots, installFilledPicker, isFilled, type FillResult } from "./fill";
import { installFillChip } from "./fillChip";
import { trackGestures } from "./gesture";
import { installLearn } from "./learn";
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
  // Hands over the page's one-tap fill, for Safari's Prefill sheet.
  onFill?: (fill: PageFill) => void;
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
  // Every list is Prefill's own, in a closed shadow root, in Safari as in Chrome: Safari's
  // bar shows at most three values with no labels, and nothing once the card is minimal,
  // so the field's own list sits under it with every value, next to the Fill form pill.
  const shown = { attach: showDropdown, skip: isFilled };
  // Safari's own bubble sits under a contact field and swallows taps there.
  const contactList: Attach = isChromium
    ? showDropdown
    : (element, choices) => showDropdown(element, choices, undefined, SAFARI_CONTACT);
  // In Safari the card's order still follows the page.
  const values = [
    ...(isChromium ? [] : [installContext(env.doc, env.win, { host, send: env.send })]),
    installSuggestions(env.doc, { host, send: env.send, ...shown, attach: contactList }),
  ];
  const stops = [
    ...values,
    installCapture(env.doc, env.win, { host, send }),
    installLearn(env.doc, env.win, { host, send: env.send }),
    installLinks(env.doc, { host, send: env.send, ...shown }),
    installCustom(env.doc, { host, send: env.send, ...shown, textAreas: true }),
  ];
  const fill = startFill(env, host);
  return () => {
    [...stops, fill.stop].forEach((stop) => {
      stop();
    });
  };
}

export interface PageFill {
  // How many empty fields a fill would fill in the form the person is in.
  count: () => number;
  fill: () => Promise<number>;
  undo: () => void;
  stop: () => void;
}

// One-tap fill: the pill above a focused field and the sheet's Fill button fill the whole
// form, and a tap on a filled field offers the other values it could have used.
function startFill(env: PageEnvironment, host: () => string): PageFill {
  const gate = trackGestures(env.doc, (event) => event.isTrusted);
  let last: FillResult | undefined;
  const run = async (anchor?: FieldElement): Promise<FillResult> => {
    last = await fillForm(fillScope(env.doc, anchor), { host, send: env.send });
    return last;
  };
  const stops = [
    installFillChip(env.doc, env.win, {
      gate,
      count: (anchor) => findSlots(fillScope(env.doc, anchor)).length,
      fill: run,
    }),
    installFilledPicker(env.doc, gate),
  ];
  const page: PageFill = {
    count: () => findSlots(fillScope(env.doc)).length,
    fill: async () => (await run()).filled,
    undo: () => {
      last?.undo();
      last = undefined;
    },
    stop: () => {
      stops.forEach((stop) => {
        stop();
      });
      gate.stop();
    },
  };
  env.onFill?.(page);
  return page;
}
