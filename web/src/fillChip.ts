import { eventOrigin, isFieldElement } from "./dom";
import type { FieldElement } from "./fieldTypes";
import type { FillResult } from "./fill";
import type { GestureGate } from "./gesture";

// The one-tap button: when the person clicks or tabs into a field of a form Prefill can
// fill, a small pill above the field offers to fill the whole form, then to undo it. It
// sits in the top layer inside a closed shadow root, like Prefill's list, so the page can
// neither read it nor press it: only the person's own tap fills.

export interface FillChipOptions {
  gate: GestureGate;
  // How many empty fields Prefill could fill in the anchor's form.
  count: (anchor: FieldElement) => number;
  fill: (anchor: FieldElement) => Promise<FillResult>;
  isUserEvent?: (event: Event) => boolean;
  now?: () => number;
}

// Fewer fields than this aren't worth a button: the field's own list covers them.
const MIN_FIELDS = 3;
const GAP = 6;
// Like Prefill's list, a tap this soon after the pill appears doesn't count, so a page
// can't slip it under a tap meant for something else.
const EARLY_TAP_MS = 400;
const DONE_MS = 8_000;

const STYLE = `
:host { all: initial; }
.pill {
  --surface: rgb(255 255 255 / 0.96); --text: #1c1c1e; --muted: #6c6c70; --accent: #0068d6; --line: rgb(60 60 67 / 0.18);
  display: inline-flex; align-items: center; gap: 2px; padding: 3px; border-radius: 999px;
  background: var(--surface); color: var(--text); box-shadow: 0 1px 2px rgb(0 0 0 / 0.18), 0 6px 18px rgb(0 0 0 / 0.14);
  font: 13px/18px -apple-system, system-ui, "Segoe UI", Roboto, sans-serif; user-select: none; -webkit-user-select: none;
  -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px);
}
@media (prefers-color-scheme: dark) {
  .pill { --surface: rgb(44 44 46 / 0.96); --text: #f2f2f7; --muted: #aeaeb2; --accent: #0a84ff; --line: rgb(235 235 245 / 0.18); }
}
button { all: unset; cursor: pointer; border-radius: 999px; padding: 5px 12px; white-space: nowrap; }
button:hover { background: var(--line); }
button:focus-visible { outline: 2px solid var(--accent); }
.main { color: var(--accent); font-weight: 600; }
.main .count { color: var(--muted); font-weight: 400; margin-left: 4px; }
.close { color: var(--muted); padding: 5px 9px; }
.status { padding: 5px 4px 5px 12px; color: var(--text); white-space: nowrap; }
.sep { width: 1px; align-self: stretch; margin: 4px 0; background: var(--line); }
`;

type State = { name: "offer"; count: number } | { name: "busy" } | { name: "done"; result: FillResult };

function setStyles(element: HTMLElement, styles: Record<string, string>): void {
  for (const [name, value] of Object.entries(styles)) element.style.setProperty(name, value, "important");
}

export function installFillChip(doc: Document, win: Window, options: FillChipOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const now = options.now ?? (() => Date.now());
  const host = doc.createElement("prefill-fill");
  const root = host.attachShadow({ mode: "closed" });
  const style = doc.createElement("style");
  style.textContent = STYLE;
  const pill = doc.createElement("div");
  pill.className = "pill";
  pill.setAttribute("role", "toolbar");
  pill.setAttribute("aria-label", "Prefill");
  root.append(style, pill);
  host.setAttribute("popover", "manual");
  setStyles(host, { position: "fixed", margin: "0", padding: "0", border: "0", background: "transparent", inset: "auto", "z-index": "2147483647", overflow: "visible" });

  let anchor: FieldElement | undefined;
  let state: State | undefined;
  let shownAt = 0;
  let dismissed = false;
  let doneTimer: ReturnType<typeof setTimeout> | undefined;

  // Beside the field where the page leaves room, as on a desktop form; above it on a phone,
  // where fields span the screen and the keyboard and lists take the space below.
  const place = (): void => {
    if (anchor === undefined) return;
    const rect = anchor.getBoundingClientRect();
    const size = host.getBoundingClientRect();
    const height = size.height || 32;
    const width = size.width || 160;
    if (rect.right + GAP + width <= win.innerWidth) {
      setStyles(host, { left: `${String(rect.right + GAP)}px`, top: `${String(rect.top + (rect.height - height) / 2)}px` });
      return;
    }
    const above = rect.top - GAP - height >= 0;
    setStyles(host, {
      left: `${String(Math.max(4, Math.min(rect.right - width, win.innerWidth - width - 4)))}px`,
      top: `${String(above ? rect.top - GAP - height : rect.bottom + GAP)}px`,
    });
  };

  const hide = (): void => {
    clearTimeout(doneTimer);
    anchor = undefined;
    state = undefined;
    if (host.isConnected) {
      try {
        host.hidePopover();
      } catch {
        // Already hidden.
      }
      host.remove();
    }
  };

  const button = (className: string, label: string, action: string): HTMLButtonElement => {
    const node = doc.createElement("button");
    node.className = className;
    node.dataset.action = action;
    node.textContent = label;
    return node;
  };

  const render = (): void => {
    if (state === undefined) return;
    const separator = doc.createElement("span");
    separator.className = "sep";
    if (state.name === "offer") {
      const main = button("main", "Fill form", "fill");
      const count = doc.createElement("span");
      count.className = "count";
      count.textContent = `${String(state.count)} fields`;
      main.append(count);
      main.setAttribute("aria-label", `Fill ${String(state.count)} fields with Prefill`);
      const close = button("close", "✕", "dismiss");
      close.setAttribute("aria-label", "Not now");
      pill.replaceChildren(main, separator, close);
    } else if (state.name === "busy") {
      const status = doc.createElement("span");
      status.className = "status";
      status.textContent = "Filling…";
      pill.replaceChildren(status);
    } else {
      const status = doc.createElement("span");
      status.className = "status";
      status.setAttribute("role", "status");
      const filled = state.result.filled;
      status.textContent = filled === 0 ? "Nothing to fill" : `Filled ${String(filled)}`;
      pill.replaceChildren(status, ...(filled === 0 ? [] : [button("main", "Undo", "undo")]));
    }
    place();
  };

  const show = (field: FieldElement, count: number): void => {
    anchor = field;
    state = { name: "offer", count };
    if (!host.isConnected) doc.documentElement.append(host);
    try {
      host.showPopover();
    } catch {
      // Already showing, or popovers unsupported: the fixed position still shows it.
    }
    shownAt = now();
    render();
  };

  // A field the person just clicked or tabbed into, while the pill isn't busy or dismissed.
  const offeredField = (event: Event): FieldElement | undefined => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || target === anchor || dismissed || state?.name === "busy") return undefined;
    return options.gate.allows(target) ? target : undefined;
  };

  const onFocus = (event: Event): void => {
    const target = offeredField(event);
    if (target === undefined) return;
    const count = options.count(target);
    if (count < MIN_FIELDS) {
      if (state?.name !== "done") hide();
      return;
    }
    show(target, count);
  };

  // A click on the field that already has focus, after an undo or a dismissed list, brings
  // the pill back the way a fresh focus would.
  const onClickField = (event: Event): void => {
    if (anchor === undefined && eventOrigin(event) === doc.activeElement) onFocus(event);
  };

  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === anchor && state?.name === "offer") hide();
  };

  const runFill = async (field: FieldElement): Promise<void> => {
    state = { name: "busy" };
    render();
    const result = await options.fill(field).catch(() => ({ filled: 0, undo: () => undefined }));
    if (anchor !== field) return;
    state = { name: "done", result };
    render();
    doneTimer = setTimeout(hide, DONE_MS);
  };

  const actions: Readonly<Record<string, () => void>> = {
    fill: () => {
      if (anchor !== undefined) void runFill(anchor);
    },
    undo: () => {
      if (state?.name === "done") state.result.undo();
      hide();
    },
    dismiss: () => {
      dismissed = true;
      hide();
    },
  };

  // Keeps focus in the field while the pill is pressed.
  const onPointerDown = (event: Event): void => {
    event.preventDefault();
  };

  const onClick = (event: MouseEvent): void => {
    const target = event.composedPath().find((node) => node instanceof HTMLElement && node.dataset.action !== undefined);
    if (!isUserEvent(event) || !(target instanceof HTMLElement) || now() - shownAt < EARLY_TAP_MS) return;
    actions[target.dataset.action ?? ""]?.();
  };

  const onViewport = (): void => {
    if (anchor !== undefined) place();
  };

  pill.addEventListener("pointerdown", onPointerDown);
  pill.addEventListener("mousedown", onPointerDown);
  pill.addEventListener("click", onClick);
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("click", onClickField, true);
  doc.addEventListener("focusout", onBlur, true);
  win.addEventListener("scroll", onViewport, { capture: true, passive: true });
  win.addEventListener("resize", onViewport, { passive: true });
  return () => {
    hide();
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("click", onClickField, true);
    doc.removeEventListener("focusout", onBlur, true);
    win.removeEventListener("scroll", onViewport, true);
    win.removeEventListener("resize", onViewport);
  };
}
