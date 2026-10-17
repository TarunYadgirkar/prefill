import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { classify } from "./classify";
import { fillForm } from "./fill";
import { fitPhones } from "./fillFit";
import { reply, type Person } from "./heldoutHost";
import type { ExtensionRequest } from "./messages";
import alex from "./fixtures/heldout/alex.json";
import oracleJpmc from "./fixtures/ats-oracle-jpmc.html?raw";

// JPMorganChase's application on Oracle Cloud HCM: its address boxes are searchable lists whose
// options are grid cells, and picking a postal code fills the city, county and state.

const box = (id: string): HTMLInputElement => {
  const found = document.getElementById(id);
  if (!(found instanceof HTMLInputElement)) throw new Error(`no ${id}`);
  return found;
};

// Oracle's lists as the live page drew them for Alex's address.
const OPTIONS: Readonly<Record<string, readonly string[]>> = {
  city: ["Berkeley, Alameda, CA"],
  region2: ["CA", "AK", "AL"],
  postalCode: ["94704, Berkeley, Alameda, CA"],
};

// Draws the grid Oracle opens under a box once the person types or presses the down arrow.
function drawList(input: HTMLInputElement): void {
  const list = document.getElementById(input.getAttribute("aria-controls") ?? "");
  if (list === null) return;
  const typed = input.value.toLowerCase();
  const shown = (OPTIONS[input.name] ?? ["Not listed"]).filter((text) => text.toLowerCase().includes(typed));
  list.innerHTML = shown
    .map((text, index) => `<div role="row"><div role="gridcell" id="${input.id}-listitem-${String(index)}">${text}</div></div>`)
    .join("");
  for (const cell of list.querySelectorAll("[role=gridcell]"))
    cell.addEventListener("click", () => {
      input.value = cell.textContent;
    });
}

function addLists(): void {
  for (const input of document.querySelectorAll<HTMLInputElement>("input[role=combobox]")) {
    const id = input.getAttribute("aria-controls");
    if (id !== null && document.getElementById(id) === null)
      input.insertAdjacentHTML("afterend", `<div role="grid" id="${id}"></div>`);
    input.addEventListener("input", () => {
      drawList(input);
    });
    input.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown") drawList(input);
    });
  }
}

beforeEach(() => {
  document.body.innerHTML = oracleJpmc;
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 200, 30));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("JPMorganChase's Oracle application", () => {
  it("leaves the county, the third address line and the e-signature alone", () => {
    expect(classify(box("region1-32")).kind).toBe("ignored");
    expect(classify(box("addressLine3-29")).kind).toBe("ignored");
    expect(classify(box("region2-33"))).toMatchObject({ kind: "address", part: "state" });
    expect(classify(box("fullName-4")).kind).toBe("sensitive");
  });

  it("picks the city, state and postal code from Oracle's lists", async () => {
    addLists();
    const send = (request: ExtensionRequest): Promise<unknown> => Promise.resolve(reply(alex as Person, request));
    await fillForm(document, { host: () => "jpmc.fa.oraclecloud.com", send });
    expect(box("addressLine1-27").value).toBe("2400 Durant Ave");
    expect(box("addressLine3-29").value).toBe("");
    expect(box("city-30").value).toBe("Berkeley, Alameda, CA");
    expect(box("region2-33").value).toBe("CA");
    expect(box("postalCode-34").value).toBe("94704, Berkeley, Alameda, CA");
    expect(box("fullName-4").value).toBe("");
  });

  it("types a number saved without spaces into the national phone box without its +1", () => {
    const phone = document.querySelector<HTMLInputElement>('input[type="tel"]');
    if (phone === null) throw new Error("no phone box");
    expect(fitPhones(phone, [{ value: "+15105550134", detail: "" }])).toEqual([{ value: "5105550134", detail: "" }]);
  });
});
