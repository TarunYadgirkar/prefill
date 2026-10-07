import { eventOrigin, isInView } from "./dom";
import type { FieldElement } from "./fieldTypes";

// A page can focus a field from script, and the browser marks that focus as trusted too.
// So a field only gets a list of the person's values when they just clicked or tapped
// it (or its label) or pressed Tab, and it is on screen.
const GESTURE_MS = 1_000;

interface Gesture {
  target: EventTarget | null;
  key: string | undefined;
  at: number;
  // The first field focused after a Tab: the only one that Tab lets through.
  focused?: EventTarget | null;
}

export interface GestureGate {
  allows: (element: FieldElement) => boolean;
  // Lets exactly this field through once, for focus Prefill's own button moved there on the
  // person's click. Only the Fill form pill calls it, from its closed shadow root.
  allowNext: (element: FieldElement) => void;
  stop: () => void;
}

// Shared by every gate on the page, since each of Prefill's lists keeps its own. A grant
// lets one check through, and ends unused when its field loses focus, another field takes
// focus, or a second has passed.
interface Grant {
  element: FieldElement;
  at: number;
}
const grants = new WeakMap<Document, Grant>();

function isGranted(doc: Document, element: FieldElement, now: number): boolean {
  const grant = grants.get(doc);
  return grant?.element === element && now - grant.at <= GESTURE_MS && isInView(element);
}

function isPointedAt(gesture: Gesture, element: FieldElement): boolean {
  const target = gesture.target;
  if (!(target instanceof Node)) return false;
  if (element.contains(target)) return true;
  const label = target instanceof Element ? target.closest("label") : null;
  return label?.control === element;
}

function follows(
  gesture: Gesture | undefined,
  element: FieldElement,
  now: number,
): boolean {
  if (gesture === undefined || now - gesture.at > GESTURE_MS) return false;
  if (gesture.key === "Tab")
    return gesture.focused === undefined || gesture.focused === element;
  return gesture.key === undefined && isPointedAt(gesture, element);
}

export function trackGestures(
  doc: Document,
  isUserEvent: (event: Event) => boolean,
  now: () => number = () => Date.now(),
): GestureGate {
  let last: Gesture | undefined;
  const record = (event: Event): void => {
    if (!isUserEvent(event)) return;
    const key = event instanceof KeyboardEvent ? event.key : undefined;
    last = { target: eventOrigin(event), key, at: now() };
  };
  // A Tab press isn't tied to a field, so it lets through only the first field focused
  // after it: a page that moves focus from script can't collect a list on every field it
  // focuses, whichever of Prefill's lists asks first.
  const bind = (event: Event): void => {
    if (grants.get(doc)?.element !== eventOrigin(event)) grants.delete(doc);
    if (last?.key === "Tab" && last.focused === undefined)
      last.focused = eventOrigin(event);
  };
  const leave = (event: Event): void => {
    if (grants.get(doc)?.element === eventOrigin(event)) grants.delete(doc);
  };
  doc.addEventListener("pointerdown", record, true);
  doc.addEventListener("keydown", record, true);
  doc.addEventListener("focusin", bind, true);
  doc.addEventListener("focusout", leave, true);
  return {
    allows: (element) => {
      if (isGranted(doc, element, now())) {
        grants.delete(doc);
        return true;
      }
      if (!follows(last, element, now()) || !isInView(element)) return false;
      if (last?.key === "Tab") last.focused = element;
      return true;
    },
    allowNext: (element) => {
      grants.set(doc, { element, at: now() });
    },
    stop: () => {
      doc.removeEventListener("pointerdown", record, true);
      doc.removeEventListener("keydown", record, true);
      doc.removeEventListener("focusin", bind, true);
      doc.removeEventListener("focusout", leave, true);
    },
  };
}

// Calls `show` when the person empties a field they tapped or tabbed into without leaving
// it, such as after deleting what Safari's AutoFill put there, so its list comes back.
// `armed` is the field whose focus passed the gesture gate.
export function onEmptied(
  doc: Document,
  isUserEvent: (event: Event) => boolean,
  armed: () => FieldElement | undefined,
  show: (element: FieldElement) => void,
): () => void {
  const onInput = (event: Event): void => {
    const target = eventOrigin(event);
    if (!isUserEvent(event) || target === null || target !== armed()) return;
    if ((target as HTMLInputElement).value === "") show(target as FieldElement);
  };
  doc.addEventListener("input", onInput, true);
  return () => {
    doc.removeEventListener("input", onInput, true);
  };
}
