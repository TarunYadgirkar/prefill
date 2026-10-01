import type { FieldElement } from "./fieldTypes";

const FIELD_TAGS: ReadonlySet<string> = new Set(["input", "select", "textarea"]);
const SKIPPED_TEXT: ReadonlySet<string> = new Set(["select", "option", "script", "style", "textarea", "input"]);
const MAX_TEXT = 200;

// Tag names rather than instanceof, so elements from other frames and worlds still count.
export function isFieldElement(node: unknown): node is FieldElement {
  return node instanceof Object && "localName" in node && FIELD_TAGS.has(String(node.localName));
}

export function fieldElements(root: ParentNode): FieldElement[] {
  return [...root.querySelectorAll("input, select, textarea")].filter(isFieldElement);
}

function squash(text: string): string {
  return text.replace(/\s+/gu, " ").trim().slice(0, MAX_TEXT);
}

// A label's own words, without the text of a select or input nested inside it.
function ownText(node: Node): string {
  if (node.nodeType === Node.TEXT_NODE) return node.textContent ?? "";
  if (node instanceof Element && SKIPPED_TEXT.has(node.localName)) return "";
  return [...node.childNodes].map(ownText).join(" ");
}

function labelledByText(el: FieldElement): string {
  const ids = (el.getAttribute("aria-labelledby") ?? "").split(/\s+/u).filter(Boolean);
  const root = el.getRootNode() as Document | ShadowRoot;
  return ids.map((id) => (root.getElementById(id) ? ownText(root.getElementById(id) as Node) : "")).join(" ");
}

// Label text in the order browsers use: <label> elements, aria-labelledby, aria-label.
export function labelText(el: FieldElement): string {
  const labels = [...(el.labels ?? [])].map(ownText).join(" ");
  return squash([labels, labelledByText(el), el.getAttribute("aria-label") ?? ""].join(" "));
}

export function placeholderText(el: FieldElement): string {
  return squash(el.getAttribute("placeholder") ?? "");
}

// The field's name and id as written, plus each split at camelCase, digits and
// punctuation, so "billingAddressLine2" also reads as "billing address line 2".
export function nameTexts(el: FieldElement): string[] {
  const raw = [el.getAttribute("name") ?? "", el.id].filter(Boolean);
  const split = raw.map((text) =>
    text
      .replace(/([a-z])([A-Z])/gu, "$1 $2")
      .replace(/([A-Za-z])(\d)/gu, "$1 $2")
      .replace(/[_\-[\].]+/gu, " ")
      .toLowerCase()
      .trim(),
  );
  return [...new Set([...raw, ...split])];
}

export function isVisible(el: Element): boolean {
  if (el.closest("[hidden], [aria-hidden=true]")) return false;
  return typeof el.checkVisibility === "function"
    ? el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })
    : true;
}

export function fieldValue(el: FieldElement): string {
  if (el.localName === "select") {
    const select = el as HTMLSelectElement;
    return (select.selectedOptions[0]?.text ?? select.value).trim();
  }
  return el.value.trim();
}
