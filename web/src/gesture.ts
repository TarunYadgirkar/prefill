import { eventOrigin, isInView } from "./dom";
import type { FieldElement } from "./fieldTypes";

// A page can focus a field from script, and the browser marks that focus as trusted too.
// So a field only gets a datalist of the person's values when they just clicked or tapped
// it (or its label) or pressed Tab, and it is on screen.
const GESTURE_MS = 1_000;

interface Gesture {
  target: EventTarget | null;
  key: string | undefined;
  at: number;
}

export interface GestureGate {
  allows: (element: FieldElement) => boolean;
  stop: () => void;
}

function isPointedAt(gesture: Gesture, element: FieldElement): boolean {
  const target = gesture.target;
  if (!(target instanceof Node)) return false;
  if (element.contains(target)) return true;
  const label = target instanceof Element ? target.closest("label") : null;
  return label?.control === element;
}

function follows(gesture: Gesture | undefined, element: FieldElement, now: number): boolean {
  if (gesture === undefined || now - gesture.at > GESTURE_MS) return false;
  return gesture.key === "Tab" || (gesture.key === undefined && isPointedAt(gesture, element));
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
  doc.addEventListener("pointerdown", record, true);
  doc.addEventListener("keydown", record, true);
  return {
    // A Tab press isn't tied to a field, so it lets one field through: a page that moves
    // focus from script after it can't collect a list on every field it focuses.
    allows: (element) => {
      if (!follows(last, element, now()) || !isInView(element)) return false;
      if (last?.key === "Tab") last = undefined;
      return true;
    },
    stop: () => {
      doc.removeEventListener("pointerdown", record, true);
      doc.removeEventListener("keydown", record, true);
    },
  };
}
