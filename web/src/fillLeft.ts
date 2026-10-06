import { isInView } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { findSlots, slotField } from "./fill";

// What a fill leaves for the person: the fields of the form Prefill knows how to fill that
// are still empty, because it had no answer for them.

const byPageOrder = (a: Node, b: Node): number => {
  if (a === b) return 0;
  return (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0 ? -1 : 1;
};

export function fieldsLeft(scope: ParentNode): FieldElement[] {
  return findSlots(scope)
    .flatMap((slot) => slotField(slot) ?? [])
    .sort(byPageOrder);
}

// Whether the person can see the field: drawn, not hidden by style or clipping, in the
// viewport, and not covered by anything but itself or its label at its centre.
export function canSee(field: FieldElement): boolean {
  if (!isInView(field)) return false;
  const rect = field.getBoundingClientRect();
  const hit = field.ownerDocument.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
  if (hit === null) return false;
  return field.contains(hit) || [...(field.labels ?? [])].some((label) => label.contains(hit));
}

// Where "need you" goes from `current`: the next field left after it in page order the
// person can see once it's scrolled into view, wrapping round to the first. A field a page
// hides, covers or clips is skipped, so the pill never opens a list where nobody looks.
export function nextLeft(left: readonly FieldElement[], current: Node | undefined): FieldElement | undefined {
  const others = left.filter((field) => field !== current);
  const after = current === undefined ? 0 : others.findIndex((field) => byPageOrder(current, field) < 0);
  const start = after < 0 ? 0 : after;
  return [...others.slice(start), ...others.slice(0, start)].find((field) => {
    field.scrollIntoView({ block: "center" });
    return canSee(field);
  });
}
