import { classify } from "./classify";
import { fieldElements, isFieldElement } from "./dom";
import { isContact, type ContactField } from "./fieldTypes";
import type { PageContextRequest, PageField } from "./messages";

export interface ContextOptions {
  host: () => string;
  send: (request: PageContextRequest) => Promise<unknown>;
  debounceMs?: number;
}

const DEFAULT_DEBOUNCE_MS = 300;
const MAX_FIELDS = 40;

// Name fields never change the card's order, so they don't make a page worth reporting.
function pageField(field: ContactField): PageField | undefined {
  if (field.kind === "name") return undefined;
  return field.section === undefined ? { kind: field.kind } : { kind: field.kind, section: field.section };
}

export function contactFields(root: ParentNode): PageField[] {
  return fieldElements(root)
    .map(classify)
    .filter(isContact)
    .map(pageField)
    .filter((field) => field !== undefined)
    .slice(0, MAX_FIELDS);
}

function isRankedField(target: EventTarget | null): boolean {
  if (!isFieldElement(target)) return false;
  const classification = classify(target);
  return isContact(classification) && classification.kind !== "name";
}

// Sends one pageContext once the page has settled, so the app can reorder the card
// before the person taps a field. Focusing a contact field before any reply has come
// back sends it once more, in case the first message was lost or never sent.
export function installContext(doc: Document, options: ContextOptions): () => void {
  const debounceMs = options.debounceMs ?? DEFAULT_DEBOUNCE_MS;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let sent = false;
  let replied = false;
  let resentOnFocus = false;

  const send = (): void => {
    const fields = contactFields(doc);
    if (fields.length === 0) return;
    sent = true;
    observer.disconnect();
    options
      .send({ type: "pageContext", host: options.host(), fields })
      .then(() => {
        replied = true;
      })
      .catch(() => undefined);
  };

  const schedule = (): void => {
    clearTimeout(timer);
    timer = setTimeout(send, debounceMs);
  };

  const onFocus = (event: Event): void => {
    if (replied || resentOnFocus || !isRankedField(event.target)) return;
    resentOnFocus = true;
    clearTimeout(timer);
    send();
  };

  // Single-page apps render their forms after load, so keep looking until one is sent.
  const observer = new MutationObserver(() => {
    if (!sent) schedule();
  });

  const start = (): void => {
    observer.observe(doc.documentElement, { childList: true, subtree: true });
    schedule();
  };

  if (doc.readyState === "loading") doc.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
  doc.addEventListener("focusin", onFocus, true);

  return () => {
    clearTimeout(timer);
    observer.disconnect();
    doc.removeEventListener("DOMContentLoaded", start);
    doc.removeEventListener("focusin", onFocus, true);
  };
}
