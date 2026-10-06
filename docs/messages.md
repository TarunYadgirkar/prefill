# Messages between the extension and the app

The content script sends a message to `background.js` with `browser.runtime.sendMessage`. The background script turns away any message that Safari doesn't say came from this extension's content script in the top frame of a normal tab showing an `https` page (or plain `http` on `localhost` and `127.0.0.1`), or in a frame whose own address is an `https` page on one of the job application hosts listed below. Messages from Private Browsing tabs never reach the app, and neither does one from a tab that doesn't say whether it is private. It then parses the message with `parseExtensionRequest`, which rebuilds it from the fields below and drops anything else, replaces `host` with the host of the page or frame Safari says sent it, and forwards the result with `browser.runtime.sendNativeMessage`. `SafariWebExtensionHandler` reads it from `SFExtensionMessageKey`, decodes it into `ExtensionRequest` and hands it to `MessageRouter`, which answers with an `ExtensionResponse`. The background script parses the answer the same way and replaces anything malformed with `{ "type": "error", "reason": "unreadable reply" }` before the page sees it.

The content script runs in the top frame of `https` pages, plus plain `http` on `localhost` and `127.0.0.1` for testing, once the page has loaded (`document_idle`). It also runs in a frame that shows a job application form company career pages embed, when the frame's own address is `https` on one of these hosts (`web/src/atsFrames.ts`), and the frame is a secure context (so not inside a plain `http` page):

| Match | Hosts |
| --- | --- |
| Exact host | `boards.greenhouse.io`, `boards.eu.greenhouse.io`, `job-boards.greenhouse.io`, `job-boards.eu.greenhouse.io`, `jobs.lever.co`, `jobs.eu.lever.co`, `jobs.ashbyhq.com`, `apply.workable.com`, `jobs.smartrecruiters.com` |
| That domain or any subdomain | `myworkdayjobs.com` |

Such a frame works under its own host, not the host of the page around it: its `pageContext`, captures and suggestions are for `boards.greenhouse.io`, say, and the career page's top frame runs separately under its own host. The manifest still matches every `http` and `https` page in every frame, because Safari only offers the All Websites switch for a pattern that covers every site, so the script itself bails out anywhere else, before adding any listener, and checks that it is in a secure context and the top frame or a listed frame, and the background script checks the sender's address and frame again. Other frames are left out so an embedded widget from another site can't reorder the card or record values under its own host, and plain `http` is left out so a network attacker can't feed values to the card. A page without email, phone or address fields sends nothing.

Every message is a JSON object with a `type` field. The Swift types live in `Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift` and the TypeScript types in `web/src/messages.ts`. Both use the same field names. The examples below are copied from `docs/message-examples.json`, which the Swift and Vitest suites both load, so a renamed field fails a test on each side.

Contact values only travel from the page to the app. No response carries an email, phone number or address back to the page. Safari's Prefill sheet (below) is one place values come back, and it is an extension page, so the background script never relays its messages from a page or hands its replies to one. `contactSuggestions` is another (see below): in Chrome and Arc it carries the card's values, and in Safari only the values a minimal card moved to Prefill's contact, and `customSuggestions` answers a field with the person's own custom fields that match it. The last is `linkSuggestions`: profile and website links do go back to the page, into a datalist the page can read, but only for a field that asks for them and only once the person focuses it. Each value in these three replies also says why it is offered and carries its label, and a learned answer the site it was saved from, so a page that can read Prefill's values also learns where one of them was learned.

Both sides enforce the same size limits (`LIMITS` in `messages.ts`, `MessageLimits` in Swift) and the same shape rules: `host` is a lowercase host name (letters, digits, dots and dashes), no text may hold control, format (bidi overrides, zero-width characters) or line separator characters (a street may hold plain newlines), and an `address` field carries `address` and no `value` while every other kind carries `value` and no `address`. The handler answers `error` to anything that breaks them. Text lengths count UTF-16 units, as JavaScript's `length` does.

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
| `customSuggestions` fields | 40, each `text` 200 characters |
| `customSuggestionsResult` | one entry per field asked about, each with at most 3 values of 200 characters |
| `answers` | 8 answers, each `value` 200 characters |
| `picked` | `value` 256 characters, `question` 200 characters |

## Shared values

| Name | Values |
| --- | --- |
| Field kind | `email`, `phone`, `address`, `name`, `link` |
| Link type | `github`, `website`, `linkedin`, `x`, `other` |
| Section hint | `home`, `work`, `shipping`, `billing`, taken from the field's `autocomplete` tokens |
| Sync status | `unchanged`, `saved`, `failed`, `off`, `notSetUp` |
| Sheet status | `ready`, `off`, `notSetUp`, `failed` |
| Recent state | `saved`, `waiting`, `removed` |
| Why | `pinned`, `used`, `card`, `learned`, `guess`, `resume` |

The `enums` block in `docs/message-examples.json` lists these values. The Swift suite checks it against `FieldKind`, `LinkType`, `SectionHint` and `SyncStatus`, and the Vitest suite checks it against the arrays the TypeScript types and validators are built from.

Every value a suggestion reply carries back says why it is offered, so Prefill's list can say so under it:

| `why` | Meaning |
| --- | --- |
| `pinned` | The person picked it on this site before. |
| `used` | The person typed or picked it on this site before. |
| `card` | It is on the person's card or Prefill's contact. `label` is the card's label as Safari's bar captions it (`work`, `home`), or the custom field's label (`School`), and is left out for an unlabeled value. |
| `learned` | Prefill saved it from a form the person submitted. `site` is the registrable domain it was saved from. |
| `guess` | The on-device model's pick. Only `customSuggestionsResult`'s `guesses` are guesses, so they carry no `why` of their own. |
| `resume` | From a resume import (not yet sent). |

`pinned` and `used` need Match each site on. A `label` is at most 100 characters.

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
    { "type": "github", "url": "https://github.com/alexrivera", "why": "pinned" },
    { "type": "website", "url": "https://alexrivera.dev", "why": "card" }
  ]
}
```

A link's `why` is `pinned` for the one picked on this site and `card` for the rest.

The content script then gives the field a `list` and adds a `<datalist>` of up to three options, which Safari's QuickType bar shows on fields it doesn't fill from the card (REPORT.md, Spike results). A field that asks for two types gets both in one option first (`github.com/alexrivera - alexrivera.dev`), then each alone; a field that asks for one type gets that type's links. Options leave out the scheme and trailing slash, which keeps them short in the bar, except in a `type=url` field, which gets whole addresses and no combined option. The content script attaches them when the field takes focus, from the links it already has, and the `list` and the datalist go away when the field loses focus. Any script on the page can read the datalist while it is there, so a page can learn the links its fields ask for once the person focuses one.

## contactSuggestions

Chrome and Arc fill contact fields from their own saved addresses, never from the card, so in those browsers the content script doesn't send `pageContext` and the card's order never changes for a Chrome page. It sends `contactSuggestions` instead, once the page has loaded and again each time the person focuses a contact field (after a click, tap or Tab, as for links, on an `input` of type text, email, tel or search without a `list` of its own). `fields` has one entry per kind and section on the page. The reply holds the card's values of those kinds in the order the card would take on this site (the same ranking `pageContext` uses: pins, use on the site, section hints, site kind), up to five of each, without saving the card. Each is an object with the `value` (for an address, `address` with its parts), its `why` (`pinned`, `used` or `card`) and its `label`. `name` is the card's given and family name. Before the card is linked, or when it can't be read, every list is empty.

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
  "emails": [
    { "value": "alex@work.example.org", "why": "pinned", "label": "work" },
    { "value": "alex.rivera@example.com", "why": "used" }
  ],
  "phones": [],
  "addresses": [
    {
      "address": { "street": "2400 Durant Ave", "city": "Berkeley", "state": "CA", "postalCode": "94704", "country": "United States" },
      "why": "card",
      "label": "home"
    }
  ],
  "name": { "given": "Alex", "family": "Rivera" }
}
```

In Safari, where the bar fills contact fields from the card, the content script still sends `pageContext` and also sends `contactSuggestions` with `"offCard": true`, asking only for values the person moved off a minimal card (Settings > Sharing your card). The reply then leaves out every value still on the card and the name, and is empty unless the card is minimal. Safari's bar shows a datalist only when the card has nothing for the field (REPORT.md, Spike results), so these emails and address parts reach the bar on a card that holds just a name and phone number; the phone field keeps the card's own suggestion.

```json
{ "type": "contactSuggestions", "host": "boards.example.io", "fields": [{ "kind": "email" }], "offCard": true }
```

The focused field gets a `list` and a `<datalist>` with the values its part asks for: emails, phone numbers (none for a phone part such as an area code), the first street line, the second, the city, state, postal code or country of each address, or the full, given or family name. Safari shows at most three of them in its bar, values only, and WebKit also opens its own list under the field. In Chrome and Arc Prefill draws its own list instead. As with links, any script on the page can read the datalist while it is there.

## customSuggestions

A custom field is an answer of the person's own that has no place on a contact card, such as "School" = "UC Berkeley", "Major" = "EECS" or "How did you hear about us" = "LinkedIn". Each has a label, a value and optional extra match words ("university, college" for School). The person adds them in the app's Custom tab on iPhone or in the Mac app's settings.

They live on the card itself, so iCloud Contacts carries them between the iPhone and the Mac without an App Group or CloudKit. Each one is one of the card's related names: the value is the name, and the label is the field's label followed by ` · Prefill` and any match words, such as `School · Prefill · university, college`. Contacts shows that as an ordinary related name ("School · Prefill" over "UC Berkeley"). Prefill only reads and writes related names whose label carries that marker, so a spouse or parent on the card is never touched, and a card rewrite that reorders values leaves every related name exactly as it was (the save is refused if it wouldn't). A custom label or value may not hold line breaks or the `·` character. The limits: 20 fields, a label of 40 characters, a value of 200, and 100 characters of match words.

The content script sends `customSuggestions` once the page has loaded, and again for one field each time the person focuses it (after a click, tap or Tab, as for links). It covers text inputs without a `list` of their own that nothing else claims: not a contact or link field, no `autocomplete` token, nothing sensitive or of `type=password`, not a search box, and not on a sign-in form. Text areas and selects never show a datalist, so they are left out. Each entry's `text` is the field's label, placeholder, name and id, joined, with hidden characters turned into spaces and cut to 200 characters.

The app splits each text into lowercase words (at camelCase, digits and punctuation), drops filler words such as "your" and "how", and drops a plural "s". A custom field's label and each of its match words is a phrase; a phrase matches when all its words appear in the field's words, so "Graduation year" matches "Expected graduation year" but not "Year of birth". The custom field whose matching phrase has the most words wins, and fields that tie are all offered, up to three, in the card's order. The reply has one entry per field asked about, in order. Each value carries the custom field's `label` and `why`: `learned` with the `site` it was saved from when Prefill learned it from a form and it still reads as learned, else `card`. Before the card is linked, or when it can't be read, every list is empty.

A field no rule matched may carry a `guesses` entry: the saved answer Apple's on-device model picked for that question, shown in the field's list with a "Suggested" caption and never filled in by one-tap fill. The handler never runs the model itself. It records the question's words (never what the person typed) in the events as a `FormQuestion`, the app asks the model about each one the next time it opens, and caches the answer by label in `AppState.insights` (or "none"), which the handler then serves. On the Mac, the app's own panel asks the model live.

```json
{
  "type": "customSuggestions",
  "host": "boards.example.io",
  "fields": [{ "text": "School job_application[educations][0][school_name_id]" }, { "text": "Cover letter" }]
}
```

```json
{
  "type": "customSuggestionsResult",
  "fields": [
    { "values": [{ "value": "UC Berkeley", "why": "card", "label": "School" }], "guesses": [] },
    { "values": [{ "value": "Yes", "why": "learned", "label": "Work authorization", "site": "example.io" }], "guesses": [] },
    { "values": [], "guesses": ["EECS"] }
  ]
}
```

The focused field gets a `list` and a `<datalist>` of its values, which Safari's QuickType bar shows (Safari has no contact suggestion of its own for such a field) and Chrome and Arc show in their dropdown. As with links, any script on the page can read the datalist while it is there.

In Chrome and Arc the messages travel through a native messaging host (`com.tarunyadgirkar.prefill`, inside Prefill.app on the Mac) rather than Safari's handler. Each message is a 32-bit little-endian length followed by that many bytes of JSON. The host checks a request against every rule here, rebuilds it from its known fields and passes it to the running Mac app over a Unix socket only Prefill's own signed host may use, so the host never touches Contacts.


## answers

Prefill learns the answers a person gives on job applications. When the person submits a form (a submit event within a second of their own click on the form's submit button or Enter in one of its fields, because a script's `requestSubmit()` also makes a trusted submit event), the content script looks at the text inputs, selects and radio groups they changed themselves, drops any whose value or question has changed since the person's last edit, and keeps the ones that ask one of eight questions: `school`, `degree`, `major`, `gpa`, `graduation`, `authorization`, `sponsorship` and `heard` (how did you hear about us). Demographic questions, sign-in forms, contact fields and anything sensitive are never read, and a value Prefill filled in is not sent because the person didn't change it.

With `action: "learn"` the app saves each answer whose question has no custom field yet, with that question's label and match words, up to the 20-field limit. When the question's custom field holds a different answer that Prefill learned from an earlier form and that still reads exactly as learned, the new answer replaces it, keeping the field's label and match words; the old answer is kept in the event for Undo. A custom field the person wrote or edited in the app is never replaced. New and replaced answers together count toward at most 8 a day across every site. A save that only adds may only add custom fields after the ones there (`CardSaveScope.addAnswers`); one that replaces is a person's edit (`personEdit`). It saves nothing when Save new info is off, the site is muted or the card isn't linked. The reply says how many answers were saved and how many `updated`, and the page then shows a pill, "Saved 2 answers", "Updated your answer" or "Saved 1 answer and updated 1", with Undo, for 8 seconds.

Undo sends `action: "undo"` with no answers. The app takes back the answers saved from that site in the last 10 minutes that are still exactly as saved: a new one comes off and a replaced one goes back to the answer it replaced. It replies with how many changed back in `saved`.

```json
{
  "type": "answers",
  "host": "boards.example.io",
  "action": "learn",
  "answers": [{ "question": "school", "value": "UC Berkeley" }, { "question": "sponsorship", "value": "No" }]
}
```

```json
{ "type": "answersResult", "saved": 2, "updated": 1 }
```

## picked

When the person picks a value from Prefill's list under a field (a trusted click on a row, or Enter on a highlighted row), the content script tells the app, so the value comes first on that site from the next focus on. It doesn't report a pick of the value that was already first, and never a value the page filled in. `kind` is `email`, `phone`, `address`, `link` or `custom`. `value` is the text that went into the field: for an address, the street line. A `custom` pick also carries `question`, the field's own words.

For an email, phone number, address or link, the app looks for the value among the person's own values (an address by its street line) and, when it finds one, records a pin for the site's registrable domain and a use of the value there, like a pick in the Prefill sheet but without rewriting the card. A value the person doesn't have is never pinned. A picked link comes first in `linkSuggestions` for that site; a site keeps one picked link. For a `custom` pick the app finds the custom field holding that value and remembers it for the question's words (lowercased, without filler words, in any order), so `customSuggestions` offers it first for any field with the same words on any site, when that field's matches include it or nothing matched (the pick then stands in for a guess). A pick never brings an answer to a field that matched other answers. An empty `value` is ignored. A picked guess then comes back as one of the field's `values`, so Fill form fills it from then on. Contact and link picks do nothing with Match each site off; custom picks don't depend on it. At most 10 picks a minute are kept across every site. The reply says whether the pick was remembered; the page doesn't act on it.

```json
{ "type": "picked", "host": "boards.example.io", "kind": "email", "value": "alex.rivera@example.com" }
```

```json
{ "type": "pickedResult", "remembered": true }
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

Tapping Prefill in Safari's page menu opens `popup.html` as a half-height sheet. It asks the active tab's content script `{ "type": "pageNeeds" }`, which answers with the page's host, the kinds of contact fields it has (`email`, `phone`, `address`) and `fillable`, the number of empty fields a one-tap fill would fill; the content script only answers this extension, in the top frame of a page it runs on. The sheet takes the host from the tab's address when Safari shares it and from that answer otherwise, and shows nothing in Private Browsing. It then sends the messages below straight to the app with `browser.runtime.sendNativeMessage`, and clears the page-menu badge for the tab.

Every sheet request carries the `host` it is about, checked like any other host, and every reply is `popupStateResult`. Kinds are `email`, `phone` or `address`; a value ID is the UUID the app gives each value. Before the card is linked the reply is `notSetUp`, and when the card can't be read or saved it is `failed` with a `reason`.

| Request | Fields | What the app does |
| --- | --- | --- |
| `popupState` | `host`, `kinds` (at most 3) | Reads the card and plans this site's order without saving. |
| `pin` | `host`, `kind`, `valueID` | Records the pick for the site, rewrites the card so the value is first, and answers for that kind. Does nothing with Match each site off. |
| `unpin` | `host`, `kind` | Takes the pick back and rewrites the card the same way. |
| `undoCapture` | `host`, `valueID` | For a value captured on this site: takes it off the card if it was saved, or turns it down if it was waiting for review. Either way later forms don't save it again. A value the person put on the card is never removed, nor one already undone or turned down that they put back by hand. |
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

## One-tap fill

The pill Prefill shows beside a field the person just clicked or tabbed into, and the Fill button at the top of Safari's sheet, fill the whole form the field is in. The content script asks the app the same three questions the field lists use, once each and only for what the form needs: `contactSuggestions` (without `offCard`, also in Safari, since it fills the fields itself), `linkSuggestions` and `customSuggestions`, whose `text` for a select is its label and for a radio group its legend or question. Nothing new reaches the page that a field's own list wouldn't offer; the difference is that one tap places every value at once.

The sheet talks to the page's content script, not to the app, with two messages only this extension's pages can send:

```json
{ "type": "fillPage" }
{ "type": "undoFill" }
```

Both answer `{ "type": "fillPageResult", "filled": 11 }`, the number of fields filled (0 after an undo).

What a page can and can't do: it can't press the pill (a closed shadow root that ignores untrusted clicks and any tap in its first 400 ms) or send the sheet's messages. It can still lure a person into tapping where the pill appears, the same risk Prefill's own list has; the pill only appears right after the person's own click or Tab into a field, and a fill only reaches visible, empty, non-sensitive fields of that form.

## error

The handler answers `error` when a message is not valid JSON, has an unknown `type`, is missing a required field, or is over the size limits.

```json
{ "type": "error", "reason": "unknown message" }
```
