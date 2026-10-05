import type { ContactKind, PopupKind, PopupRecent, PopupStateResult, PopupValue, SheetRequest } from "../messages";

export interface SheetView {
  host: string;
  kind: ContactKind;
  state: PopupStateResult | undefined;
  busy: boolean;
  note: string | undefined;
  // The page's one-tap fill: how many fields it can fill, and how many the last tap filled.
  fillable: number;
  filled: number | undefined;
}

export interface SheetActions {
  send: (request: SheetRequest) => void;
  showKind: (kind: ContactKind) => void;
  fill: () => void;
  undoFill: () => void;
}

const KIND_NAMES: Record<ContactKind, { tab: string; plural: string }> = {
  email: { tab: "Email", plural: "emails" },
  phone: { tab: "Phone", plural: "phone numbers" },
  address: { tab: "Address", plural: "addresses" },
};

type Child = Node | string | undefined;

function el(tag: string, className?: string, ...children: Child[]): HTMLElement {
  const node = document.createElement(tag);
  if (className !== undefined) node.className = className;
  node.append(...children.filter((child) => child !== undefined));
  return node;
}

function button(label: string, className: string, onTap: () => void, disabled: boolean): HTMLButtonElement {
  const node = el("button", className, label) as HTMLButtonElement;
  node.type = "button";
  node.disabled = disabled;
  node.addEventListener("click", onTap);
  return node;
}

const valueLines = (value: PopupValue): HTMLElement =>
  el("span", "lines", el("span", "caption", value.caption), el("span", "text", value.text));

// Safari's QuickType row: two slots, the label over the value, the first slot marked.
function bar(entry: PopupKind | undefined): HTMLElement {
  const slots = (entry?.values ?? []).slice(0, 2);
  const row = el("div", slots.length === 1 ? "bar alone" : "bar");
  row.setAttribute("role", "group");
  row.setAttribute("aria-label", "Safari suggests");
  if (slots.length === 0) row.append(el("span", "slot empty", "Nothing on your card yet"));
  slots.forEach((value, index) => {
    const slot = el("span", index === 0 ? "slot first" : "slot", valueLines(value));
    slot.style.setProperty("view-transition-name", `value-${value.id}`);
    row.append(slot);
  });
  return row;
}

function pinnedNote(entry: PopupKind, view: SheetView, actions: SheetActions): HTMLElement | undefined {
  if (entry.pinnedID === undefined || entry.pinnedID !== entry.values[0]?.id) return undefined;
  const unpin = (): void => {
    actions.send({ type: "unpin", host: view.host, kind: entry.kind });
  };
  return el("p", "pinned", "Picked for this site. ", button("Let Prefill choose", "link", unpin, view.busy));
}

function choices(entry: PopupKind, view: SheetView, actions: SheetActions): HTMLElement {
  const isOff = view.state?.status === "off";
  const rows = entry.values.slice(1).map((value) => {
    const pick = (): void => {
      actions.send({ type: "pin", host: view.host, kind: entry.kind, valueID: value.id });
    };
    const row = button("", "row choice", pick, view.busy || isOff);
    row.append(valueLines(value), el("span", "accessory", "Use here"));
    row.setAttribute("aria-label", `Use ${value.text} on this site`);
    row.style.setProperty("view-transition-name", `row-${value.id}`);
    return el("li", undefined, row);
  });
  const footnote = isOff
    ? "Reorder for each site is off in Prefill, so Safari offers the same order on every site."
    : `Tap one to put it first here. Then tap the ${KIND_NAMES[entry.kind].tab.toLowerCase()} field again.`;
  if (rows.length === 0) return el("section", "group", el("p", "footnote", `No other ${KIND_NAMES[entry.kind].plural} on your card.`));
  return el("section", "group", el("h2", undefined, "Other choices"), el("ul", "list", ...rows), el("p", "footnote", footnote));
}

function recentRow(item: PopupRecent, view: SheetView, actions: SheetActions): HTMLElement {
  const undo = (): void => {
    actions.send({ type: "undoCapture", host: view.host, valueID: item.value.id });
  };
  const accessory =
    item.state === "removed"
      ? el("span", "accessory quiet", "Removed")
      : button(item.state === "saved" ? "Undo" : "Dismiss", "link", undo, view.busy);
  const lines = valueLines(item.value);
  if (item.state === "waiting") lines.append(el("span", "caption", "Waiting for you to review"));
  return el("li", "row", lines, accessory);
}

function recent(view: SheetView, actions: SheetActions): HTMLElement | undefined {
  const items = view.state?.recent ?? [];
  if (items.length === 0) return undefined;
  const rows = items.map((item) => recentRow(item, view, actions));
  return el("section", "group", el("h2", undefined, "Saved from this site"), el("ul", "list", ...rows));
}

function muteSwitch(view: SheetView, actions: SheetActions): HTMLElement {
  const input = el("input") as HTMLInputElement;
  input.type = "checkbox";
  input.setAttribute("role", "switch");
  input.checked = view.state?.muted ?? false;
  input.disabled = view.busy;
  input.addEventListener("change", () => {
    actions.send({ type: "muteSite", host: view.host, muted: input.checked });
  });
  const row = el("label", "row", el("span", "text", "Don't save on this site"), input);
  const note = "Prefill won't add emails, phone numbers or addresses you type into forms here.";
  return el("section", "group", el("div", "list", row), el("p", "footnote", note));
}

function kindTabs(view: SheetView, kinds: ContactKind[], actions: SheetActions): HTMLElement | undefined {
  if (kinds.length < 2) return undefined;
  const tabs = kinds.map((kind) => {
    const tab = button(KIND_NAMES[kind].tab, "segment", () => {
      actions.showKind(kind);
    }, false);
    tab.setAttribute("role", "tab");
    tab.setAttribute("aria-selected", String(kind === view.kind));
    return tab;
  });
  const control = el("div", "segments", ...tabs);
  control.setAttribute("role", "tablist");
  return control;
}

// Like Safari's AutoFill Contact: one tap fills every empty field the page asks for.
function fillCard(view: SheetView, actions: SheetActions): HTMLElement | undefined {
  if (view.filled !== undefined) {
    const done = view.filled === 0 ? "Nothing left to fill on this page." : `Filled ${String(view.filled)} ${view.filled === 1 ? "field" : "fields"}.`;
    const undo = view.filled === 0 ? undefined : button("Undo", "link", actions.undoFill, view.busy);
    return el("section", "fill", el("p", "fill-done", done, undo === undefined ? undefined : " ", undo));
  }
  if (view.fillable === 0) return undefined;
  const label = `Fill ${String(view.fillable)} ${view.fillable === 1 ? "field" : "fields"}`;
  const fill = button(label, "fill-button", actions.fill, view.busy);
  const note = "Name, contact info, links and your saved answers. Demographic questions get “Decline”.";
  return el("section", "fill", fill, el("p", "footnote", note));
}

function problem(title: string, detail: string): HTMLElement {
  return el("section", "problem", el("h2", undefined, title), el("p", undefined, detail));
}

function body(view: SheetView, actions: SheetActions): Child[] {
  const state = view.state;
  if (state === undefined) return [bar(undefined), el("p", "footnote", "Checking your card…")];
  if (state.status === "notSetUp") return [problem("Finish setting up Prefill", "Open Prefill to choose your contact card.")];
  const entry = state.kinds.find((item) => item.kind === view.kind);
  if (entry === undefined) return [problem("Prefill couldn't read your card", state.reason ?? "Try again in a moment.")];
  const failure = state.status === "failed" ? el("p", "failure", state.reason ?? "Something went wrong. Try again.") : undefined;
  return [
    kindTabs(view, state.kinds.map((item) => item.kind), actions),
    bar(entry),
    pinnedNote(entry, view, actions),
    failure,
    choices(entry, view, actions),
    recent(view, actions),
    muteSwitch(view, actions),
  ];
}

export function render(root: HTMLElement, view: SheetView, actions: SheetActions): void {
  const header = el("header", "site", el("p", "eyebrow", "Safari will suggest on"), el("h1", undefined, view.host));
  const note = el("p", "note", view.note);
  note.setAttribute("role", "status");
  root.setAttribute("aria-busy", String(view.busy || view.state === undefined));
  // Filling goes through the page, so the button doesn't wait on the card's state.
  const children = [fillCard(view, actions), ...body(view, actions)].filter((child) => child !== undefined);
  root.replaceChildren(header, ...children, note);
}

export function renderProblem(root: HTMLElement, title: string, detail: string): void {
  root.replaceChildren(problem(title, detail));
}
