import { eventOrigin } from "./dom";

export interface Choice {
  value: string;
  // A few words on what the value is ("Phone", "LinkedIn"), shown under it.
  detail: string;
}

export type TextField = HTMLInputElement | HTMLTextAreaElement;
// Shows `choices` for `element` and returns what takes them away again.
export type Attach = (element: TextField, choices: readonly Choice[]) => () => void;

const GAP = 4;
// Like Chrome's own popup, a click this soon after the list appears doesn't pick, so a page
// can't slip the list under a click meant for something else.
const EARLY_CLICK_MS = 500;
const MIN_WIDTH = 240;
const MAX_WIDTH = 420;

// Drawn to look like Chrome's own autofill popup, following the browser's light or dark look.
const STYLE = `
:host { all: initial; }
.menu {
  --surface: #ffffff; --text: #1f1f1f; --text-muted: #474747; --hover: rgb(31 31 31 / 0.08); --divider: rgb(31 31 31 / 0.12);
  box-sizing: border-box; padding: 4px 0; border-radius: 8px; background: var(--surface); color: var(--text);
  font: 13px/20px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  box-shadow: 0 1px 3px rgb(0 0 0 / 0.3), 0 4px 8px 3px rgb(0 0 0 / 0.15);
  overflow: hidden; user-select: none; cursor: default;
}
@media (prefers-color-scheme: dark) {
  .menu { --surface: #282a2d; --text: #e3e3e3; --text-muted: #c4c7c5; --hover: rgb(227 227 227 / 0.08); --divider: rgb(227 227 227 / 0.12); }
}
.row { display: grid; padding: 6px 16px; }
.row[aria-selected="true"], .row:hover { background: var(--hover); }
.value, .detail { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.detail { font-size: 12px; line-height: 16px; color: var(--text-muted); }
.footer { margin-top: 4px; padding: 6px 16px 2px; border-top: 1px solid var(--divider); font-size: 12px; line-height: 16px; color: var(--text-muted); }
`;

// Sets the value the way typing would, so pages built on React (Airtable) see the change:
// the element's own value setter, then input and change events.
export function fillField(element: TextField, value: string): void {
  const prototype = element.localName === "textarea" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(prototype, "value")?.set?.call(element, value);
  element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText", data: value }));
  element.dispatchEvent(new Event("change", { bubbles: true }));
}

// The choices that still fit what's in the field, or all of them while it's empty. A
// field that already holds one of them offers nothing.
export function matching(choices: readonly Choice[], typed: string): Choice[] {
  const text = typed.trim().toLowerCase();
  if (text === "") return [...choices];
  if (choices.some((choice) => choice.value.toLowerCase() === text)) return [];
  return choices.filter((choice) => choice.value.toLowerCase().includes(text));
}

function setStyles(element: HTMLElement, styles: Record<string, string>): void {
  for (const [name, value] of Object.entries(styles)) element.style.setProperty(name, value, "important");
}

function rowFor(doc: Document, choice: Choice, index: number): HTMLElement {
  const row = doc.createElement("div");
  row.className = "row";
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

// Prefill's own suggestion list for Chrome and Arc, under the focused field. It sits in
// the top layer inside a closed shadow root, so the page can neither cover nor read it,
// and only the person's own clicks and keys pick a value.
export function showDropdown(element: TextField, choices: readonly Choice[], isUserEvent = (event: Event) => event.isTrusted): () => void {
  const doc = element.ownerDocument;
  const win = doc.defaultView ?? window;
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
  let selected = -1;
  let hidden = false;
  let shownAt = 0;
  // What the person typed. Only their own input narrows the list, so a page can't set the
  // field's value and watch the list's size to learn the card's values.
  let typed = "";

  const place = (): void => {
    const rect = element.getBoundingClientRect();
    const width = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, rect.width));
    const height = host.getBoundingClientRect().height;
    const below = rect.bottom + GAP + height <= win.innerHeight || rect.top - GAP - height < 0;
    setStyles(host, {
      left: `${String(Math.max(0, Math.min(rect.left, win.innerWidth - width)))}px`,
      top: `${String(below ? rect.bottom + GAP : rect.top - GAP - height)}px`,
      width: `${String(width)}px`,
    });
  };

  const render = (): void => {
    const wasShown = shown.length > 0;
    shown = hidden ? [] : matching(choices, typed);
    if (!wasShown && shown.length > 0) shownAt = Date.now();
    selected = Math.min(selected, shown.length - 1);
    const footer = doc.createElement("div");
    footer.className = "footer";
    footer.textContent = "Prefill";
    menu.replaceChildren(...shown.map((choice, index) => rowFor(doc, choice, index)), footer);
    menu.querySelectorAll(".row").forEach((row, index) => {
      row.setAttribute("aria-selected", String(index === selected));
    });
    setStyles(host, { display: shown.length === 0 ? "none" : "block" });
    if (shown.length > 0) place();
  };

  const pick = (index: number): void => {
    const choice = shown[index];
    if (choice === undefined) return;
    fillField(element, choice.value);
    close();
  };

  const move = (step: number): void => {
    hidden = false;
    const count = matching(choices, typed).length;
    selected = count === 0 ? -1 : (selected + step + count) % count;
    render();
  };

  const close = (): void => {
    hidden = true;
    render();
  };

  // Each key's action, and whether the list used the key.
  const KEYS: Readonly<Record<string, () => boolean>> = {
    ArrowDown: () => {
      move(1);
      return true;
    },
    ArrowUp: () => {
      move(-1);
      return true;
    },
    Enter: () => {
      if (selected < 0 || shown.length === 0) return false;
      pick(selected);
      return true;
    },
    Escape: () => {
      if (shown.length === 0) return false;
      close();
      return true;
    },
  };

  const onKey = (event: KeyboardEvent): void => {
    if (!isUserEvent(event) || eventOrigin(event) !== element || event.isComposing) return;
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
  const onMouseDown = (event: MouseEvent): void => {
    event.preventDefault();
  };

  const onClick = (event: MouseEvent): void => {
    const row = event.composedPath().find((node) => node instanceof HTMLElement && node.classList.contains("row"));
    if (!isUserEvent(event) || !(row instanceof HTMLElement) || Date.now() - shownAt < EARLY_CLICK_MS) return;
    pick(Number(row.dataset.index));
  };

  menu.addEventListener("mousedown", onMouseDown);
  menu.addEventListener("click", onClick);
  win.addEventListener("keydown", onKey, true);
  win.addEventListener("scroll", place, { capture: true, passive: true });
  win.addEventListener("resize", place, { passive: true });
  element.addEventListener("input", onInput);
  doc.documentElement.append(host);
  if (typeof host.showPopover === "function") host.showPopover();
  render();

  return () => {
    win.removeEventListener("keydown", onKey, true);
    win.removeEventListener("scroll", place, { capture: true });
    win.removeEventListener("resize", place);
    element.removeEventListener("input", onInput);
    host.remove();
  };
}
