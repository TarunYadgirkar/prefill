import { buildCapture, type EditedField } from "./captureFields";
import { classify } from "./classify";
import { fieldValue, isFieldElement, isVisible } from "./dom";
import { isContact, type FieldElement } from "./fieldTypes";
import type { CaptureRequest } from "./messages";

export interface CaptureOptions {
  host: () => string;
  send: (request: CaptureRequest) => void;
  // Only edits the person made count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
}

const SUBMIT_CONTROLS = "button, input[type=submit], input[type=image]";

function submitButton(target: EventTarget | null): HTMLButtonElement | HTMLInputElement | undefined {
  if (!(target instanceof Element)) return undefined;
  const control = target.closest(SUBMIT_CONTROLS);
  if (control === null) return undefined;
  if (control.localName === "button" && (control as HTMLButtonElement).type !== "submit") return undefined;
  return control as HTMLButtonElement | HTMLInputElement;
}

function hasPassword(scope: ParentNode): boolean {
  return scope.querySelector("input[type=password]") !== null;
}

function inDocumentOrder(elements: readonly FieldElement[]): FieldElement[] {
  return [...elements].sort((first, second) =>
    first.compareDocumentPosition(second) & Node.DOCUMENT_POSITION_PRECEDING ? 1 : -1,
  );
}

// Watches what the person types into contact fields and reports it when a form is
// submitted, by a submit event or a click on its submit button, whichever comes first.
// Forms that post with fetch never submit, so whatever is left is reported when the
// page is hidden or unloaded. Sensitive fields are never read.
export function installCapture(doc: Document, win: Window, options: CaptureOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const edited = new Map<FieldElement, EditedField>();
  let lastSignature = "";

  const remember = (event: Event): void => {
    const target = event.target;
    if (!isUserEvent(event) || !isFieldElement(target)) return;
    const field = classify(target);
    if (!isContact(field)) return;
    // Visibility is judged when the person types: a multi-step form may hide the field
    // again before it submits.
    if (edited.has(target) || isVisible(target)) edited.set(target, { field, element: target, value: "" });
  };

  const report = (elements: readonly FieldElement[], scope: ParentNode): void => {
    const entries = inDocumentOrder(elements).flatMap((element) => {
      const entry = edited.get(element);
      edited.delete(element);
      return entry === undefined ? [] : [{ ...entry, value: fieldValue(element) }];
    });
    const request = buildCapture(options.host(), hasPassword(scope), entries);
    if (request === undefined) return;
    const signature = JSON.stringify(request);
    if (signature === lastSignature) return;
    lastSignature = signature;
    options.send(request);
  };

  const reportForm = (form: HTMLFormElement): void => {
    const members = [...form.elements].filter(isFieldElement);
    report(
      members.filter((element) => edited.has(element)),
      form,
    );
  };

  const onSubmit = (event: Event): void => {
    if (event.target instanceof HTMLFormElement) reportForm(event.target);
  };

  const onClick = (event: Event): void => {
    const button = submitButton(event.target);
    if (button === undefined) return;
    const form = button.form;
    if (form === null) {
      report([...edited.keys()], doc);
      return;
    }
    // The browser blocks an invalid form, so the submit that follows a fix is the real one.
    if (form.noValidate || form.checkValidity()) reportForm(form);
  };

  const flush = (): void => {
    report([...edited.keys()], doc);
  };

  const onVisibility = (): void => {
    if (doc.visibilityState === "hidden") flush();
  };

  doc.addEventListener("input", remember, true);
  doc.addEventListener("change", remember, true);
  doc.addEventListener("submit", onSubmit, true);
  doc.addEventListener("click", onClick, true);
  doc.addEventListener("visibilitychange", onVisibility, true);
  win.addEventListener("pagehide", flush, true);

  return () => {
    doc.removeEventListener("input", remember, true);
    doc.removeEventListener("change", remember, true);
    doc.removeEventListener("submit", onSubmit, true);
    doc.removeEventListener("click", onClick, true);
    doc.removeEventListener("visibilitychange", onVisibility, true);
    win.removeEventListener("pagehide", flush, true);
  };
}
