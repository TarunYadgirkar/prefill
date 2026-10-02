import { classify } from "./classify";
import { eventOrigin, fieldElements, isFieldElement, mayHoldFields } from "./dom";
import { isContact, type ContactField } from "./fieldTypes";
import { LIMITS, parseExtensionResponse, type PageContextRequest, type PageField } from "./messages";

export interface ContextOptions {
  host: () => string;
  send: (request: PageContextRequest) => Promise<unknown>;
  debounceMs?: number;
  maxWaitMs?: number;
}

const DEFAULT_DEBOUNCE_MS = 300;
const DEFAULT_MAX_WAIT_MS = 1_000;
// Fields looked at per scan, and scans per page, so a page full of inputs that never
// holds a contact form costs a bounded amount of work.
const MAX_INSPECTED = 200;
const MAX_SCANS = 30;

// Name fields never change the card's order, so they don't make a page worth reporting.
function pageField(field: ContactField): PageField | undefined {
  if (field.kind === "name") return undefined;
  return field.section === undefined ? { kind: field.kind } : { kind: field.kind, section: field.section };
}

export function contactFields(root: ParentNode): PageField[] {
  const fields: PageField[] = [];
  for (const element of fieldElements(root, MAX_INSPECTED)) {
    const classification = classify(element);
    const field = isContact(classification) ? pageField(classification) : undefined;
    if (field !== undefined) fields.push(field);
    if (fields.length >= LIMITS.pageFields) break;
  }
  return fields;
}

function isRankedField(target: EventTarget | null): boolean {
  if (!isFieldElement(target)) return false;
  const classification = classify(target);
  return isContact(classification) && classification.kind !== "name";
}

const keyOf = (field: PageField): string => `${field.kind} ${field.section ?? ""}`;

function isAnswered(reply: unknown): boolean {
  const response = parseExtensionResponse(reply);
  return response !== undefined && response.type !== "error" && !("status" in response && response.status === "failed");
}

// Waits for `waitMs` of quiet, but never longer than `maxWaitMs` after the first call.
function debounce(run: () => void, waitMs: number, maxWaitMs: number) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let deadline: number | undefined;
  const cancel = (): void => {
    clearTimeout(timer);
    timer = undefined;
    deadline = undefined;
  };
  const schedule = (): void => {
    const now = Date.now();
    deadline ??= now + maxWaitMs;
    clearTimeout(timer);
    timer = setTimeout(
      () => {
        cancel();
        run();
      },
      Math.min(waitMs, deadline - now),
    );
  };
  return { schedule, cancel };
}

// Tells the app which kinds of contact fields the page has, so it can reorder the card
// before the person taps one. It reports once the page settles and again whenever a
// form with a new kind or section appears. The card's order is shared by every page and
// tab, so it also reports when the page comes back from the back-forward cache or into
// view, and on the first focus of a contact field after any of those.
export function installContext(doc: Document, win: Window, options: ContextOptions): () => void {
  let reported = new Set<string>();
  let focusResend = true;
  let scans = 0;

  const deliver = (fields: PageField[]): void => {
    reported = new Set([...reported, ...fields.map(keyOf)]);
    const retry = (): void => {
      focusResend = true;
    };
    options
      .send({ type: "pageContext", host: options.host(), fields })
      .then((reply) => {
        if (!isAnswered(reply)) retry();
      })
      .catch(retry);
  };

  const resend = (): void => {
    const fields = contactFields(doc);
    if (fields.length > 0) deliver(fields);
  };

  const scan = (): void => {
    scans += 1;
    if (scans >= MAX_SCANS) observer.disconnect();
    const fields = contactFields(doc);
    if (fields.some((field) => !reported.has(keyOf(field)))) deliver(fields);
  };

  const settle = debounce(scan, options.debounceMs ?? DEFAULT_DEBOUNCE_MS, options.maxWaitMs ?? DEFAULT_MAX_WAIT_MS);

  const observer = new MutationObserver((records) => {
    if (records.some((record) => [...record.addedNodes].some(mayHoldFields))) settle.schedule();
  });

  const onFocus = (event: Event): void => {
    if (!focusResend || !isRankedField(eventOrigin(event))) return;
    focusResend = false;
    settle.cancel();
    resend();
  };

  const onReturn = (): void => {
    focusResend = true;
    resend();
  };

  const onPageShow = (event: Event): void => {
    if ((event as PageTransitionEvent).persisted) onReturn();
  };

  const onVisibility = (): void => {
    if (doc.visibilityState === "visible") onReturn();
  };

  const start = (): void => {
    observer.observe(doc.documentElement, { childList: true, subtree: true });
    settle.schedule();
  };

  if (doc.readyState === "loading") doc.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("visibilitychange", onVisibility, true);
  win.addEventListener("pageshow", onPageShow, true);

  return () => {
    settle.cancel();
    observer.disconnect();
    doc.removeEventListener("DOMContentLoaded", start);
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("visibilitychange", onVisibility, true);
    win.removeEventListener("pageshow", onPageShow, true);
  };
}
