// Searchable dropdowns (Greenhouse's React-Select, Ashby's location box) load their options
// only when they open, so a saved page has none. This stands in for the page's script: the
// down arrow or typing opens a list of the options the expectations file gives, narrowed
// by what was typed, and a click on one chooses it, as React-Select does.

export interface FakeComboboxes {
  picked: ReadonlyMap<HTMLInputElement, string>;
  stop: () => void;
}

const listId = (index: number): string => `prefill-heldout-list-${String(index)}`;

export function fakeComboboxes(doc: Document, options: ReadonlyMap<HTMLInputElement, readonly string[]>): FakeComboboxes {
  const picked = new Map<HTMLInputElement, string>();
  const inputs = [...options.keys()];

  const close = (input: HTMLInputElement): void => {
    doc.getElementById(listId(inputs.indexOf(input)))?.remove();
  };

  const choose = (input: HTMLInputElement, text: string): void => {
    picked.set(input, text);
    doc.getElementById(`react-select-${input.id}-placeholder`)?.remove();
    close(input);
  };

  const open = (input: HTMLInputElement): void => {
    close(input);
    const typed = input.value.trim().toLowerCase();
    const shown = (options.get(input) ?? []).filter((text) => text.toLowerCase().includes(typed));
    const list = doc.createElement("div");
    list.id = listId(inputs.indexOf(input));
    list.setAttribute("role", "listbox");
    shown.forEach((text, index) => {
      const option = doc.createElement("div");
      option.setAttribute("role", "option");
      option.id = `${list.id}-option-${String(index)}`;
      option.textContent = text;
      option.addEventListener("click", () => {
        choose(input, text);
      });
      list.append(option);
    });
    input.setAttribute("aria-controls", list.id);
    input.after(list);
  };

  const target = (event: Event): HTMLInputElement | undefined => {
    return inputs.find((input) => input === event.target);
  };
  const onInput = (event: Event): void => {
    const input = target(event);
    if (input !== undefined) open(input);
  };
  const onKey = (event: Event): void => {
    const input = target(event);
    const key = (event as KeyboardEvent).key;
    if (input === undefined) return;
    if (key === "ArrowDown") open(input);
    if (key === "Escape") close(input);
  };
  doc.addEventListener("input", onInput, true);
  doc.addEventListener("keydown", onKey, true);
  return {
    picked,
    stop: () => {
      doc.removeEventListener("input", onInput, true);
      doc.removeEventListener("keydown", onKey, true);
    },
  };
}
