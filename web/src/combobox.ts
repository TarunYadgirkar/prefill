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

function press(input: HTMLInputElement, key: string): void {
  input.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
}

function click(element: HTMLElement): void {
  for (const type of ["mousedown", "mouseup", "click"])
    element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, button: 0 }));
}

// Opens the list (typing `search` first when given, which narrows long lists such as
// schools), picks the option `choose` points at, and returns what clears it again.
export async function fillCombobox(
  input: HTMLInputElement,
  choose: (options: readonly Option[]) => number,
  search?: string,
): Promise<(() => void) | undefined> {
  input.focus();
  if (search === undefined) press(input, "ArrowDown");
  else fillField(input, search);
  const elements = await waitForOptions(input);
  const options = elements.map((element) => ({ text: element.textContent.trim(), value: element.id }));
  const chosen = elements[choose(options)];
  if (chosen === undefined) {
    if (search !== undefined) fillField(input, "");
    press(input, "Escape");
    input.blur();
    return undefined;
  }
  click(chosen);
  input.blur();
  return () => {
    input.focus();
    press(input, "Backspace");
    input.blur();
  };
}
