import { buildCapture, describeElement, type EditedField, type FieldDescription } from "./captureFields";
import { classify } from "./classify";
import { eventOrigin, fieldValue, isFieldElement, isInView, isRendered } from "./dom";
import { isContact, type ContactField, type FieldElement } from "./fieldTypes";
import type { CaptureRequest } from "./messages";

export interface CaptureOptions {
  host: () => string;
  send: (request: CaptureRequest) => void;
  // Only events the browser made for the person count. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
}

interface Tracked {
  field: ContactField;
  description: FieldDescription;
  // The value as of the person's last edit, so a page that rewrites the field afterwards is caught.
  typed: string;
  // The person has left the field since their last edit.
  settled: boolean;
}

interface Trigger {
  submitted: boolean;
  // A real submit ends the form, so its fields are forgotten. A hidden page or a click
  // outside any form may come back, so they stay for the next report.
  consume: boolean;
}

const SUBMIT: Trigger = { submitted: true, consume: true };
const LOOSE_SUBMIT: Trigger = { submitted: true, consume: false };
const HIDDEN: Trigger = { submitted: false, consume: false };

const SUBMIT_CONTROLS = "button, input[type=submit], input[type=image]";
const SUBMIT_WORDS =
  /sign.?up|register|create|join|continue|next|submit|save|send|confirm|order|check.?out|pay|buy|subscribe|finish|done|get started/iu;
// How far up from a form-less button to look for the fields it would send.
const NEARBY_LEVELS = 4;

function submitControl(target: EventTarget | null): HTMLButtonElement | HTMLInputElement | undefined {
  if (!(target instanceof Element)) return undefined;
  const control = target.closest(SUBMIT_CONTROLS);
  if (control === null) return undefined;
  if (control.localName === "button" && (control as HTMLButtonElement).type !== "submit") return undefined;
  return control as HTMLButtonElement | HTMLInputElement;
}

function controlText(control: HTMLButtonElement | HTMLInputElement): string {
  return [control.textContent, control.getAttribute("aria-label"), control.getAttribute("value")].join(" ");
}

function isNear(control: Element, fields: readonly Element[]): boolean {
  let scope: Element | null = control.parentElement;
  for (let level = 0; scope !== null && level < NEARBY_LEVELS; level += 1) {
    const container = scope;
    if (fields.some((field) => container.contains(field))) return true;
    scope = scope.parentElement;
  }
  return false;
}

// A button outside any form submits nothing by itself, so it only counts when it says it
// submits and sits next to the fields the person typed in.
function isLooseSubmit(control: HTMLButtonElement | HTMLInputElement, fields: readonly Element[]): boolean {
  const says = control.getAttribute("type")?.toLowerCase() === "submit" || SUBMIT_WORDS.test(controlText(control));
  return says && isNear(control, fields);
}

function isValid(element: Element): boolean {
  const control = element as Partial<HTMLInputElement>;
  return control.willValidate !== true || control.validity?.valid !== false;
}

// Checks validity the way the browser will, without firing the page's invalid handlers.
function willSubmit(form: HTMLFormElement, control: HTMLButtonElement | HTMLInputElement): boolean {
  return form.noValidate || control.formNoValidate || [...form.elements].every(isValid);
}

// A visible password box that isn't a sign-in's current password marks a sign-up.
function hasNewPassword(scope: ParentNode): boolean {
  return [...scope.querySelectorAll("input[type=password]")].some(
    (input) => isRendered(input) && !/current-password/iu.test(input.getAttribute("autocomplete") ?? ""),
  );
}

function inDocumentOrder(elements: readonly FieldElement[]): FieldElement[] {
  return [...elements].sort((first, second) =>
    first.compareDocumentPosition(second) & Node.DOCUMENT_POSITION_PRECEDING ? 1 : -1,
  );
}

// Phone formatting may change spaces and dashes, never digits.
function sameValue(field: ContactField, typed: string, now: string): boolean {
  if (field.kind === "phone") return typed.replace(/\D/gu, "") === now.replace(/\D/gu, "");
  return typed.replace(/\s+/gu, " ").toLowerCase() === now.replace(/\s+/gu, " ").toLowerCase();
}

function reportable(element: FieldElement, entry: Tracked, trigger: Trigger): EditedField | undefined {
  const value = fieldValue(element);
  if (!sameValue(entry.field, entry.typed, value)) return undefined;
  if (!trigger.submitted && !entry.settled) return undefined;
  return { field: entry.field, description: entry.description, value };
}

// Watches what the person types into contact fields and reports it when a form is
// submitted, by a submit event or a click on its submit button, whichever comes first.
// Forms that post with fetch may never submit, so fields the person finished are also
// reported when the page is hidden; those reports never go straight onto the card.
// Sensitive fields are never read.
export function installCapture(doc: Document, win: Window, options: CaptureOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const edited = new Map<FieldElement, Tracked>();
  let lastSignature = "";

  const track = (target: FieldElement, settled: boolean): void => {
    const known = edited.get(target);
    if (known !== undefined) {
      edited.set(target, { ...known, typed: fieldValue(target), settled });
      return;
    }
    const field = classify(target);
    // Visibility is judged when the person types: a multi-step form may hide the field
    // again before it submits.
    if (!isContact(field) || !isInView(target)) return;
    edited.set(target, { field, description: describeElement(target), typed: fieldValue(target), settled });
  };

  const remember = (event: Event): void => {
    const target = eventOrigin(event);
    if (isUserEvent(event) && isFieldElement(target)) track(target, event.type === "change");
  };

  const report = (elements: readonly FieldElement[], scope: ParentNode, trigger: Trigger): void => {
    const entries = inDocumentOrder(elements).flatMap((element) => {
      const entry = edited.get(element);
      if (entry === undefined) return [];
      if (trigger.consume) edited.delete(element);
      return reportable(element, entry, trigger) ?? [];
    });
    const facts = { host: options.host(), hasPassword: hasNewPassword(scope), submitted: trigger.submitted };
    const request = buildCapture(facts, entries);
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
      SUBMIT,
    );
  };

  const onSubmit = (event: Event): void => {
    if (isUserEvent(event) && event.target instanceof HTMLFormElement) reportForm(event.target);
  };

  const onClick = (event: Event): void => {
    const control = isUserEvent(event) ? submitControl(eventOrigin(event)) : undefined;
    if (control === undefined) return;
    const form = control.form;
    const fields = [...edited.keys()];
    if (form === null) {
      if (isLooseSubmit(control, fields)) report(fields, doc, LOOSE_SUBMIT);
      return;
    }
    // The browser blocks an invalid form, so the submit that follows a fix is the real one.
    if (willSubmit(form, control)) reportForm(form);
  };

  const flush = (event: Event): void => {
    if (isUserEvent(event)) report([...edited.keys()], doc, HIDDEN);
  };

  const onVisibility = (event: Event): void => {
    if (doc.visibilityState === "hidden") flush(event);
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
