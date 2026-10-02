# Messages between the extension and the app

The content script sends a message to `background.js` with `browser.runtime.sendMessage`. The background script turns away any message that Safari doesn't say came from this extension's content script in the top frame of a normal tab showing an `https` page (or plain `http` on `localhost` and `127.0.0.1`). Messages from Private Browsing tabs never reach the app, and neither does one from a tab that doesn't say whether it is private. It then parses the message with `parseExtensionRequest`, which rebuilds it from the fields below and drops anything else, replaces `host` with the host of the page Safari says sent it, and forwards the result with `browser.runtime.sendNativeMessage`. `SafariWebExtensionHandler` reads it from `SFExtensionMessageKey`, decodes it into `ExtensionRequest` and hands it to `MessageRouter`, which answers with an `ExtensionResponse`. The background script parses the answer the same way and replaces anything malformed with `{ "type": "error", "reason": "unreadable reply" }` before the page sees it.

The content script runs in the top frame of `https` pages only, plus plain `http` on `localhost` and `127.0.0.1` for testing, once the page has loaded (`document_idle`). The manifest matches only those, and the script checks again that it is in a secure context and the top frame. Frames are left out so an embedded widget from another site can't reorder the card or record values under its own host, and plain `http` is left out so a network attacker can't feed values to the card. A page without email, phone or address fields sends nothing.

Every message is a JSON object with a `type` field. The Swift types live in `Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift` and the TypeScript types in `web/src/messages.ts`. Both use the same field names. The examples below are copied from `docs/message-examples.json`, which the Swift and Vitest suites both load, so a renamed field fails a test on each side.

Contact values only travel from the page to the app. No response carries an email, phone number or address back to the page.

Both sides enforce the same size limits (`LIMITS` in `messages.ts`, `MessageLimits` in Swift) and the same shape rules: `host` is a lowercase host name (letters, digits, dots and dashes), no text may hold control, format (bidi overrides, zero-width characters) or line separator characters (a street may hold plain newlines), and an `address` field carries `address` and no `value` while every other kind carries `value` and no `address`. The handler answers `error` to anything that breaks them.

| Limit | Value |
| --- | --- |
| Whole message | 64 KB |
| `host` | 253 characters |
| `pageContext` fields | 40 |
| `capture` fields | 20 |
| `value` | 256 characters |
| `autocomplete`, `name`, `label` | 100 characters each |
| `address.street` | 400 characters |
| Other address parts | 200 characters each |

## Shared values

| Name | Values |
| --- | --- |
| Field kind | `email`, `phone`, `address`, `name` |
| Section hint | `home`, `work`, `shipping`, `billing`, taken from the field's `autocomplete` tokens |
| Sync status | `unchanged`, `saved`, `failed`, `off`, `notSetUp` |

The `enums` block in `docs/message-examples.json` lists these values. The Swift suite checks it against `FieldKind`, `SectionHint` and `SyncStatus`, and the Vitest suite checks it against the arrays the TypeScript types and validators are built from.

A `name` field is never saved. The capture filter only uses it to tell whether a form is about the person.

## ping

`ping` checks that the native handler answers. The content script doesn't send it on its own, so ordinary page loads never reach the app. The reply is `pong`.

```json
{ "type": "ping" }
```

```json
{ "type": "pong" }
```

## pageContext

The content script sends `pageContext` once the page has settled: 300 ms after the last change that added a field, and never more than a second after the first such change, so forms an app renders after load still count and a page that never stops changing still gets one. It sends again when a later form adds a kind or section it hasn't reported yet, such as the address step of a checkout. The card's order is shared by every tab, so it also sends again when the page comes back from the back-forward cache or into view, and on the first focus of an email, phone or address field after load or after either of those. Each report can rewrite the card, which syncs to every device, so a page sends at most five, at least two seconds apart; a report asked for sooner waits and goes out once. It lists the kinds of email, phone and address fields on the page and their section hints, without any values. Name fields are left out because they never change the card's order. The app ranks the person's values for this site and rewrites their card if the first two values of a kind should change.

| Field | Type | Meaning |
| --- | --- | --- |
| `host` | string | The page's host name. The app reduces it to the registrable domain, so `shop.example.net` and `example.net` share history. |
| `fields` | array | One entry per contact field, in page order. |
| `fields[].kind` | field kind | What the field asks for. |
| `fields[].section` | section hint, optional | Where the field says the value is used. The first field of a kind that has a section decides the hint for that kind. |

```json
{
  "type": "pageContext",
  "host": "shop.example.net",
  "fields": [
    { "kind": "email", "section": "work" },
    { "kind": "phone" },
    { "kind": "address", "section": "shipping" }
  ]
}
```

The reply is `pageContextResult`. Its `status` is `saved` when the card was rewritten, `unchanged` when the first two values already fit, `off` when Match each site is turned off, `notSetUp` when the person hasn't linked their card in Prefill yet, and `failed` when the card could not be read or saved. A failure includes a `reason` written for people. The content script only uses the status, to keep a retry for the next focus after `failed` or `error`; nothing shows the reason yet.

```json
{ "type": "pageContextResult", "status": "saved" }
```

```json
{
  "type": "pageContextResult",
  "status": "failed",
  "reason": "Prefill can't reach your contact card. Open Prefill to give it access again."
}
```

## capture

The content script sends `capture` with `trigger: "submit"` when the person submits a form (a submit event or a click on its submit button, whichever comes first, while Safari reports a fresh tap or keypress), or clicks a button outside any form that says it submits ("Continue", "Sign up") next to the fields they typed in. A page script that submits the form by itself sends nothing. It sends `trigger: "flush"` when the page is hidden, which covers forms that post with `fetch`; that report holds only fields the person has left, and an address only once its postal code is in. Fields reported for a hidden page stay, so a later submit still sends them whole.

Only events Safari marks as the person's count, and only fields they typed into while the field was on screen at a usable size and editable. If the page changes a value after the person typed it (beyond a phone number's spacing), the field is dropped. Password, one-time code, card number, bank account and ID fields are never sent, and neither is any box that was ever `type=password`, even after a "show password" toggle. A box only counts as a phone number when its `autocomplete` says `tel` or its label, name or placeholder says phone, and none of them mentions a card, account, code, PIN, birth date or the like. Address parts typed into separate boxes arrive as one `address`; a repeated part or a different `autocomplete` section starts the next one. A form with nothing but names typed sends nothing. `hasPassword` is true when the form has a visible password field that isn't a sign-in's current password, which marks it as a sign-up.

| Field | Type | Meaning |
| --- | --- | --- |
| `host` | string | The page's host name. |
| `hasPassword` | boolean | The form has a visible new-password field. |
| `trigger` | `submit` or `flush` | The person submitted the form, or the page was hidden first. |
| `fields[].kind` | field kind | What the field holds. |
| `fields[].value` | string, optional | The typed text for email, phone and name fields. |
| `fields[].address` | object, optional | For an address, the parts `street`, `city`, `state`, `postalCode` and `country`. |
| `fields[].autocomplete` | string, optional | The field's `autocomplete` attribute as written. |
| `fields[].name` | string, optional | The field's `name` or `id`. |
| `fields[].label` | string, optional | The text of the field's label. |
| `fields[].section` | section hint, optional | The section from `autocomplete`. A `home` or `work` section becomes the saved value's label. |
| `fields[].userTyped` | boolean | The person typed the value. The content script only sends such fields; the app ignores any other. |

The app uses `autocomplete`, `name` and `label` to skip fields meant for someone else, such as a gift recipient or an invite, and checks each value: an email must be a single address with a valid domain, a phone number 7 to 15 digits with only the usual separators (and not a card number or a bare code), and an address free of links and control characters.

```json
{
  "type": "capture",
  "host": "shop.example.net",
  "hasPassword": true,
  "trigger": "submit",
  "fields": [
    { "kind": "name", "value": "Alex Rivera", "autocomplete": "name", "name": "full_name", "label": "Full name", "userTyped": true },
    { "kind": "email", "value": "alex.new@example.net", "autocomplete": "email", "name": "email", "label": "Email", "userTyped": true },
    {
      "kind": "address",
      "section": "shipping",
      "userTyped": true,
      "address": {
        "street": "2400 Durant Ave",
        "city": "Berkeley",
        "state": "CA",
        "postalCode": "94704",
        "country": "United States"
      }
    }
  ]
}
```

The reply is `captureResult`, with counts only. `saved` values went onto the card (ranked first for this site when Match each site is on, and placed after the person's own order when it is off), `review` values wait in Recently added for the person to confirm, and `ignored` fields were skipped. A value already on the card counts toward none of the three, since only its use on this site is recorded, and only when Match each site is on. A new value goes straight onto the card only when the form also holds something already on the card that the person typed themselves: one of its emails, phones or addresses, or its full name (given and family, in one box or split across two). A password box, tags or a lone first name are not enough, since a page controls them. Values go to review instead of the card without that, when the report has `trigger: "flush"`, when the card can't be written, or past the save limits: three new values per form and six per hour across all sites. Before the person has linked their card, or when the card can't be read, the app stores nothing and every field counts as `ignored`.

```json
{ "type": "captureResult", "saved": 1, "review": 0, "ignored": 1 }
```

## error

The handler answers `error` when a message is not valid JSON, has an unknown `type`, is missing a required field, or is over the size limits.

```json
{ "type": "error", "reason": "unknown message" }
```
