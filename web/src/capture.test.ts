import { afterEach, describe, expect, it, vi } from "vitest";
import formHtml from "../../testbed/form.html?raw";
import { installCapture } from "./capture";
import checkoutTagged from "./fixtures/checkout-tagged.html?raw";
import checkoutUntagged from "./fixtures/checkout-untagged.html?raw";
import gift from "./fixtures/gift.html?raw";
import signup from "./fixtures/signup.html?raw";
import type { CaptureRequest } from "./messages";

let uninstall: (() => void) | undefined;

afterEach(() => {
  uninstall?.();
  uninstall = undefined;
  document.body.innerHTML = "";
});

function setUp(html: string, isUserEvent: (event: Event) => boolean = () => true) {
  document.body.innerHTML = html;
  const send = vi.fn<(request: CaptureRequest) => void>();
  uninstall = installCapture(document, window, { host: () => "shop.example.net", send, isUserEvent });
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
  window.dispatchEvent(new Event("pagehide"));
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
      fields: [
        { kind: "name", value: "Alex Rivera", name: "fullName", label: "Full name" },
        { kind: "email", value: "new.person@example.org", autocomplete: "email", name: "email", label: "Email" },
      ],
    });
  });

  it("ignores events the person didn't make", () => {
    const send = setUp(signup, (event) => event.isTrusted);
    type("#signupEmail", "new.person@example.org");
    click("#create");
    expect(send).not.toHaveBeenCalled();
  });

  it("skips fields hidden from the person and fields left as the page filled them", () => {
    const send = setUp(signup);
    (element("#fullName") as HTMLInputElement).value = "Prefilled By Page";
    type("#hp", "bot@example.net");
    type("#signupEmail", "new.person@example.org");
    click("#create");
    expect(send.mock.calls[0]?.[0].fields.map((field) => field.value)).toEqual(["new.person@example.org"]);
  });

  it("sends nothing when only a name was typed", () => {
    const send = setUp(signup);
    type("#fullName", "Alex Rivera");
    click("#create");
    hide();
    expect(send).not.toHaveBeenCalled();
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
        { street: "2400 Durant Ave\nApt 4", city: "Berkeley", state: "California", postalCode: "94704", country: "United States" },
      ],
      ["address", "billing", { street: "1 Market St", city: "San Francisco", state: "", postalCode: "94105", country: "" }],
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
    const fields = send.mock.calls[0]?.[0].fields ?? [];
    expect(fields.map((field) => field.kind)).toEqual(["name", "email", "address"]);
    expect(fields[2]).toMatchObject({
      address: { street: "2400 Durant Ave", city: "Berkeley", postalCode: "94704" },
      name: "billing_address_1 billing_city billing_postcode",
      label: "Street address, Town / City, ZIP Code",
    });
  });

  it("waits for the real submit when the browser blocks an invalid form", () => {
    const send = setUp(checkoutTagged);
    type("#ship_phone", "+1 510 555 0134");
    click("#pay");
    expect(send).not.toHaveBeenCalled();
    type("#checkout_email", "alex.rivera@example.com");
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
    const fields = send.mock.calls[0]?.[0].fields ?? [];
    expect(fields.map((field) => [field.kind, field.name])).toEqual([
      ["name", "recipient_name"],
      ["email", "recipient_email"],
      ["address", "recipient_street recipient_city recipient_zip"],
    ]);
    expect(fields[0]?.autocomplete).toBe("off");
  });
});

describe("capture for forms that never submit", () => {
  it("flushes typed values when the page is hidden, once", () => {
    const send = setUp(formHtml);
    type("[name=usr_contact]", "new.person@example.org");
    type("[name=mob]", "510 555 0111");
    Object.defineProperty(document, "visibilityState", { value: "hidden", configurable: true });
    document.dispatchEvent(new Event("visibilitychange"));
    hide();
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]?.[0].fields.map((field) => [field.kind, field.label])).toEqual([
      ["email", "Your e-mail"],
      ["phone", "Mobile number"],
    ]);
    Reflect.deleteProperty(document, "visibilityState");
  });
});
