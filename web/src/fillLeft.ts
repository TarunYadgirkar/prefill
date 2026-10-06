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

// Where "need you" goes from `current`: the next field left after it in page order, or
// back to the first one.
export function nextLeft(left: readonly FieldElement[], current: Node | undefined): FieldElement | undefined {
  const others = left.filter((field) => field !== current);
  if (current === undefined) return others[0];
  return others.find((field) => byPageOrder(current, field) < 0) ?? others[0];
}
