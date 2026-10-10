// Field-name patterns derived from Chromium's autofill parsing patterns,
// components/autofill/core/browser/form_parsing/resources/legacy_regex_patterns.json
// Copyright 2025 The Chromium Authors. Used under the BSD-style license reproduced in NOTICE.
// Changes from the original: a subset of the languages, one regex per type, "address line 2"
// also accepts a space, and a loose trailing "name" catches labels such as "Recipient name"
// so a form about someone else still reaches the app's someone-else filter.

import type { AddressPart, Control, NamePart } from "./fieldTypes";
import type { LinkType } from "./messages";

export type RuleResult =
  | { kind: "link" }
  | { kind: "email" }
  | { kind: "phone" }
  | { kind: "address"; part: AddressPart }
  | { kind: "name"; part: NamePart }
  | { kind: "ignored" };

export interface Rule {
  result: RuleResult;
  pattern: RegExp;
  negative?: RegExp;
  controls: readonly Control[];
}

const TEXT: readonly Control[] = ["text"];
const WEB: readonly Control[] = ["text", "url"];
// Some forms (Airtable's) ask for a name or an email in a text area.
const TEXT_EMAIL: readonly Control[] = ["text", "email", "textarea"];
const NAME: readonly Control[] = ["text", "textarea"];
const NUMERIC: readonly Control[] = ["text", "tel", "number"];
const CHOICE: readonly Control[] = ["text", "select"];
const STREET: readonly Control[] = ["text", "textarea"];
const ANY: readonly Control[] = [
  "text",
  "email",
  "tel",
  "number",
  "select",
  "textarea",
  "url",
];

// Words that ask for a profile or website link, one pattern per link type. Prefill's own,
// not from Chromium, which has no link types.
export const LINK_WORDS: readonly (readonly [LinkType, RegExp])[] = [
  ["github", /git.?hub/iu],
  ["linkedin", /linked.?in/iu],
  [
    "x",
    /twitter|\bx\.com\b|^x\s*[:(]|^x\s+(?:profile|handle|url|link|account)\b/iu,
  ],
  ["other", /other.?(?:web.?site|url|link)/iu],
  [
    "website",
    /portfolio|web.?site|personal.?(?:site|page)|home.?page|\bblog\b/iu,
  ],
];
// A bare "URL" names no link type: "LinkedIn URL" asks for LinkedIn alone, and "URL" by
// itself asks for a website.
export const GENERIC_LINK = /\burl\b/iu;
// Words that ask for a link to something other than a profile or website: a field that
// says "Resume Link" wants a document, whatever its autocomplete token says.
export const OTHER_LINKS =
  /r[eé]sum[eé]|\bcv\b|project|demo|video|paper|publication|writing.?sample|calendly|schedul/iu;
// A link to the person's company or startup, not to them: "What is your company's website?"
export const ORG_LINK =
  /compan(?:y|ies)|start.?up|organi[sz]ation|business|employer|venture|\bfirm\b/iu;
// Where a label starts listing examples: "Website (Examples: LinkedIn, GitHub, portfolio)".
export const EXAMPLES = /\(?\s*(?:\be\.?\s?g\b\.?|\bexamples?\b|\bfor instance\b|\bsuch as\b)/iu;
export const LINK = new RegExp(
  [
    ...LINK_WORDS.map(([, pattern]) => pattern.source),
    GENERIC_LINK.source,
  ].join("|"),
  "iu",
);

// A question about how to say the name ("Name pronunciation") wants the sound, not the name,
// a startup, company, team or project name isn't the person's, and a preferred name is a
// saved answer of its own.
const nameIgnored =
  /user.?name|user.?id|nickname|maiden name|title|prefix|suffix|mail|school|universit|college|reference|bank|pronunc|pronounce|phonetic|preferred|how (?:do )?(?:you|we|to) say|start.?up|compan(?:y|ies)|organi[sz]ation|\bteam\b|project|venture|用户名|会社/iu;
const addressNameIgnored =
  /(?:address|location).*(?:nickname|label|type)|lookup/iu;

// Card numbers, security codes, one-time codes, passwords, bank details and government IDs. A field
// that matches is never classified as contact data, whatever else it matches.
export const SENSITIVE: readonly RegExp[] = [
  /(?:card|(?<![a-z0-9])cc|acct).?(?:number|#|no|num|field(?!s)|pan)|0000 ?0000 ?0000 ?0000|1234 ?1234 ?1234 ?1234/iu,
  /verification|card.?identification|security.?code|card.?code|security.?value|security.?number|card.?pin|c-v-v|(?:cvn|cvv|cvc|csc|cvd|ccv)|\bcid\b|cccid/iu,
  /\botp\b|one.?time|verification.code|2fa|six.digit/iu,
  /card.?(?:holder|owner)|name[\W_]?on[\W_]?card|\bname\b.{0,30}\bon (?:the |your )?card\b|(?:card|(?<![a-z0-9])cc).?name|expir|\bexp\b|exp(?:iry|iration)?.?date/iu,
  /password|passwort|passcode|passwd|\bpwd\b|contraseña|mot de passe|\bssn\b|social.?security|secret|\bmfa\b/iu,
  /account.?(?:number|no\b|num|#)|routing|\biban\b|\bbic\b|swift.?code|sort.?code|\bpin\b(?!.?code)|token|(?:backup|recovery|access|auth).?code/iu,
  /\bdob\b|date.?of.?birth|birth.?date|national.?id|passport|tax.?id|driver.?s?.?licen[cs]e|\b(?:ein|itin|nin)\b/iu,
  /(?:social|national).?insurance|tax.?file|aadhaa?r|\b(?:cpf|dni|bsn|nie|nif|bsb)\b|nhs.?(?:number|no)|medicare|personnummer|visa.?(?:number|no\b)|transit.?number/iu,
  /kontonummer|kartennummer|num[eé]ro de (?:carte|compte)|account.?holder|name.?on.?(?:the.?)?account/iu,
  /(?:confirmation|sms|text(?:ed)?|login|sign.?in|security|access).?code|\d.?digit.{0,12}code|security.?(?:answer|question)/iu,
];

// Words that rule a box out as a phone number, whatever its type or tags say: stores and
// banks use type=tel for card numbers, codes, account numbers and birth dates. "cc" counts
// only as its own word or a card token, since generated ids ("8019a3b2-28cc-...") hold it,
// and Lever names every question "cards[...]".
export const NOT_PHONE =
  /card(?!s\b|s\[)|(?<![a-z0-9])cc(?![a-z0-9])|(?<![a-z0-9])cc[-_.]?(?:num|no\b|exp|cvv|csc|cvc)|cvv|\bpan\b|expir|routing|account|acct|iban|ssn|social|\btax|\bdob\b|birth|\bpin\b|otp|code|token|secret|pass|pwd/iu;

// A signature typed as a name ("Signature", "Electronic signature", "Type your full name to
// sign", "Initials" on a waiver) is the person's own act, never filled for them.
export const SIGNATURE =
  /signature|\be-?sign|\bsign (?:your|here|below|this)|\b(?:typing|signing) (?:and signing )?your (?:full |legal )?name|type your (?:full |legal )?name (?:to|as) (?:sign|your)|^\W*initials?\W*$|\binitial (?:here|below|each)|your initials/iu;

// Words that make a field someone else's: an emergency contact, a parent or guardian, a
// spouse, a reference or referrer, a gift's recipient. Their name, email, phone or address
// is never the person's own.
export const SOMEONE_ELSE =
  /emergency|next.?of.?kin|guardian|\bparents?\b|\bmother\b|\bfather\b|spouse|husband|\bwife\b|\breferences?\b|referr(?:er|al|ing)|recipient/iu;

// Fields that look like contact data but are not the person's own details. Checked after
// email and phone, so "Business email" is still an email.
const IGNORED =
  /^q$|search|query|suche|recherch|busca|検索|搜索|captcha|(promo(tion|tional)?|gift|discount|coupon)[-_. ]*code|gift.?(card|cert)|company|business|organi[sz]ation|firma|empresa|soci[eé]t[eé]|attention|attn/iu;

// Words that ask for a country, and those that ask for a dialling code instead.
export const COUNTRY = /country|countries|país|pais|\bpays\b|\bpaese\b|\bnazione\b|(\b|_)land(\b|_)|国家/iu;
export const NOT_COUNTRY = /country.?code|(\b|_)land(\b|_).*mark/iu;

export const RULES: readonly Rule[] = [
  {
    result: { kind: "email" },
    pattern:
      /\be[-_ ]?mail|email|correo.*electr(o|ó)nico|courriel|メールアドレス|邮件|邮箱|電子郵件|電郵地址|Электронн(ая|ой).?Почт(а|ы)|(\b|_)eposta(\b|_)/iu,
    controls: TEXT_EMAIL,
  },
  {
    result: { kind: "phone" },
    pattern:
      /phone|\bmobil(?:e|nummer)?\b|\btel\b|\bcell|contact.?number|celular|m[oó]vil|handy|rufnummer|telefoon|portable|\bgsm\b|telefonnummer|telefono|teléfono|telfixe|telefone|telemovel|電話|电话|телефон|(\b|_|\*)telefon(\b|_|\*)/iu,
    negative: /\bext\b|extension|area.?code|country.?code|phone.?code/iu,
    controls: NUMERIC,
  },
  { result: { kind: "ignored" }, pattern: IGNORED, controls: ANY },
  { result: { kind: "link" }, pattern: LINK, controls: WEB },
  {
    result: { kind: "address", part: "postalCode" },
    pattern:
      /(?<!\.)zip|postal|post.*code|pcode|pin.?code|postleitzahl|\bplz\b|\bcp\b|\bcdp\b|\bcap\b|\bcep\b|codpos|郵便番号|邮政编码|邮编|郵遞區號/iu,
    controls: NUMERIC,
  },
  {
    result: { kind: "address", part: "country" },
    pattern: COUNTRY,
    negative: NOT_COUNTRY,
    controls: CHOICE,
  },
  {
    result: { kind: "address", part: "state" },
    pattern:
      /(?<!(united|hist|history).?)state|region|province|county|principality|estado|provincia|都道府県|省/iu,
    controls: CHOICE,
  },
  {
    result: { kind: "address", part: "city" },
    pattern:
      /(?<!(?:pa|ri|li|di|ni|lo))city|town|suburb|\bort\b|stadt|ciudad|localidad|poblacion|ville|commune|citt[àa]\b|localita|cidade|市区町村|^(?:current |your |home )?location\b|where (?:are you|do you) (?:currently )?(?:located|based|live)\b/iu,
    // "Location" on an application is where the person lives, unless it asks where they'd work.
    negative: /prefer|desired|relocat|willing|office|remote|on.?site|hybrid|(?:work|job).?location/iu,
    controls: CHOICE,
  },
  {
    result: { kind: "address", part: "street2" },
    pattern:
      /address.?line.?(2|two)|address.?2|addr.?2|suite|\bapt\b|apartment|\bunit\b|adresszusatz|complemento|addresssuppl|appartement|住所2|地址2/iu,
    negative: addressNameIgnored,
    controls: TEXT,
  },
  {
    result: { kind: "address", part: "street" },
    pattern:
      /^address$|address.?line(one|1)?|address1|addr1|street|(?:shipping|billing)address$|house.?name|(^\W*address)|(address\W*$)|strasse|straße|direccion|dirección|adresse|indirizzo|morada|endereço|住所|地址/iu,
    negative: addressNameIgnored,
    controls: STREET,
  },
  // Says "full" in its own language, or asks for both names at once ("First and Last Name",
  // "Name (first and last)"), so it wins over the family and given words in it
  // ("Nom complet", "Nombre completo").
  {
    result: { kind: "name", part: "full" },
    pattern:
      /full.?name|nom(?:bre|e)? complet[oa]?|vollst[äa]ndiger.?name|氏名|姓名|フルネーム|(?:first|given)(?:.?name)?[\W_]*(?:and|&|\+)?[\W_]*(?:last|family|surname)|(?:last|family|surname)(?:.?name)?[\W_]*(?:and|&|\+)?[\W_]*(?:first|given)|name.*first.*last/iu,
    negative: nameIgnored,
    controls: NAME,
  },
  {
    result: { kind: "name", part: "family" },
    pattern:
      /last.*name|lname|surname(?!\d)|last$|secondname|family.*name|nachname|apellidos?|famille|^nom(?![a-z])|cognome|sobrenome|姓/iu,
    negative: nameIgnored,
    controls: NAME,
  },
  {
    result: { kind: "name", part: "given" },
    pattern:
      /first.*name|initials|fname|first$|given.*name|vorname|nombre|forename|prénom|prenom|\bnome\b|名/iu,
    negative: nameIgnored,
    controls: NAME,
  },
  {
    result: { kind: "name", part: "middle" },
    pattern: /middle.*name|mname|middle$/iu,
    negative: nameIgnored,
    controls: NAME,
  },
  {
    result: { kind: "name", part: "full" },
    pattern:
      /^name|full.?name|your.?name|customer.?name|bill.?name|ship.?name|name.*first.*last|firstandlastname|contact.?(name|person)|receiver|(^|\W)name$|姓名|氏名/iu,
    negative: nameIgnored,
    controls: NAME,
  },
];
