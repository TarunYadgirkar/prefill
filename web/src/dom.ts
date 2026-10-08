import type { FieldElement } from "./fieldTypes";

const FIELD_TAGS: ReadonlySet<string> = new Set([
  "input",
  "select",
  "textarea",
]);
const FIELD_SELECTOR = "input, select, textarea";
const SKIPPED_TEXT: ReadonlySet<string> = new Set([
  "select",
  "option",
  "script",
  "style",
  "textarea",
  "input",
]);
const MAX_TEXT = 200;
// Smaller than this, a field is a honeypot or a tracking trick, not something a person types into.
const MIN_SIZE = 4;

export function isFieldElement(node: unknown): node is FieldElement {
  return (
    typeof node === "object" &&
    node !== null &&
    "localName" in node &&
    FIELD_TAGS.has(String(node.localName))
  );
}

// A field that already opens a list of its own: a datalist, or a page's combobox such as
// react-select or a places lookup. A second list on top would cover it and confuse it.
export function hasOwnList(el: Element): boolean {
  if (
    el.hasAttribute("list") ||
    el.getAttribute("role")?.toLowerCase() === "combobox"
  )
    return true;
  const autocomplete = el.getAttribute("aria-autocomplete")?.toLowerCase();
  return (
    autocomplete === "list" ||
    autocomplete === "both" ||
    el.getAttribute("aria-haspopup")?.toLowerCase() === "listbox"
  );
}

// The element an event really started on. Events from inside an open shadow root reach
// the document retargeted to the shadow host.
export function eventOrigin(event: Event): EventTarget | null {
  return event.composedPath()[0] ?? event.target;
}

function shadowRoots(root: ParentNode): ShadowRoot[] {
  return [...root.querySelectorAll("*")].flatMap((element) =>
    element.shadowRoot === null ? [] : [element.shadowRoot],
  );
}

// Fields in page order, including those inside open shadow roots, up to `limit`.
export function fieldElements(
  root: ParentNode,
  limit = Infinity,
): FieldElement[] {
  const own = [...root.querySelectorAll(FIELD_SELECTOR)]
    .filter(isFieldElement)
    .slice(0, limit);
  return shadowRoots(root).reduce<FieldElement[]>(
    (found, shadow) =>
      found.length >= limit
        ? found
        : [...found, ...fieldElements(shadow, limit - found.length)],
    own,
  );
}

// Whether added nodes could hold a field: one itself, one inside, or a shadow host.
export function mayHoldFields(node: Node): boolean {
  if (!(node instanceof Element)) return false;
  return (
    isFieldElement(node) ||
    node.shadowRoot !== null ||
    node.querySelector(FIELD_SELECTOR) !== null
  );
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

function labelledByText(el: Element): string {
  const ids = (el.getAttribute("aria-labelledby") ?? "")
    .split(/\s+/u)
    .filter(Boolean);
  // A detached element's root is the element itself, which can't look up ids.
  const root = el.getRootNode();
  if (!("getElementById" in root)) return "";
  const finder = root as Document | ShadowRoot;
  return ids
    .map((id) => {
      const found = finder.getElementById(id);
      return found === null ? "" : ownText(found);
    })
    .join(" ");
}

// Label text in the order browsers use: <label> elements, aria-labelledby, aria-label.
export function labelText(el: FieldElement): string {
  const labels = [...(el.labels ?? [])].map(ownText).join(" ");
  return squash(
    [labels, labelledByText(el), el.getAttribute("aria-label") ?? ""].join(" "),
  );
}

// How far up from a field to look for the words before it.
const NEARBY_LEVELS = 4;
const NEARBY_STOPS: ReadonlySet<string> = new Set(["form", "fieldset", "body", "html"]);

// The words just before an element when nothing labels it, the way Chromium infers a label:
// the nearest earlier sibling with text, at the element's level or a few levels up, as long
// as that sibling holds no field of its own ("<div>Question?</div><div><input></div>").
// The text of the nearest earlier sibling with any, or "" when a sibling holding a field
// comes first, since its words belong to that field.
function textBefore(node: Element): string | undefined {
  for (let sibling = node.previousElementSibling; sibling !== null; sibling = sibling.previousElementSibling) {
    if (FIELD_TAGS.has(sibling.localName) || sibling.querySelector(FIELD_SELECTOR) !== null) return "";
    const text = squash(ownText(sibling));
    if (text !== "") return text;
  }
  return undefined;
}

export function nearbyText(el: Element): string {
  let node: Element | null = el;
  for (let level = 0; node !== null && level < NEARBY_LEVELS; level += 1) {
    const text = textBefore(node);
    if (text !== undefined) return text;
    node = node.parentElement;
    if (node !== null && NEARBY_STOPS.has(node.localName)) return "";
  }
  return "";
}

// The last words before a node in page order: on a waiver, "By typing and signing your name
// you agree" before the name boxes.
function lastWordsBefore(node: Element): string {
  const walker = node.ownerDocument.createTreeWalker(node.ownerDocument.body, NodeFilter.SHOW_TEXT);
  walker.currentNode = node;
  for (let text = walker.previousNode(); text !== null; text = walker.previousNode()) {
    if (/\p{L}{3}/u.test(text.textContent ?? "")) return text.textContent ?? "";
  }
  return "";
}

// What a group of boxes is for, when a field is one part of it (a name in a first and a last
// box): the group's own label and the words just before it.
export function groupContext(el: Element): string {
  const group = el.parentElement?.closest("[role=group], fieldset");
  if (group === null || group === undefined) return "";
  const legend = group.localName === "fieldset" ? (group.querySelector("legend")?.textContent ?? "") : "";
  return squash([legend, labelledByText(group), group.getAttribute("aria-label") ?? "", lastWordsBefore(group)].join(" "));
}

// The field's label, or the words before it when the page didn't label it.
export function inferredLabel(el: FieldElement): string {
  return labelText(el) || nearbyText(el);
}

export function placeholderText(el: FieldElement): string {
  return squash(el.getAttribute("placeholder") ?? "");
}

// The field's name and id as written, plus each split at camelCase, digits and
// punctuation, so "billingAddressLine2" also reads as "billing address line 2".
export function nameTexts(el: FieldElement): string[] {
  return splitNames([el.getAttribute("name") ?? "", el.id].filter(Boolean));
}

export function splitNames(raw: readonly string[]): string[] {
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

// Clipping away the whole box is the usual way to hide something that still takes input.
function isClipped(el: Element): boolean {
  const style = el.ownerDocument.defaultView?.getComputedStyle(el);
  const clipPath = style?.getPropertyValue("clip-path") ?? "";
  return (
    (clipPath !== "" && clipPath !== "none") ||
    /^rect/u.test(style?.getPropertyValue("clip") ?? "")
  );
}

// aria-hidden only hides from screen readers, and some pages (Meta's job applications) wrap
// everything on screen in it, so it doesn't count here.
function isStyledVisible(el: Element): boolean {
  if (el.closest("[hidden]") || isClipped(el)) return false;
  return typeof el.checkVisibility === "function"
    ? el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })
    : true;
}

function isOnPage(rect: DOMRect, view: Window | null): boolean {
  return (
    rect.right + (view?.scrollX ?? 0) > 0 &&
    rect.bottom + (view?.scrollY ?? 0) > 0
  );
}

// Drawn at a usable size and not pushed off the page's top or left edge.
export function isRendered(el: Element): boolean {
  if (!isStyledVisible(el)) return false;
  const rect = el.getBoundingClientRect();
  return (
    rect.width >= MIN_SIZE &&
    rect.height >= MIN_SIZE &&
    isOnPage(rect, el.ownerDocument.defaultView)
  );
}

// Rendered and at least partly inside the layout viewport, as a field is while someone
// types in it. On iOS the window's inner size follows zoom, so the larger of the two counts.
export function isInView(el: Element): boolean {
  if (!isRendered(el)) return false;
  const rect = el.getBoundingClientRect();
  const { width, height } = viewportSize(el.ownerDocument);
  return (
    rect.right > 0 && rect.bottom > 0 && rect.left < width && rect.top < height
  );
}

function viewportSize(doc: Document): { width: number; height: number } {
  const view = doc.defaultView;
  return {
    width: Math.max(view?.innerWidth ?? 0, doc.documentElement.clientWidth),
    height: Math.max(view?.innerHeight ?? 0, doc.documentElement.clientHeight),
  };
}

export function fieldValue(el: FieldElement): string {
  if (el.localName === "select") {
    const select = el as HTMLSelectElement;
    return (select.selectedOptions[0]?.text ?? select.value).trim();
  }
  return el.value.trim();
}

// Puts a fixed element at a spot given in getBoundingClientRect's coordinates. While iPhone
// Safari pans the page above the keyboard, those differ from the ones `position: fixed`
// uses, so this measures where the element landed and moves it by the difference.
export function placeFixed(host: HTMLElement, left: number, top: number): void {
  const set = (x: number, y: number): void => {
    host.style.setProperty("left", `${String(x)}px`, "important");
    host.style.setProperty("top", `${String(y)}px`, "important");
  };
  set(left, top);
  const landed = host.getBoundingClientRect();
  if (landed.width === 0 && landed.height === 0) return;
  const dx = left - landed.left;
  const dy = top - landed.top;
  if (Math.abs(dx) >= 1 || Math.abs(dy) >= 1) set(left + dx, top + dy);
}

// The part of the window the keyboard leaves visible.
export function visibleHeight(win: Window): number {
  return win.visualViewport?.height ?? win.innerHeight;
}

// Runs `place` whenever the page scrolls, resizes or is panned for the keyboard. Returns the undo.
export function onViewportChange(win: Window, place: () => void): () => void {
  const visual = win.visualViewport;
  win.addEventListener("scroll", place, { capture: true, passive: true });
  win.addEventListener("resize", place, { passive: true });
  visual?.addEventListener("scroll", place);
  visual?.addEventListener("resize", place);
  return () => {
    win.removeEventListener("scroll", place, { capture: true });
    win.removeEventListener("resize", place);
    visual?.removeEventListener("scroll", place);
    visual?.removeEventListener("resize", place);
  };
}
