# Messages between the extension and the app

The content script sends a message to `background.js` with `browser.runtime.sendMessage`. The background script checks it with `isExtensionRequest` and forwards it unchanged with `browser.runtime.sendNativeMessage`. `SafariWebExtensionHandler` reads it from `SFExtensionMessageKey`, decodes it into `ExtensionRequest` and hands it to `MessageRouter`, which answers with an `ExtensionResponse`. The background script checks the answer with `isExtensionResponse` and replaces anything malformed with `{ "type": "error", "reason": "unreadable reply" }` before the page sees it.

The content script runs in every frame (`all_frames`). A frame without email, phone or address fields sends nothing.

Every message is a JSON object with a `type` field. The Swift types live in `Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift` and the TypeScript types in `web/src/messages.ts`. Both use the same field names. The examples below are copied from `docs/message-examples.json`, which the Swift and Vitest suites both load, so a renamed field fails a test on each side.

Contact values only travel from the page to the app. No response carries an email, phone number or address back to the page.

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

The content script sends `pageContext` once the page has settled (300 ms after the last change, so forms an app renders after load still count). If the person focuses a contact field before any reply has come back, it sends the message once more. It lists the kinds of email, phone and address fields on the page and their section hints, without any values. Name fields are left out because they never change the card's order. The app ranks the person's values for this site and rewrites their card if the first two values of a kind should change.

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

The reply is `pageContextResult`. Its `status` is `saved` when the card was rewritten, `unchanged` when the first two values already fit, `off` when Match each site is turned off, `notSetUp` when the person hasn't linked their card in Prefill yet, and `failed` when the card could not be read or saved. A failure includes a `reason` the app can show as is.

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

The content script sends `capture` when a form is submitted (a submit event or a click on its submit button, whichever comes first), or when a page with typed contact values is hidden, which covers forms that post with `fetch`. Only fields the person typed into while they were visible are sent. Password, one-time code and card number fields are never sent. Address parts typed into separate boxes arrive as one `address`; a repeated part or a different `autocomplete` section starts the next one. A form with nothing but names typed sends nothing. `hasPassword` tells the app whether the form had a password field, which marks it as a sign-up or sign-in form.

| Field | Type | Meaning |
| --- | --- | --- |
| `host` | string | The page's host name. |
| `hasPassword` | boolean | The form contained a password field. |
| `fields[].kind` | field kind | What the field holds. |
| `fields[].value` | string, optional | The typed text for email, phone and name fields. |
| `fields[].address` | object, optional | For an address, the parts `street`, `city`, `state`, `postalCode` and `country`. |
| `fields[].autocomplete` | string, optional | The field's `autocomplete` attribute as written. |
| `fields[].name` | string, optional | The field's `name` or `id`. |
| `fields[].label` | string, optional | The text of the field's label. |
| `fields[].section` | section hint, optional | The section from `autocomplete`. A `home` or `work` section becomes the saved value's label. |

The app uses `autocomplete`, `name` and `label` to skip fields meant for someone else, such as a gift recipient or an invite.

```json
{
  "type": "capture",
  "host": "shop.example.net",
  "hasPassword": true,
  "fields": [
    { "kind": "name", "value": "Alex Rivera", "autocomplete": "name", "name": "full_name", "label": "Full name" },
    { "kind": "email", "value": "alex.new@example.net", "autocomplete": "email", "name": "email", "label": "Email" },
    {
      "kind": "address",
      "section": "shipping",
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

The reply is `captureResult`, with counts only. `saved` values went onto the card, ranked first for this site, `review` values wait in Recently added for the person to confirm, and `ignored` fields were skipped. A value already on the card counts toward none of the three, since only its use on this site is recorded. A value that should have been saved but could not be written to the card goes to review instead. Before the person has linked their card, the app stores nothing and every field counts as `ignored`.

```json
{ "type": "captureResult", "saved": 1, "review": 0, "ignored": 1 }
```

## error

The handler answers `error` when a message is not valid JSON, has an unknown `type`, or is missing a required field.

```json
{ "type": "error", "reason": "unknown message" }
```
