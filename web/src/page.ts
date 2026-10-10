import { installApplications } from "./applications";
import { isAtsFrame } from "./atsFrames";
import { installCapture } from "./capture";
import { classify } from "./classify";
import { installCustom } from "./custom";
import { SAFARI_CONTACT, showDropdown, type Attach } from "./dropdown";
import { isContact, type FieldElement } from "./fieldTypes";
import { fillableCount, fillForm, fillScope, findSlots, installFilledPicker, isFilled, noteFor, type FillResult } from "./fill";
import { installFillChip, MIN_FIELDS } from "./fillChip";
import { fieldsLeft } from "./fillLeft";
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
  // Prefill shows its own list in both. Safari's bar also offers the card's name and phone,
  // so there name fields get no second list.
  browser?: "safari" | "chromium";
  // Hands over the page's one-tap fill, for Safari's Prefill sheet.
  onFill?: (fill: PageFill) => void;
}

type FrameFacts = Pick<PageEnvironment, "protocol" | "hostname" | "isSecureContext" | "isTopFrame">;

// Runs in the top frame of secure pages, and in a frame only when it shows one of the job
// application forms in atsFrames.ts over https, under that form's own host. So a network
// attacker on plain http or a frame from any other site can't feed the card values.
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
  // bar shows only what the card holds, at most three values with no labels, so the field's
  // own list sits under it with every value, next to the Fill form pill. Prefill never
  // reorders the card for a page.
  const shown = { attach: showDropdown, skip: isFilled };
  const contactList = contactAttach(isChromium);
  const applications = installApplications(env.doc, env.win, { host, send });
  const stops = [
    applications.stop,
    installSuggestions(env.doc, { host, send: env.send, ...shown, attach: contactList, skipNames: !isChromium }),
    installCapture(env.doc, env.win, { host, send }),
    installLearn(env.doc, env.win, {
      host,
      send: env.send,
      onSubmitted: applications.record,
    }),
    installLinks(env.doc, { host, send: env.send, ...shown }),
    installCustom(env.doc, { host, send: env.send, ...shown, textAreas: true }),
  ];
  const fill = startFill(env, host, (element) => (isContact(classify(element)) ? contactList : showDropdown));
  return () => {
    [...stops, fill.stop].forEach((stop) => {
      stop();
    });
  };
}

// Safari's own bubble sits under a contact field and swallows taps there, filled or not.
function contactAttach(isChromium: boolean): Attach {
  return isChromium ? showDropdown : (element, choices) => showDropdown(element, choices, undefined, SAFARI_CONTACT);
}

// The pill's count for each form, kept until anything on the page changes a field (the
// person typing, a fill or its undo), so moving between fields doesn't ask the app each time.
function formCounts(doc: Document, ask: (scope: ParentNode) => Promise<number>) {
  const known = new Map<ParentNode, Promise<number>>();
  const forget = (): void => {
    known.clear();
  };
  doc.addEventListener("input", forget, true);
  doc.addEventListener("change", forget, true);
  return {
    count: (scope: ParentNode): Promise<number> => {
      const asked = known.get(scope) ?? ask(scope).catch(() => 0);
      known.set(scope, asked);
      return asked;
    },
    forget,
    stop: (): void => {
      doc.removeEventListener("input", forget, true);
      doc.removeEventListener("change", forget, true);
    },
  };
}

export interface PageFill {
  // How many empty fields a fill would fill in the form the person is in.
  count: () => Promise<number>;
  fill: () => Promise<number>;
  undo: () => void;
  stop: () => void;
}

// One-tap fill: the pill above a focused field and the sheet's Fill button fill the whole
// form, and a tap on a filled field offers the other values it could have used.
function startFill(env: PageEnvironment, host: () => string, attachFor: (element: FieldElement) => Attach): PageFill {
  const gate = trackGestures(env.doc, (event) => event.isTrusted);
  let last: FillResult | undefined;
  // Undo takes back every fill since the last undo, so a later run that filled nothing
  // can't hide the fields an earlier one filled.
  const counts = formCounts(env.doc, (scope) => fillableCount(scope, { host, send: env.send }));
  const run = async (anchor?: FieldElement): Promise<FillResult> => {
    const result = await fillForm(fillScope(env.doc, anchor), { host, send: env.send });
    counts.forget();
    if (result.filled === 0) return result;
    const earlier = last;
    last = {
      filled: result.filled + (earlier?.filled ?? 0),
      undo: () => {
        result.undo();
        earlier?.undo();
      },
    };
    return result;
  };
  // Asks the app only for a form big enough for the pill.
  const count = async (anchor?: FieldElement): Promise<number> => {
    const scope = fillScope(env.doc, anchor);
    return findSlots(scope).length < MIN_FIELDS ? 0 : counts.count(scope);
  };
  const stops = [
    installFillChip(env.doc, env.win, {
      gate,
      count,
      fill: run,
      left: (anchor) => fieldsLeft(fillScope(env.doc, anchor)),
      note: noteFor,
    }),
    installFilledPicker(env.doc, gate, undefined, attachFor),
  ];
  const page: PageFill = {
    count: () => counts.count(fillScope(env.doc)),
    fill: async () => (await run()).filled,
    undo: () => {
      last?.undo();
      last = undefined;
      counts.forget();
    },
    stop: () => {
      [...stops, counts.stop].forEach((stop) => {
        stop();
      });
      gate.stop();
    },
  };
  env.onFill?.(page);
  return page;
}
