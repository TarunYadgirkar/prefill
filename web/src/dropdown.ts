import { eventOrigin, onViewportChange, placeFixed, visibleHeight } from "./dom";

export interface Choice {
  value: string;
  // A few words on what the value is or why it's offered ("Work email", "Used here").
  detail: string;
  // A guess is drawn apart from the person's own values. A note is a line of text, not a
  // value: it can't be picked and never reaches the field.
  tone?: "guess" | "note";
  // Runs when the person picks this value, after it's in the field.
  onPick?: () => void;
}

export type TextField = HTMLInputElement | HTMLTextAreaElement;
// Shows `choices` for `element` and returns what takes them away again.
export type Attach = (
  element: TextField,
  choices: readonly Choice[],
) => () => void;

const GAP = 4;

// Room the list leaves on each side of its field, and which side it tries first.
export interface Placement {
  above: number;
  below: number;
  preferAbove: boolean;
}
const UNDER_FIELD: Placement = { above: 0, below: 0, preferAbove: false };
// Safari draws its own suggestion bubble under a contact field and takes every tap in a
// band under the field, wider than the bubble it draws: in the simulator a tap 72 pt under
// the field went nowhere and one 122 pt under it reached the page. So there the list sits
// above the field, clear of the Fill form pill, and below only past that band.
export const SAFARI_CONTACT: Placement = { above: 44, below: 124, preferAbove: true };

// Where the list goes: on the preferred side when it fits, else the other side when that
// fits, else on the side with more room, cut to that room so it scrolls.
export function listSpot(
  field: DOMRect,
  height: number,
  room: number,
  placement: Placement,
): { top: number; maxHeight?: number } {
  const under = field.bottom + GAP + placement.below;
  const roomOver = field.top - GAP - placement.above;
  const roomUnder = room - under;
  if (placement.preferAbove && roomOver >= height) return { top: roomOver - height };
  if (roomUnder >= height) return { top: under };
  if (roomOver >= height) return { top: roomOver - height };
  return roomOver > roomUnder
    ? { top: Math.max(0, roomOver - Math.min(height, roomOver)), maxHeight: roomOver }
    : { top: under, maxHeight: Math.max(0, roomUnder) };
}
// Like Chrome's own popup, a click this soon after the list appears doesn't pick, so a page
// can't slip the list under a click meant for something else.
const EARLY_CLICK_MS = 500;
const MIN_WIDTH = 240;
const MAX_WIDTH = 420;

// Drawn to look like Chrome's own autofill popup, following the browser's light or dark look.
const STYLE = `
:host { all: initial; }
.menu {
  --surface: #ffffff; --text: #1f1f1f; --text-muted: #474747; --accent: #0b57d0; --hover: rgb(31 31 31 / 0.08); --divider: rgb(31 31 31 / 0.12);
  box-sizing: border-box; padding: 4px 0; border-radius: 8px; background: var(--surface); color: var(--text);
  font: 13px/20px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  box-shadow: 0 1px 3px rgb(0 0 0 / 0.3), 0 4px 8px 3px rgb(0 0 0 / 0.15);
  overflow: hidden; user-select: none; cursor: default;
}
@media (prefers-color-scheme: dark) {
  .menu { --surface: #282a2d; --text: #e3e3e3; --text-muted: #c4c7c5; --accent: #a8c7fa; --hover: rgb(227 227 227 / 0.08); --divider: rgb(227 227 227 / 0.12); }
}
.row { all: unset; box-sizing: border-box; display: grid; width: 100%; padding: 6px 16px; cursor: default; }
.row[aria-selected="true"], .row:hover { background: var(--hover); }
.value, .detail { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.detail { font-size: 12px; line-height: 16px; color: var(--text-muted); }
.guess .value { color: var(--text-muted); }
.guess .detail { color: var(--accent); }
.note { padding: 6px 16px; font-size: 12px; line-height: 16px; color: var(--text-muted); }
.footer { margin-top: 4px; padding: 6px 16px 2px; border-top: 1px solid var(--divider); font-size: 12px; line-height: 16px; color: var(--text-muted); }
`;

// Sets the value the way typing would, so pages built on React (Airtable) see the change:
// the element's own value setter, then input and change events.
export function fillField(element: TextField, value: string): void {
  const prototype =
    element.localName === "textarea"
      ? HTMLTextAreaElement.prototype
      : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(prototype, "value")?.set?.call(
    element,
    value,
  );
  element.dispatchEvent(
    new InputEvent("input", {
      bubbles: true,
      inputType: "insertReplacementText",
      data: value,
    }),
  );
  element.dispatchEvent(new Event("change", { bubbles: true }));
}

// A phone number reads the same whatever its spaces, dashes and brackets, and with or without
// a country code in front, so numbers are compared by their digits.
const PHONE_LIKE = /^[\d\s()+.-]+$/u;
const MIN_PHONE_DIGITS = 7;

function phoneDigits(text: string): string | undefined {
  const digits = text.replace(/\D/gu, "");
  return PHONE_LIKE.test(text) && digits.length >= MIN_PHONE_DIGITS ? digits : undefined;
}

function isSameValue(value: string, text: string): boolean {
  const typed = phoneDigits(text);
  const held = typed === undefined ? undefined : phoneDigits(value);
  if (typed === undefined || held === undefined) return value.toLowerCase() === text;
  return held.endsWith(typed) || typed.endsWith(held);
}

function fits(value: string, text: string): boolean {
  if (value.toLowerCase().includes(text)) return true;
  const digits = text.replace(/\D/gu, "");
  return PHONE_LIKE.test(text) && PHONE_LIKE.test(value) && digits !== "" && value.replace(/\D/gu, "").includes(digits);
}

// The choices that still fit what's in the field, or all of them while it's empty. A
// field that already holds one of them offers nothing.
export function matching(choices: readonly Choice[], typed: string): Choice[] {
  const text = typed.trim().toLowerCase();
  if (text === "") return [...choices];
  if (choices.some((choice) => isSameValue(choice.value, text))) return [];
  return choices.filter((choice) => fits(choice.value, text));
}

function setStyles(element: HTMLElement, styles: Record<string, string>): void {
  for (const [name, value] of Object.entries(styles))
    element.style.setProperty(name, value, "important");
}

// A button, not a plain element: iOS Safari sends a tap's click only to something it takes
// as clickable, as it does for the Fill form pill.
function rowFor(doc: Document, choice: Choice, index: number): HTMLElement {
  const row = doc.createElement("button");
  row.type = "button";
  row.tabIndex = -1;
  row.className = choice.tone === undefined ? "row" : `row ${choice.tone}`;
  row.setAttribute("role", "option");
  row.dataset.index = String(index);
  const value = doc.createElement("span");
  value.className = "value";
  value.textContent = choice.value;
  const detail = doc.createElement("span");
  detail.className = "detail";
  detail.textContent = choice.detail;
  row.append(value, detail);
  return row;
}

function noteFor(doc: Document, note: Choice): HTMLElement {
  const line = doc.createElement("div");
  line.className = "note";
  line.setAttribute("role", "note");
  line.textContent = note.value;
  return line;
}

// Prefill's own suggestion list for Chrome and Arc, under the focused field. It sits in
// the top layer inside a closed shadow root, so the page can neither cover nor read it,
// and only the person's own clicks and keys pick a value.
export function showDropdown(
  element: TextField,
  choices: readonly Choice[],
  isUserEvent = (event: Event) => event.isTrusted,
  placement: Placement = UNDER_FIELD,
): () => void {
  const doc = element.ownerDocument;
  const win = doc.defaultView ?? window;
  // Notes are read, not picked, so only the values take part in typing, arrows and Enter.
  const notes = choices.filter((choice) => choice.tone === "note");
  const values = choices.filter((choice) => choice.tone !== "note");
  const host = doc.createElement("prefill-suggestions");
  const root = host.attachShadow({ mode: "closed" });
  const style = doc.createElement("style");
  style.textContent = STYLE;
  const menu = doc.createElement("div");
  menu.className = "menu";
  menu.setAttribute("role", "listbox");
  root.append(style, menu);
  host.setAttribute("popover", "manual");
  // Page CSS can't hide, move or fade the list: inline !important beats it.
  setStyles(host, {
    all: "initial",
    display: "block",
    position: "fixed",
    margin: "0",
    padding: "0",
    border: "0",
    background: "transparent",
    overflow: "visible",
    inset: "auto",
    opacity: "1",
    visibility: "visible",
    transform: "none",
    filter: "none",
    "clip-path": "none",
    "pointer-events": "auto",
  });

  let shown: Choice[] = [];
  let isOpen = false;
  let selected = -1;
  let hidden = false;
  let shownAt = 0;
  // What the person typed. Only their own input narrows the list, so a page can't set the
  // field's value and watch the list's size to learn the card's values.
  let typed = "";

  const place = (): void => {
    const rect = element.getBoundingClientRect();
    const width = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, rect.width));
    setStyles(host, { width: `${String(width)}px` });
    menu.style.removeProperty("max-height");
    const spot = listSpot(rect, host.getBoundingClientRect().height, visibleHeight(win), placement);
    if (spot.maxHeight !== undefined) setStyles(menu, { "max-height": `${String(spot.maxHeight)}px`, "overflow-y": "auto" });
    placeFixed(host, Math.max(0, Math.min(rect.left, win.innerWidth - width)), spot.top);
  };

  const render = (): void => {
    const wasShown = shown.length > 0;
    shown = hidden ? [] : matching(values, typed);
    if (!wasShown && shown.length > 0) shownAt = Date.now();
    selected = Math.min(selected, shown.length - 1);
    isOpen = shown.length > 0 || (!hidden && notes.length > 0);
    const footer = doc.createElement("div");
    footer.className = "footer";
    footer.textContent = "Prefill";
    menu.replaceChildren(
      ...shown.map((choice, index) => rowFor(doc, choice, index)),
      ...notes.map((note) => noteFor(doc, note)),
      footer,
    );
    menu.querySelectorAll(".row").forEach((row, index) => {
      row.setAttribute("aria-selected", String(index === selected));
    });
    setStyles(host, { display: isOpen ? "block" : "none" });
    if (isOpen) place();
  };

  const pick = (index: number): void => {
    const choice = shown[index];
    if (choice === undefined) return;
    fillField(element, choice.value);
    choice.onPick?.();
    close();
  };

  const move = (step: number): void => {
    hidden = false;
    const count = matching(values, typed).length;
    if (count === 0) selected = -1;
    else if (selected < 0) selected = step < 0 ? count - 1 : 0;
    else selected = (selected + step + count) % count;
    render();
  };

  const canMove = (): boolean =>
    matching(values, typed).length > 0 &&
    (element.localName !== "textarea" || shown.length > 0);

  const close = (): void => {
    hidden = true;
    render();
  };

  // Each key's action, and whether the list used the key.
  const KEYS: Readonly<Record<string, () => boolean>> = {
    // Arrows open a closed list in a text box, but in a text area they only move through a
    // list already showing, so the caret can still move between lines.
    ArrowDown: () => {
      if (!canMove()) return false;
      move(1);
      return true;
    },
    ArrowUp: () => {
      if (!canMove()) return false;
      move(-1);
      return true;
    },
    Enter: () => {
      if (selected < 0 || shown.length === 0) return false;
      pick(selected);
      return true;
    },
    Escape: () => {
      if (!isOpen) return false;
      close();
      return true;
    },
  };

  const onKey = (event: KeyboardEvent): void => {
    if (
      !isUserEvent(event) ||
      eventOrigin(event) !== element ||
      event.isComposing
    )
      return;
    if (KEYS[event.key]?.() !== true) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  const onInput = (event: Event): void => {
    if (!isUserEvent(event)) return;
    typed = element.value;
    hidden = false;
    selected = -1;
    render();
  };

  // Keeps focus in the field while a row is pressed.
  const onMouseDown = (event: Event): void => {
    event.preventDefault();
  };

  const onClick = (event: MouseEvent): void => {
    const row = event
      .composedPath()
      .find(
        (node) => node instanceof HTMLElement && node.classList.contains("row"),
      );
    if (
      !isUserEvent(event) ||
      !(row instanceof HTMLElement) ||
      Date.now() - shownAt < EARLY_CLICK_MS
    )
      return;
    pick(Number(row.dataset.index));
  };

  menu.addEventListener("pointerdown", onMouseDown);
  menu.addEventListener("mousedown", onMouseDown);
  menu.addEventListener("click", onClick);
  win.addEventListener("keydown", onKey, true);
  const stopPlacing = onViewportChange(win, place);
  // Removing a focused field fires no focusout, so a page that swaps its form would
  // otherwise leave the list floating at the top left.
  const removal = new MutationObserver(() => {
    if (!element.isConnected) close();
  });
  removal.observe(doc.documentElement, { childList: true, subtree: true });
  element.addEventListener("input", onInput);
  doc.documentElement.append(host);
  if (typeof host.showPopover === "function") host.showPopover();
  render();

  return () => {
    win.removeEventListener("keydown", onKey, true);
    stopPlacing();
    removal.disconnect();
    element.removeEventListener("input", onInput);
    host.remove();
  };
}
