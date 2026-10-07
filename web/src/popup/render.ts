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

function pinnedNote(entry: PopupKind, view: SheetView, actions: SheetActions): HTMLElement | undefined {
  if (entry.pinnedID === undefined || entry.pinnedID !== entry.values[0]?.id) return undefined;
  const unpin = (): void => {
    actions.send({ type: "unpin", host: view.host, kind: entry.kind });
  };
  return el("p", "pinned", "Picked for this site. ", button("Let Prefill choose", "link", unpin, view.busy));
}

// Every value of the kind, in the order Prefill's list under a field offers them here. The
// first is marked; tapping another puts it first on this site. The card itself never changes.
function choices(entry: PopupKind, view: SheetView, actions: SheetActions): HTMLElement {
  const plural = KIND_NAMES[entry.kind].plural;
  if (entry.values.length === 0) return el("section", "group", el("p", "footnote", `No ${plural} saved in Prefill yet.`));
  const isOff = view.state?.status === "off";
  const rows = entry.values.map((value, index) => {
    if (index === 0) {
      const first = el("div", "row first", valueLines(value), el("span", "accessory quiet", "First"));
      first.style.setProperty("view-transition-name", `row-${value.id}`);
      return el("li", undefined, first);
    }
    const pick = (): void => {
      actions.send({ type: "pin", host: view.host, kind: entry.kind, valueID: value.id });
    };
    const row = button("", "row choice", pick, view.busy || isOff);
    row.append(valueLines(value), el("span", "accessory", "Use here"));
    row.setAttribute("aria-label", `Use ${value.text} first on this site`);
    row.style.setProperty("view-transition-name", `row-${value.id}`);
    return el("li", undefined, row);
  });
  const footnote = isOff
    ? "“Put the value you used on a site first” is off in Prefill, so its list keeps one order on every site."
    : `Tap one to put it first in Prefill’s list on this site. Your contact card stays as it is.`;
  return el("section", "group", el("ul", "list", ...rows), el("p", "footnote", footnote));
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
  if (state === undefined) return [el("p", "footnote", "Checking your card…")];
  if (state.status === "notSetUp") return [problem("Finish setting up Prefill", "Open Prefill to choose your contact card.")];
  const entry = state.kinds.find((item) => item.kind === view.kind);
  if (entry === undefined) return [problem("Prefill couldn't read your card", state.reason ?? "Try again in a moment.")];
  const failure = state.status === "failed" ? el("p", "failure", state.reason ?? "Something went wrong. Try again.") : undefined;
  return [
    kindTabs(view, state.kinds.map((item) => item.kind), actions),
    pinnedNote(entry, view, actions),
    failure,
    choices(entry, view, actions),
    recent(view, actions),
    muteSwitch(view, actions),
  ];
}

export function render(root: HTMLElement, view: SheetView, actions: SheetActions): void {
  const header = el("header", "site", el("p", "eyebrow", "First on this site"), el("h1", undefined, view.host));
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
