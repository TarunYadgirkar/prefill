// Field-name patterns derived from Chromium's autofill parsing patterns,
// components/autofill/core/browser/form_parsing/resources/legacy_regex_patterns.json
// Copyright 2025 The Chromium Authors. Used under the BSD-style license reproduced in NOTICE.
// Changes from the original: a subset of the languages, one regex per type, "address line 2"
// also accepts a space, and a loose trailing "name" catches labels such as "Recipient name"
// so a form about someone else still reaches the app's someone-else filter.

import type { AddressPart, Control, NamePart } from "./fieldTypes";

export type RuleResult =
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
const TEXT_EMAIL: readonly Control[] = ["text", "email"];
const NUMERIC: readonly Control[] = ["text", "tel", "number"];
const CHOICE: readonly Control[] = ["text", "select"];
const STREET: readonly Control[] = ["text", "textarea"];
const ANY: readonly Control[] = ["text", "email", "tel", "number", "select", "textarea"];

const nameIgnored = /user.?name|user.?id|nickname|maiden name|title|prefix|suffix|mail|用户名/iu;
const addressNameIgnored = /(?:address|location).*(?:nickname|label|type)|lookup/iu;

// Card numbers, security codes, one-time codes, passwords, bank details and government IDs. A field
// that matches is never classified as contact data, whatever else it matches.
export const SENSITIVE: readonly RegExp[] = [
  /(?:card|cc|acct).?(?:number|#|no|num|field(?!s)|pan)|0000 ?0000 ?0000 ?0000|1234 ?1234 ?1234 ?1234/iu,
  /verification|card.?identification|security.?code|card.?code|security.?value|security.?number|card.?pin|c-v-v|(?:cvn|cvv|cvc|csc|cvd|ccv)|\bcid\b|cccid/iu,
  /\botp\b|one.?time|verification.code|2fa|six.digit/iu,
  /card.?(?:holder|owner)|name.*on.*card|(?:card|cc).?name|expir|exp.*date/iu,
  /password|passwort|passcode|contraseña|mot de passe|\bssn\b|social.?security/iu,
  /account.?(?:number|no\b|num|#)|routing|\biban\b|\bbic\b|swift.?code|sort.?code|\bpin\b(?!.?code)|token|(?:backup|recovery|access|auth).?code/iu,
  /\bdob\b|date.?of.?birth|birth.?date|national.?id|passport|tax.?id|driver.?s?.?licen[cs]e|\b(?:ein|itin|nin)\b/iu,
];

// Fields that look like contact data but are not the person's own details. Checked after
// email and phone, so "Business email" is still an email.
const IGNORED =
  /^q$|search|query|suche|recherch|busca|検索|搜索|captcha|(promo(tion|tional)?|gift|discount|coupon)[-_. ]*code|gift.?(card|cert)|company|business|organi[sz]ation|firma|empresa|soci[eé]t[eé]|attention|attn/iu;

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
      /phone|mobile|contact.?number|telefonnummer|telefono|teléfono|telfixe|telefone|telemovel|電話|电话|телефон|(\b|_|\*)telefon(\b|_|\*)/iu,
    negative: /\bext\b|extension|area.?code|country.?code|phone.?code/iu,
    controls: NUMERIC,
  },
  { result: { kind: "ignored" }, pattern: IGNORED, controls: ANY },
  {
    result: { kind: "address", part: "postalCode" },
    pattern:
      /(?<!\.)zip|postal|post.*code|pcode|pin.?code|postleitzahl|\bplz\b|\bcp\b|\bcdp\b|\bcap\b|\bcep\b|codpos|郵便番号|邮政编码|邮编|郵遞區號/iu,
    controls: NUMERIC,
  },
  {
    result: { kind: "address", part: "country" },
    pattern: /country|countries|país|pais|\bpays\b|\bpaese\b|\bnazione\b|(\b|_)land(\b|_)|国家/iu,
    negative: /country.?code|(\b|_)land(\b|_).*mark/iu,
    controls: CHOICE,
  },
  {
    result: { kind: "address", part: "state" },
    pattern: /(?<!(united|hist|history).?)state|region|province|county|principality|estado|provincia|都道府県|省/iu,
    controls: CHOICE,
  },
  {
    result: { kind: "address", part: "city" },
    pattern:
      /(?<!(?:pa|ri|li|di|ni|lo))city|town|suburb|\bort\b|stadt|ciudad|localidad|poblacion|ville|commune|citt[àa]\b|localita|cidade|市区町村/iu,
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
  {
    result: { kind: "name", part: "family" },
    pattern:
      /last.*name|lname|surname(?!\d)|last$|secondname|family.*name|nachname|apellidos?|famille|^nom(?![a-z])|cognome|sobrenome|姓/iu,
    negative: nameIgnored,
    controls: TEXT,
  },
  {
    result: { kind: "name", part: "given" },
    pattern: /first.*name|initials|fname|first$|given.*name|vorname|nombre|forename|prénom|prenom|\bnome\b|名/iu,
    negative: nameIgnored,
    controls: TEXT,
  },
  {
    result: { kind: "name", part: "middle" },
    pattern: /middle.*name|mname|middle$/iu,
    negative: nameIgnored,
    controls: TEXT,
  },
  {
    result: { kind: "name", part: "full" },
    pattern:
      /^name|full.?name|your.?name|customer.?name|bill.?name|ship.?name|name.*first.*last|firstandlastname|contact.?(name|person)|receiver|(^|\W)name$|姓名|氏名/iu,
    negative: nameIgnored,
    controls: TEXT,
  },
];
