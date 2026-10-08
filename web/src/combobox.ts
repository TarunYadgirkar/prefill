import type { Option } from "./choices";
import { fillField } from "./dropdown";

// Searchable dropdowns built from a text box and a list that opens under it, like the
// React-Select boxes Greenhouse uses for every question with choices. There is no value to
// set: a person types or presses the down arrow, waits for the list, and clicks an option,
// so one-tap fill does the same.

const WAIT_MS = 1_500;
const POLL_MS = 50;

export function isCombobox(element: Element): boolean {
  if (element.localName !== "input") return false;
  const autocomplete = element.getAttribute("aria-autocomplete")?.toLowerCase();
  return element.getAttribute("role")?.toLowerCase() === "combobox" || autocomplete === "list" || autocomplete === "both";
}

// React-Select names its parts after the box: "react-select-<id>-placeholder", "-option-3".
function prefixOf(input: HTMLInputElement): string {
  return `react-select-${input.id}-`;
}

function root(input: HTMLInputElement): Document | ShadowRoot {
  const node = input.getRootNode();
  return node instanceof ShadowRoot ? node : input.ownerDocument;
}

// A box with nothing chosen still shows its placeholder; a chosen value replaces it.
export function isComboboxEmpty(input: HTMLInputElement): boolean {
  if (input.value.trim() !== "") return false;
  if (input.id === "") return true;
  return root(input).getElementById(`${prefixOf(input)}placeholder`) !== null;
}

function optionElements(input: HTMLInputElement): HTMLElement[] {
  const finder = root(input);
  const listId = input.getAttribute("aria-controls") ?? input.getAttribute("aria-owns");
  const list = listId === null ? null : finder.getElementById(listId);
  if (list !== null) return [...list.querySelectorAll<HTMLElement>("[role=option]")];
  if (input.id === "") return [];
  return [...finder.querySelectorAll<HTMLElement>(`[id^="${CSS.escape(prefixOf(input))}option-"]`)];
}

async function waitForOptions(input: HTMLInputElement): Promise<HTMLElement[]> {
  const start = Date.now();
  for (;;) {
    const options = optionElements(input);
    if (options.length > 0 || Date.now() - start > WAIT_MS) return options;
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

const CONTROL_DEPTH = 4;

// Whether the box still shows `text` as its one choice. React-Select draws the choice beside
// the input, a few levels up, and a multi-select's chips would hold more than that.
function shows(input: HTMLInputElement, text: string): boolean {
  if (isComboboxEmpty(input)) return false;
  let node: HTMLElement | null = input.parentElement;
  for (let depth = 0; node !== null && depth < CONTROL_DEPTH; depth += 1) {
    const shown = node.textContent.trim();
    if (shown !== "") return shown === text;
    node = node.parentElement;
  }
  return false;
}

function press(input: HTMLInputElement, key: string): void {
  input.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
}

function click(element: HTMLElement): void {
  for (const type of ["mousedown", "mouseup", "click"])
    element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, button: 0 }));
}

// Opens the list, typing `search` first when given, and returns the option `choose` points at.
async function openAndChoose(
  input: HTMLInputElement,
  choose: (options: readonly Option[]) => number,
  search?: string,
): Promise<HTMLElement | undefined> {
  if (search === undefined) press(input, "ArrowDown");
  else fillField(input, search);
  const elements = await waitForOptions(input);
  const options = elements.map((element) => ({ text: element.textContent.trim(), value: element.id }));
  return elements[choose(options)];
}

function close(input: HTMLInputElement, typed: boolean): void {
  if (typed) fillField(input, "");
  press(input, "Escape");
}

// Opens the list (typing `search` first when given, which narrows long lists such as
// schools), picks the option `choose` points at, and returns what clears it again. When the
// typed answer shows nothing that fits ("May 2027" in a month list), the whole list gets a look.
export async function fillCombobox(
  input: HTMLInputElement,
  choose: (options: readonly Option[]) => number,
  search?: string,
): Promise<(() => void) | undefined> {
  input.focus();
  let chosen = await openAndChoose(input, choose, search);
  if (chosen === undefined && search !== undefined) {
    close(input, true);
    chosen = await openAndChoose(input, choose);
  }
  if (chosen === undefined) {
    close(input, false);
    input.blur();
    return undefined;
  }
  const picked = chosen.textContent.trim();
  click(chosen);
  input.blur();
  return () => {
    // Backspace clears whatever the box holds, so only Prefill's own pick is taken back.
    if (!shows(input, picked)) return;
    input.focus();
    press(input, "Backspace");
    input.blur();
  };
}
