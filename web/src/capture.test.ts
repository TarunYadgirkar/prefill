import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import formHtml from "../../testbed/form.html?raw";
import { installCapture } from "./capture";
import checkoutTagged from "./fixtures/checkout-tagged.html?raw";
import checkoutUntagged from "./fixtures/checkout-untagged.html?raw";
import gift from "./fixtures/gift.html?raw";
import signup from "./fixtures/signup.html?raw";
import type { CaptureRequest } from "./messages";

let uninstall: (() => void) | undefined;

const ON_SCREEN = new DOMRect(10, 10, 200, 30);
const OFF_SCREEN = new DOMRect(-10_000, 10, 200, 30);

beforeEach(() => {
  // happy-dom lays nothing out, so every element would measure 0 by 0.
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockImplementation(function (this: Element) {
    return this.hasAttribute("data-offscreen") ? OFF_SCREEN : ON_SCREEN;
  });
});

afterEach(() => {
  uninstall?.();
  uninstall = undefined;
  document.body.innerHTML = "";
  Reflect.deleteProperty(document, "visibilityState");
  vi.restoreAllMocks();
});

function setUp(
  html: string,
  isUserEvent: (event: Event) => boolean = () => true,
  hasActivation: () => boolean = () => true,
) {
  document.body.innerHTML = html;
  const send = vi.fn<(request: CaptureRequest) => void>();
  uninstall = installCapture(document, window, { host: () => "shop.example.net", send, isUserEvent, hasActivation });
  return send;
}

function element(selector: string): Element {
  const found = document.querySelector(selector);
  if (found === null) throw new Error(`no ${selector}`);
  return found;
}

function type(selector: string, value: string): void {
  const input = element(selector) as HTMLInputElement;
  input.value = value;
  input.dispatchEvent(new Event("input", { bubbles: true }));
}

// Typing, then leaving the field, as a person does before moving on.
function fill(selector: string, value: string): void {
  type(selector, value);
  element(selector).dispatchEvent(new Event("change", { bubbles: true }));
}

function choose(selector: string, value: string): void {
  const select = element(selector) as HTMLSelectElement;
  select.value = value;
  select.dispatchEvent(new Event("change", { bubbles: true }));
}

function click(selector: string): void {
  element(selector).dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
}

function submit(selector: string): void {
  element(selector).dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
}

function hide(): void {
  Object.defineProperty(document, "visibilityState", { value: "hidden", configurable: true });
  document.dispatchEvent(new Event("visibilitychange"));
  window.dispatchEvent(new Event("pagehide"));
}

function sentFields(send: ReturnType<typeof setUp>, call = 0) {
  return send.mock.calls[call]?.[0].fields ?? [];
}

describe("capture on sign-up", () => {
  it("sends the typed email and name once, never the password or code", () => {
    const send = setUp(signup);
    type("#fullName", "Alex Rivera");
    type("#signupEmail", "new.person@example.org");
    type("#pw", "correct horse battery");
    type("#code", "123456");
    click("#create");
    submit("form");
    hide();
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0]).toEqual({
      type: "capture",
      host: "shop.example.net",
      hasPassword: true,
      trigger: "submit",
      fields: [
        { kind: "name", value: "Alex Rivera", name: "fullName", label: "Full name", userTyped: true },
        {
          kind: "email",
          value: "new.person@example.org",
          autocomplete: "email",
          name: "email",
          label: "Email",
          userTyped: true,
        },
      ],
    });
  });

  it("ignores events the person didn't make", () => {
    const send = setUp(signup, (event) => event.isTrusted);
    type("#signupEmail", "new.person@example.org");
    click("#create");
    expect(send).not.toHaveBeenCalled();
  });

  it("sends nothing when the page script submits without the person tapping", () => {
    const send = setUp(signup, () => true, () => false);
    type("#signupEmail", "new.person@example.org");
    click("#create");
    submit("form");
    expect(send).not.toHaveBeenCalled();
  });

  it("skips a field the person can't edit", () => {
    const send = setUp(
      '<form><input type="email" name="a" readonly><input type="email" name="b" disabled><input type="email" name="c"><button>Go</button></form>',
    );
    type("[name=a]", "page@example.net");
    type("[name=b]", "page2@example.net");
    type("[name=c]", "new.person@example.org");
    click("button");
    expect(sentFields(send).map((field) => field.value)).toEqual(["new.person@example.org"]);
  });

  it("never reads a password box a show-password toggle turned into text", async () => {
    const send = setUp(
      '<form><input type="email" name="email"><input type="password" name="secret_box" id="pw"><button>Go</button></form>',
    );
    element("#pw").setAttribute("type", "email");
    await Promise.resolve();
    type("#pw", "hunter2@example.net");
    type("[name=email]", "new.person@example.org");
    click("button");
    expect(sentFields(send).map((field) => field.value)).toEqual(["new.person@example.org"]);
  });

  it("skips fields hidden from the person and fields left as the page filled them", () => {
    const send = setUp(signup);
    (element("#fullName") as HTMLInputElement).value = "Prefilled By Page";
    type("#hp", "bot@example.net");
    type("#signupEmail", "new.person@example.org");
    click("#create");
    expect(sentFields(send).map((field) => field.value)).toEqual(["new.person@example.org"]);
  });

  it.each([
    ['<input type="email" name="a" style="display:none">', "display none"],
    ['<input type="email" name="a" style="opacity:0">', "opacity 0"],
    ['<input type="email" name="a" style="visibility:hidden">', "visibility hidden"],
    ['<input type="email" name="a" data-offscreen>', "off the page"],
    ['<input type="email" name="a" style="clip-path: inset(50%)">', "clipped away"],
  ])("skips a field the person can't see: %s (%s)", (field) => {
    const send = setUp(`<form>${field}<input type="email" name="b"><button>Go</button></form>`);
    type("[name=a]", "planted@example.net");
    type("[name=b]", "new.person@example.org");
    click("button");
    expect(sentFields(send).map((sent) => sent.value)).toEqual(["new.person@example.org"]);
  });

  it("drops a value the page rewrote after the person typed it", () => {
    const send = setUp(signup);
    type("#signupEmail", "new.person@example.org");
    (element("#signupEmail") as HTMLInputElement).value = "attacker@evil.example";
    type("#fullName", "Alex Rivera");
    click("#create");
    expect(send).not.toHaveBeenCalled();
  });

  it("keeps a phone number the page only reformatted", () => {
    const send = setUp('<form><input type="tel" name="phone" autocomplete="tel"><button>Save</button></form>');
    type("[name=phone]", "5105550134");
    (element("[name=phone]") as HTMLInputElement).value = "(510) 555-0134";
    click("button");
    expect(sentFields(send).map((field) => field.value)).toEqual(["(510) 555-0134"]);
  });

  it("sends nothing when only a name was typed", () => {
    const send = setUp(signup);
    type("#fullName", "Alex Rivera");
    click("#create");
    hide();
    expect(send).not.toHaveBeenCalled();
  });
});

describe("what counts as a sign-up", () => {
  it.each([
    ['<input type="password" autocomplete="new-password">', true],
    ['<input type="password">', true],
    ['<input type="password" autocomplete="current-password">', false],
    ['<input type="password" style="display:none">', false],
    ['<input type="password" hidden>', false],
  ])("%s gives hasPassword %s", (password, expected) => {
    const send = setUp(`<form><input type="email" name="email">${password}<button>Go</button></form>`);
    type("[name=email]", "new.person@example.org");
    click("button");
    expect(send.mock.calls[0]?.[0].hasPassword).toBe(expected);
  });
});

describe("capture on checkout", () => {
  it("joins tagged address parts into one address per section and skips card fields", () => {
    const send = setUp(checkoutTagged);
    type("#checkout_email", "alex.rivera@example.com");
    type("#ship_line1", "2400 Durant Ave");
    type("#ship_line2", "Apt 4");
    type("#ship_city", "Berkeley");
    choose("#ship_state", "CA");
    choose("#ship_country", "US");
    type("#ship_zip", "94704");
    type("#ship_phone", "+1 510 555 0134");
    type("#bill_line1", "1 Market St");
    type("#bill_city", "San Francisco");
    type("#bill_zip", "94105");
    type("#cc_number", "4111 1111 1111 1111");
    type("#cc_csc", "123");
    submit("#checkout");
    const request = send.mock.calls[0]?.[0];
    expect(request?.hasPassword).toBe(false);
    expect(request?.fields.map((field) => [field.kind, field.section, field.address ?? field.value])).toEqual([
      ["email", undefined, "alex.rivera@example.com"],
      ["phone", "shipping", "+1 510 555 0134"],
      [
        "address",
        "shipping",
        {
          street: "2400 Durant Ave\nApt 4",
          city: "Berkeley",
          state: "California",
          postalCode: "94704",
          country: "United States",
        },
      ],
      [
        "address",
        "billing",
        { street: "1 Market St", city: "San Francisco", state: "", postalCode: "94105", country: "" },
      ],
    ]);
    expect(JSON.stringify(request)).not.toContain("4111");
  });

  it("joins untagged address parts in page order", () => {
    const send = setUp(checkoutUntagged);
    type("#billing_first_name", "Alex");
    type("#billing_address_1", "2400 Durant Ave");
    type("#billing_city", "Berkeley");
    type("#billing_postcode", "94704");
    type("#billing_email", "alex.rivera@example.com");
    type("#coupon_code", "SAVE10");
    click("#place_order");
    const fields = sentFields(send);
    expect(fields.map((field) => field.kind)).toEqual(["name", "email", "address"]);
    expect(fields[2]).toMatchObject({
      address: { street: "2400 Durant Ave", city: "Berkeley", postalCode: "94704" },
      name: "billing_address_1 billing_city billing_postcode",
      label: "Street address, Town / City, ZIP Code",
    });
  });

  it("waits for the real submit when the browser blocks an invalid form, without firing invalid events", () => {
    const send = setUp(checkoutTagged);
    const invalid = vi.fn();
    element("#checkout_email").addEventListener("invalid", invalid);
    type("#ship_phone", "+1 510 555 0134");
    click("#pay");
    expect(send).not.toHaveBeenCalled();
    // The browser's own submit attempt fires it once; the check before it adds none.
    expect(invalid).toHaveBeenCalledTimes(1);
    type("#checkout_email", "alex.rivera@example.com");
    click("#pay");
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("trusts a submit button that skips validation", () => {
    const send = setUp(checkoutTagged.replace('id="pay"', 'id="pay" formnovalidate'));
    type("#ship_phone", "+1 510 555 0134");
    click("#pay");
    expect(send).toHaveBeenCalledTimes(1);
  });
});

describe("capture metadata for the someone-else filter", () => {
  it("passes recipient names and labels through for the app to judge", () => {
    const send = setUp(gift);
    type("[name=recipient_name]", "Jordan Lee");
    type("[name=recipient_email]", "jordan.lee@example.net");
    type("[name=recipient_street]", "77 Gift Way");
    type("[name=recipient_city]", "Oakland");
    type("[name=recipient_zip]", "94612");
    submit("#gift");
    const fields = sentFields(send);
    expect(fields.map((field) => [field.kind, field.name])).toEqual([
      ["name", "recipient_name"],
      ["email", "recipient_email"],
      ["address", "recipient_street recipient_city recipient_zip"],
    ]);
    expect(fields[0]?.autocomplete).toBe("off");
  });

  it("keeps what it sends within the message limits", () => {
    const inputs = Array.from({ length: 30 }, (_, index) => `<input type="email" name="e${String(index)}">`).join("");
    const long = "x".repeat(300);
    const send = setUp(
      `<form><label>${long}<input type="email" name="${long}"></label>${inputs}<button>Go</button></form>`,
    );
    type(`[name="${long}"]`, "first@example.org");
    for (let index = 0; index < 30; index += 1) type(`[name=e${String(index)}]`, `e${String(index)}@example.org`);
    click("button");
    const fields = sentFields(send);
    expect(fields).toHaveLength(20);
    expect(fields[0]?.name).toHaveLength(100);
    expect(fields[0]?.label?.length).toBeLessThanOrEqual(100);
  });
});

describe("capture for forms that never submit", () => {
  it("flushes finished fields when the page is hidden, once, as not submitted", () => {
    const send = setUp(formHtml);
    fill("[name=usr_contact]", "new.person@example.org");
    fill("[name=mob]", "510 555 0111");
    hide();
    hide();
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0].trigger).toBe("flush");
    expect(sentFields(send).map((field) => [field.kind, field.label])).toEqual([
      ["email", "Your e-mail"],
      ["phone", "Mobile number"],
    ]);
  });

  it("leaves a field the person is still typing in", () => {
    const send = setUp(formHtml);
    fill("[name=usr_contact]", "new.person@example.org");
    type("[name=mob]", "510 55");
    hide();
    expect(sentFields(send).map((field) => field.kind)).toEqual(["email"]);
  });

  it("keeps what a hidden page flushed, so the later submit still sends the whole address", () => {
    const send = setUp(checkoutTagged);
    fill("#ship_line1", "2400 Durant Ave");
    fill("#ship_city", "Berkeley");
    hide();
    expect(send).not.toHaveBeenCalled();
    fill("#ship_zip", "94704");
    fill("#checkout_email", "alex.rivera@example.com");
    submit("#checkout");
    expect(send).toHaveBeenCalledTimes(1);
    const address = sentFields(send).find((field) => field.kind === "address")?.address;
    expect(address).toMatchObject({ street: "2400 Durant Ave", city: "Berkeley", postalCode: "94704" });
  });

  it("ignores a hide or pagehide the page made up", () => {
    const send = setUp(formHtml, (event) => event.type === "input" || event.type === "change");
    fill("[name=usr_contact]", "new.person@example.org");
    hide();
    expect(send).not.toHaveBeenCalled();
  });
});

describe("buttons outside any form", () => {
  const app = `
    <nav><button id="menu">Menu</button></nav>
    <main>
      <div class="step">
        <div class="row"><span id="email-label">Email</span><input type="email" name="email" aria-labelledby="email-label"></div>
        <button id="show">Show password</button>
        <button id="continue" type="button">Continue</button>
      </div>
    </main>`;

  it("a button that doesn't say it submits sends nothing", () => {
    const send = setUp(app);
    type("[name=email]", "alex@gm");
    click("#menu");
    click("#show");
    expect(send).not.toHaveBeenCalled();
  });

  it("a nearby button that says it submits sends the fields, which stay for the next step", () => {
    const send = setUp(app.replace('type="button"', ""));
    type("[name=email]", "new.person@example.org");
    click("#continue");
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0]).toMatchObject({ trigger: "submit", fields: [{ kind: "email", label: "Email" }] });
  });

  it("a field the app has since removed is still reported, from what was read while typing", () => {
    const send = setUp(app);
    fill("[name=email]", "new.person@example.org");
    element(".step").remove();
    expect(() => {
      hide();
    }).not.toThrow();
    expect(sentFields(send)).toEqual([
      { kind: "email", value: "new.person@example.org", name: "email", label: "Email", userTyped: true },
    ]);
  });
});

describe("fields inside an open shadow root", () => {
  it("captures what the person types in a web component", () => {
    const send = setUp('<x-email-field></x-email-field><button id="go">Submit</button>');
    const shadow = element("x-email-field").attachShadow({ mode: "open" });
    shadow.innerHTML = '<label>Email <input type="email" name="email" autocomplete="email"></label>';
    const input = shadow.querySelector("input");
    if (input === null) throw new Error("no shadow input");
    input.value = "new.person@example.org";
    input.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
    input.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    hide();
    expect(sentFields(send)).toEqual([
      {
        kind: "email",
        value: "new.person@example.org",
        autocomplete: "email",
        name: "email",
        label: "Email",
        userTyped: true,
      },
    ]);
  });
});
