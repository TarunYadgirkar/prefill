# Messages between the extension and the app

The content script sends a message to `background.js` with `browser.runtime.sendMessage`. The background script turns away any message that Safari doesn't say came from this extension's content script in the top frame of a normal tab showing an `https` page (or plain `http` on `localhost` and `127.0.0.1`). Messages from Private Browsing tabs never reach the app, and neither does one from a tab that doesn't say whether it is private. It then parses the message with `parseExtensionRequest`, which rebuilds it from the fields below and drops anything else, replaces `host` with the host of the page Safari says sent it, and forwards the result with `browser.runtime.sendNativeMessage`. `SafariWebExtensionHandler` reads it from `SFExtensionMessageKey`, decodes it into `ExtensionRequest` and hands it to `MessageRouter`, which answers with an `ExtensionResponse`. The background script parses the answer the same way and replaces anything malformed with `{ "type": "error", "reason": "unreadable reply" }` before the page sees it.

The content script runs in the top frame of `https` pages only, plus plain `http` on `localhost` and `127.0.0.1` for testing, once the page has loaded (`document_idle`). The manifest still matches every `http` and `https` page, because Safari only offers the All Websites switch for a pattern that covers every site, so the script itself bails out anywhere else and checks that it is in a secure context and the top frame, and the background script checks the page's address again. Frames are left out so an embedded widget from another site can't reorder the card or record values under its own host, and plain `http` is left out so a network attacker can't feed values to the card. A page without email, phone or address fields sends nothing.

Every message is a JSON object with a `type` field. The Swift types live in `Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift` and the TypeScript types in `web/src/messages.ts`. Both use the same field names. The examples below are copied from `docs/message-examples.json`, which the Swift and Vitest suites both load, so a renamed field fails a test on each side.

Contact values only travel from the page to the app. No response carries an email, phone number or address back to the page. Safari's Prefill sheet (below) is one place values come back, and it is an extension page, so the background script never relays its messages from a page or hands its replies to one. `contactSuggestions`, sent only in Chrome and Arc, is another (see below). The last is `linkSuggestions`: profile and website links do go back to the page, into a datalist the page can read, but only for a field that asks for them and only once the person focuses it.

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
| `linkSuggestions` types | 5 |
| `linkSuggestionsResult` links | 10, at most 3 of a type |
| `contactSuggestionsResult` | 5 emails, 5 phone numbers, 5 addresses |

## Shared values

| Name | Values |
| --- | --- |
| Field kind | `email`, `phone`, `address`, `name`, `link` |
| Link type | `github`, `website`, `linkedin`, `x`, `other` |
| Section hint | `home`, `work`, `shipping`, `billing`, taken from the field's `autocomplete` tokens |
| Sync status | `unchanged`, `saved`, `failed`, `off`, `notSetUp` |
| Sheet status | `ready`, `off`, `notSetUp`, `failed` |
| Recent state | `saved`, `waiting`, `removed` |

The `enums` block in `docs/message-examples.json` lists these values. The Swift suite checks it against `FieldKind`, `LinkType`, `SectionHint` and `SyncStatus`, and the Vitest suite checks it against the arrays the TypeScript types and validators are built from.

A `name` field is never saved. The capture filter only uses it to tell whether a form is about the person.

A `link` field asks for a profile or website address, such as a job application's "GitHub/Portfolio:" or "LinkedIn:" question. The content script reads that from the field's label, name, id or placeholder (GitHub, portfolio, website, personal site, homepage, URL, LinkedIn, Twitter, x.com, other website), or from `type=url` and `autocomplete="url"`, which ask for a website. A field can ask for several link types, in the order its words name them. A link's type comes from its host: github.com, linkedin.com, x.com and twitter.com, and `website` for any other. On the card a link is one of the contact's URL addresses, labeled GitHub, LinkedIn, X or homepage. Link fields are never part of `pageContext`, since Safari's contact bar doesn't show links.

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

The reply is `pageContextResult`. Its `status` is `saved` when the card was rewritten, `unchanged` when the first two values already fit or when pages have already rewritten the card six times in the last minute, `off` when Match each site is turned off, `notSetUp` when the person hasn't linked their card in Prefill yet, and `failed` when the card could not be read or saved. A failure includes a `reason` written for people. The content script only uses the status, to keep a retry for the next focus after `failed` or `error`; nothing shows the reason yet.

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

## linkSuggestions

The content script asks for the card's links of the types a page's `link` fields want once the page has loaded, because Safari reads a field's list as the field takes focus and the app's answer would come too late. It asks again each time the person focuses a `link` field (within a second of a click or tap on the field or its label, or a press of Tab, while the field is on screen and has no `list` of its own; a page that focuses a field from script gets nothing), which also covers fields a page adds later. The reply lists them in the person's order on the card, up to three of each type the request names, always as full `http` or `https` addresses. Before the card is linked, or when it can't be read, `links` is empty.

| Field | Type | Meaning |
| --- | --- | --- |
| `host` | string | The page's host name. |
| `types` | array of link types | What the field asks for, first wanted first. |

```json
{ "type": "linkSuggestions", "host": "boards.example.io", "types": ["github", "website"] }
```

```json
{
  "type": "linkSuggestionsResult",
  "links": [
    { "type": "github", "url": "https://github.com/alexrivera" },
    { "type": "website", "url": "https://alexrivera.dev" }
  ]
}
```

The content script then gives the field a `list` and adds a `<datalist>` of up to three options, which Safari's QuickType bar shows on fields it doesn't fill from the card (REPORT.md, Spike results). A field that asks for two types gets both in one option first (`github.com/alexrivera - alexrivera.dev`), then each alone; a field that asks for one type gets that type's links. Options leave out the scheme and trailing slash, which keeps them short in the bar, except in a `type=url` field, which gets whole addresses and no combined option. The content script attaches them when the field takes focus, from the links it already has, and the `list` and the datalist go away when the field loses focus. Any script on the page can read the datalist while it is there, so a page can learn the links its fields ask for once the person focuses one.

## contactSuggestions

Chrome and Arc fill contact fields from their own saved addresses, never from the card, so in those browsers the content script doesn't send `pageContext` and the card's order never changes for a Chrome page. It sends `contactSuggestions` instead, once the page has loaded and again each time the person focuses a contact field (after a click, tap or Tab, as for links, on an `input` of type text, email, tel or search without a `list` of its own). `fields` has one entry per kind and section on the page. The reply holds the card's values of those kinds in the order the card would take on this site (the same ranking `pageContext` uses: pins, use on the site, section hints, site kind), up to five of each, without saving the card. `name` is the card's given and family name. Before the card is linked, or when it can't be read, every list is empty.

```json
{
  "type": "contactSuggestions",
  "host": "shop.example.net",
  "fields": [{ "kind": "email" }, { "kind": "address", "section": "shipping" }, { "kind": "name" }]
}
```

```json
{
  "type": "contactSuggestionsResult",
  "emails": ["alex@work.example.org", "alex.rivera@example.com"],
  "phones": [],
  "addresses": [
    { "street": "2400 Durant Ave", "city": "Berkeley", "state": "CA", "postalCode": "94704", "country": "United States" }
  ],
  "name": { "given": "Alex", "family": "Rivera" }
}
```

The focused field gets a `list` and a `<datalist>` with the values its part asks for: emails, phone numbers (none for a phone part such as an area code), the first street line, the second, the city, state, postal code or country of each address, or the full, given or family name. Chrome shows the options in its own autofill dropdown under any addresses it has saved. As with links, any script on the page can read the datalist while it is there.

In Chrome and Arc the messages travel through a native messaging host (`com.tarunyadgirkar.prefill`, inside Prefill.app on the Mac) rather than Safari's handler. Each message is a 32-bit little-endian length followed by that many bytes of JSON. The host checks a request against every rule here, rebuilds it from its known fields and passes it to the running Mac app over a Unix socket only Prefill's own signed host may use, so the host never touches Contacts.

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

The app uses `autocomplete`, `name` and `label` to skip fields meant for someone else, such as a gift recipient or an invite, and checks each value: an email must be a single address with a valid domain, a phone number 7 to 15 digits with only the usual separators (and not a card number or a bare code), an address free of links and control characters, and a link a single `http`, `https` or scheme-less web address with a valid domain. A link is saved with `https://` in front when it had no scheme, labeled by its type.

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

The reply is `captureResult`, with counts only. `saved` values went onto the card (ranked first for this site when Match each site is on, and placed after the person's own order when it is off), `review` values wait in Recently added for the person to confirm, and `ignored` fields were skipped. A value already on the card counts toward none of the three, since only its use on this site is recorded, and only when Match each site is on. A new value goes straight onto the card only when the form also holds something already on the card that the person typed themselves: one of its emails, phones or addresses, or its full name (given and family, in one box or split across two). A password box, tags or a lone first name are not enough, since a page controls them. Values go to review instead of the card without that, when the report has `trigger: "flush"`, when the card can't be written, or past the save limits: three new values per form and six per hour across all sites. One site can file at most 20 values for review a day; past that its values count as `ignored`. Before the person has linked their card, or when the card can't be read, the app stores nothing and every field counts as `ignored`.

```json
{ "type": "captureResult", "saved": 1, "review": 0, "ignored": 1 }
```

## The Prefill sheet

Tapping Prefill in Safari's page menu opens `popup.html` as a half-height sheet. It asks the active tab's content script `{ "type": "pageNeeds" }`, which answers with the page's host and the kinds of contact fields it has (`email`, `phone`, `address`); the content script only answers this extension, in the top frame of a page it runs on. The sheet takes the host from the tab's address when Safari shares it and from that answer otherwise, and shows nothing in Private Browsing. It then sends the messages below straight to the app with `browser.runtime.sendNativeMessage`, and clears the page-menu badge for the tab.

Every sheet request carries the `host` it is about, checked like any other host, and every reply is `popupStateResult`. Kinds are `email`, `phone` or `address`; a value ID is the UUID the app gives each value. Before the card is linked the reply is `notSetUp`, and when the card can't be read or saved it is `failed` with a `reason`.

| Request | Fields | What the app does |
| --- | --- | --- |
| `popupState` | `host`, `kinds` (at most 3) | Reads the card and plans this site's order without saving. |
| `pin` | `host`, `kind`, `valueID` | Records the pick for the site, rewrites the card so the value is first, and answers for that kind. Does nothing with Match each site off. |
| `unpin` | `host`, `kind` | Takes the pick back and rewrites the card the same way. |
| `undoCapture` | `host`, `valueID` | For a value captured on this site: takes it off the card if it was saved, or turns it down if it was waiting for review. Either way later forms don't save it again. A value the person put on the card is never removed. |
| `muteSite` | `host`, `muted` | Turns "Don't save on this site" on or off. While it is on, a `capture` from the site is dropped whole. |

These are recorded as events (`pins`, `mutes`, and a `dismissed` capture for an undo), since only the app writes AppState. The app folds them in when it reads the store, and the handler reads through the same fold, so a choice counts right away.

```json
{ "type": "pin", "host": "shop.example.net", "kind": "email", "valueID": "5E1D7C1A-8C1B-5F0E-9A6B-2C4D6E8F0A1B" }
```

The reply lists, for each kind asked about, every value in the order Safari will offer them on the site (the first two are the bar's two slots), with the label as the bar captions it and the value on one line. `pinnedID` is the value picked for the site, if any. `recent` holds up to five values saved from the site, newest first, and `muted` says whether the site is muted.

| Limit | Value |
| --- | --- |
| Kinds per reply | 3 |
| Values per kind | 30 |
| `recent` | 5 |
| `caption` | 100 UTF-16 units |
| `text` | 1,000 UTF-16 units, cut short by the app, with line breaks and hidden characters turned into spaces |

```json
{
  "type": "popupStateResult",
  "status": "ready",
  "kinds": [
    {
      "kind": "email",
      "pinnedID": "5E1D7C1A-8C1B-5F0E-9A6B-2C4D6E8F0A1B",
      "values": [
        { "id": "5E1D7C1A-8C1B-5F0E-9A6B-2C4D6E8F0A1B", "caption": "work", "text": "alex@work.example.org" },
        { "id": "0B3E5A7C-9D1F-5B2A-8C4E-6F8A0B2C4D6E", "caption": "home", "text": "alex.rivera@example.com" }
      ]
    }
  ],
  "recent": [
    {
      "kind": "email",
      "state": "saved",
      "value": { "id": "7A9C1E3B-5D7F-5A1C-8E2B-4D6F8A0C2E4A", "caption": "email", "text": "alex.new@example.net" }
    }
  ],
  "muted": false
}
```

When a `capture` reply has values waiting for review, the background script puts that count on Prefill's row in the page menu for the tab with `browser.action.setBadgeText`. Values saved straight to the card leave no badge, since the sheet's Undo covers them.

## error

The handler answers `error` when a message is not valid JSON, has an unknown `type`, is missing a required field, or is over the size limits.

```json
{ "type": "error", "reason": "unknown message" }
```
