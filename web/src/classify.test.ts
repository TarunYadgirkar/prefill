import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import formHtml from "../../testbed/form.html?raw";
import greenhouse from "../../testbed/sites/greenhouse.html?raw";
import { parseAutocomplete } from "./autocomplete";
import { classify } from "./classify";
import { fieldElements } from "./dom";
import type { Classification, FieldElement } from "./fieldTypes";
import airtable from "./fixtures/airtable-form.html?raw";
import checkoutTagged from "./fixtures/checkout-tagged.html?raw";
import checkoutUntagged from "./fixtures/checkout-untagged.html?raw";
import signup from "./fixtures/signup.html?raw";

function page(html: string): void {
  document.body.innerHTML = html;
}

function field(selector: string): FieldElement {
  const element = document.querySelector(selector);
  if (element === null) throw new Error(`no ${selector}`);
  return element as FieldElement;
}

function summary(classification: Classification): string {
  if (classification.kind === "sensitive" || classification.kind === "ignored")
    return classification.kind;
  return [classification.kind, classification.part, classification.section]
    .filter(Boolean)
    .join(" ");
}

function classifyAll(): Record<string, string> {
  return Object.fromEntries(
    fieldElements(document).map((element) => [
      element.getAttribute("name") ?? element.id,
      summary(classify(element)),
    ]),
  );
}

beforeEach(() => {
  document.body.innerHTML = "";
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue(
    new DOMRect(10, 10, 200, 30),
  );
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("parseAutocomplete", () => {
  it.each([
    ["email", { field: "email" }],
    ["work email", { field: "email", contact: "work" }],
    ["shipping street-address", { field: "street-address", mode: "shipping" }],
    [
      "section-gift shipping postal-code",
      { field: "postal-code", mode: "shipping", section: "section-gift" },
    ],
    [
      "section-a billing home tel",
      { field: "tel", contact: "home", mode: "billing", section: "section-a" },
    ],
    ["  Mobile   TEL webauthn ", { field: "tel", contact: "mobile" }],
  ])("reads %j", (raw, detail) => {
    expect(parseAutocomplete(raw)).toEqual(detail);
  });

  it.each([
    null,
    "",
    "on",
    "off",
    "nope",
    "work street-address",
    "email work",
    "billing shipping email",
    "section- email",
  ])("rejects %j", (raw) => {
    expect(parseAutocomplete(raw)).toBeUndefined();
  });
});

describe("classify on the testbed page", () => {
  it("reads the tagged and untagged forms the way Safari does", () => {
    page(formHtml);
    expect(classifyAll()).toEqual({
      name: "name full",
      email: "email",
      tel: "phone",
      street: "address street",
      city: "address city",
      state: "address state",
      zip: "address postalCode",
      usr_contact: "email",
      mob: "phone",
    });
  });
});

describe("classify on hand-written forms", () => {
  it("tagged checkout: sections come from the tokens and card fields are sensitive", () => {
    page(checkoutTagged);
    expect(classifyAll()).toEqual({
      "checkout[email]": "email",
      "checkout[shipping_address][country]": "address country shipping",
      "checkout[shipping_address][first_name]": "name given shipping",
      "checkout[shipping_address][last_name]": "name family shipping",
      "checkout[shipping_address][address1]": "address street shipping",
      "checkout[shipping_address][address2]": "address street2 shipping",
      "checkout[shipping_address][city]": "address city shipping",
      "checkout[shipping_address][province]": "address state shipping",
      "checkout[shipping_address][zip]": "address postalCode shipping",
      "checkout[shipping_address][phone]": "phone shipping",
      "checkout[billing_address][address1]": "address street billing",
      "checkout[billing_address][city]": "address city billing",
      "checkout[billing_address][zip]": "address postalCode billing",
      "checkout[credit_card][number]": "sensitive",
      "checkout[credit_card][name]": "sensitive",
      "checkout[credit_card][verification_value]": "sensitive",
    });
  });

  it("untagged checkout: labels and names decide, a tel ZIP stays a ZIP", () => {
    page(checkoutUntagged);
    expect(classifyAll()).toEqual({
      billing_first_name: "name given",
      billing_last_name: "name family",
      billing_company: "ignored",
      billing_address_1: "address street",
      billing_address_2: "address street2",
      billing_city: "address city",
      billing_state: "address state",
      billing_postcode: "address postalCode",
      billing_phone: "phone",
      billing_email: "email",
      order_comments: "ignored",
      coupon_code: "ignored",
    });
  });

  it("sign-up: passwords and codes are sensitive, checkboxes ignored", () => {
    page(signup);
    expect(classifyAll()).toEqual({
      fullName: "name full",
      email: "email",
      password: "sensitive",
      code: "sensitive",
      website_email: "email",
      newsletter: "ignored",
    });
  });
});

describe("classify single fields", () => {
  it.each([
    ['<input autocomplete="work email">', "email work"],
    ['<input type="email" autocomplete="username">', "email"],
    [
      '<form><input type="email" name="email"><input type="password" autocomplete="current-password"></form>',
      "ignored",
    ],
    ['<input type="email" autocomplete="username webauthn">', "ignored"],
    [
      '<div><input type="email" name="email"><input type="password" autocomplete="current-password"></div>',
      "ignored",
    ],
    [
      '<form><input type="email" name="email"><input type="password"><button>Log in</button></form>',
      "ignored",
    ],
    ['<label>Cell <input type="tel"></label>', "phone"],
    ['<label>Tel. <input type="text"></label>', "phone"],
    ["<label>Social Insurance Number <input></label>", "sensitive"],
    ["<label>Name on account <input></label>", "sensitive"],
    ["<label>Confirmation code <input></label>", "sensitive"],
    ["<label>Nombre completo <input></label>", "name full"],
    ["<label>School name <input></label>", "ignored"],

    ['<input autocomplete="username">', "ignored"],
    ['<input autocomplete="one-time-code">', "sensitive"],
    ['<input autocomplete="tel-area-code">', "phone partial"],
    ['<input autocomplete="organization">', "ignored"],
    ['<input type="password" name="email">', "sensitive"],
    ['<input type="hidden" name="email">', "ignored"],
    ['<input type="search" name="email">', "ignored"],
    ['<input type="tel">', "ignored"],
    ['<label>Mobile phone <input type="tel"></label>', "phone"],
    ['<input type="tel" name="pan1">', "ignored"],
    [
      '<label>Enter the 8-digit code <input type="tel" inputmode="numeric"></label>',
      "sensitive",
    ],
    ['<label>Account number <input type="tel"></label>', "sensitive"],
    ['<label>Routing number <input type="tel"></label>', "sensitive"],
    ['<label>Backup code <input type="tel"></label>', "sensitive"],
    ['<label>PIN <input type="tel"></label>', "sensitive"],
    ['<label>Date of birth <input type="tel"></label>', "sensitive"],
    ['<label>PIN code <input name="x"></label>', "address postalCode"],
    [
      '<input type="tel" autocomplete="tel" aria-label="Verification code">',
      "sensitive",
    ],
    ['<input autocomplete="email" aria-label="Account number">', "sensitive"],
    ['<input name="phone_ext">', "ignored"],
    ['<input type="tel" name="phone_ext">', "ignored"],
    ['<input name="home_mailing_address">', "address street"],
    ['<input name="same_mailing_street">', "address street"],
    ['<input name="e-mail">', "email"],
    ['<input name="userEmail">', "email"],
    ['<label>Card number <input name="x"></label>', "sensitive"],
    ['<label>CVV <input name="x"></label>', "sensitive"],
    ['<label>Name on card <input name="x"></label>', "sensitive"],
    ['<input name="nameOnCard">', "sensitive"],
    ['<label>Name as it appears on your card <input name="x"></label>', "sensitive"],
    ['<label>Phone <input type="tel" name="cc"></label>', "sensitive"],
    ['<label>Phone <input type="tel" name="ccexp"></label>', "sensitive"],
    ['<label>Phone <input type="tel" name="f-28cc-436d"></label>', "phone"],
    ['<label>Preferred name <input name="cards[0][field0]"></label>', "name full"],
    ["<label>Name pronunciation <input></label>", "ignored"],
    ["<label>How do you say your name? <input></label>", "ignored"],
    ['<label>Company website <input type="url"></label>', "ignored"],
    ['<label>What is your startup\'s website? <input autocomplete="url"></label>', "ignored"],
    ["<label>Organization LinkedIn <input></label>", "ignored"],
    ['<label>Business email <input name="x"></label>', "email"],
    ['<label>Search <input name="q"></label>', "ignored"],
    ['<label>Recipient name <input name="x"></label>', "ignored"],
    ['<label>Emergency contact phone <input type="tel" name="x"></label>', "ignored"],
    ['<label>Parent/Guardian email <input type="email" name="x"></label>', "ignored"],
    ['<label>Reference name <input name="x"></label>', "ignored"],
    ['<label>Referrer\'s email <input type="email" name="x"></label>', "ignored"],
    ['<label>Spouse name <input name="x"></label>', "ignored"],
    ['<label>Name of Participant <input name="x"></label>', "name full"],
    ['<label>Username <input name="x"></label>', "ignored"],
    [
      '<label>Country <select name="c"><option>United States</option></select></label>',
      "address country",
    ],
    ['<label>Address <textarea name="a"></textarea></label>', "address street"],
    ['<input name="shipAddressLine2">', "address street2"],
    [
      '<input placeholder="you@example.com" name="contact" aria-label="E-mail">',
      "email",
    ],
    [
      '<span id="l">Mobile number</span><input aria-labelledby="l" name="x">',
      "phone",
    ],
    [
      '<input name="x" autocomplete="off" placeholder="ZIP">',
      "address postalCode",
    ],
  ])("%s is %s", (html, expected) => {
    page(html);
    expect(summary(classify(field("input, select, textarea")))).toBe(expected);
  });
});

describe("classify link fields", () => {
  it.each([
    ["LinkedIn URL", ["linkedin"]],
    ["GitHub URL", ["github"]],
    ["Other website", ["other"]],
    ["Portfolio URL", ["website"]],
    ["URL", ["website"]],
  ])("reads %s as %j", (label, types) => {
    page(`<label>${label} <input type="text"></label>`);
    const found = classify(field("input"));
    expect(found.kind === "link" ? found.linkTypes : found.kind).toEqual(types);
  });

  it.each([
    ['<label>GitHub <textarea name="x"></textarea></label>', ["github"]],
    ['<label>LinkedIn profile URL <textarea name="x"></textarea></label>', ["linkedin"]],
    ['<label>Tell us about a project you built, with a link to its GitHub repository <textarea name="x"></textarea></label>', "ignored"],
    ["<label>Website (e.g. LinkedIn) <input></label>", ["website", "linkedin", "github"]],
    ["<label>Links (such as GitHub or LinkedIn) <input></label>", ["github", "linkedin", "website"]],
    ["<label>GitHub/Portfolio <input></label>", ["github", "website"]],
  ])("reads %s as %j", (html, types) => {
    page(html);
    const found = classify(field("input, textarea"));
    expect(found.kind === "link" ? found.linkTypes : found.kind).toEqual(types);
  });

  it("reads a Greenhouse-style application's untagged link questions", () => {
    page(greenhouse.replace(/<link[^>]*>/u, ""));
    const links = (selector: string): unknown => {
      const found = classify(field(selector));
      return found.kind === "link" ? found.linkTypes : found.kind;
    };
    expect(links("#question_0")).toEqual(["github", "website"]);
    expect(links("#question_1")).toEqual(["linkedin"]);
    expect(links("#question_2")).toBe("ignored");
    expect(summary(classify(field("#email")))).toBe("email");
  });

  it("treats a url field as a website and leaves a company website alone", () => {
    page(
      '<input id="a" type="url"><label>Company website <input id="b"></label>',
    );
    expect(classify(field("#a"))).toMatchObject({
      kind: "link",
      linkTypes: ["website"],
    });
    expect(classify(field("#b")).kind).toBe("ignored");
  });
});

describe("Airtable's form", () => {
  const byLabel = (): Record<string, string> =>
    Object.fromEntries(
      fieldElements(document)
        .filter((element) => element.labels?.[0] !== undefined)
        .map((element) => {
          const found = classify(element);
          const types =
            "linkTypes" in found ? (found.linkTypes ?? []).join(",") : "";
          return [
            element.labels?.[0]?.textContent.trim() ?? "",
            [summary(found), types].filter(Boolean).join(" "),
          ];
        }),
    );

  it("reads names and emails in text areas, and a resume link as no profile", () => {
    page(airtable);
    expect(byLabel()).toMatchObject({
      "Full Name": "name full",
      "Student Email": "email",
      "Personal Email": "email",
      Phone: "phone",
      Linkedin: "link linkedin",
      Github: "link github",
      "Resume Link": "ignored",
      University: "ignored",
      "Optional project website or link": "link website",
    });
  });
});
