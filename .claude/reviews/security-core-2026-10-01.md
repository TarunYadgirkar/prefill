Prefill security and privacy review, commit 8ae9427. Read-only; no files modified.

One thing first. At this commit nothing in the capture path is exploitable yet. `MessageRouter.swift:16` answers "not handled yet" for `pageContext` and `capture`, and `content.ts` only sends `ping`. The Critical and High items below are latent. The decision logic and message contract that Phase 2 will plug into already encode the unsafe trust assumptions.

Two facts differ from the brief:
- The manifest has no `all_frames`, so the content script runs in the top frame only (`Extension/Resources/manifest.json:22-26`). `docs/messages.md:23` says the same.
- The repo is PUBLIC (`gh repo view`).

## CRITICAL (becomes exploitable the moment Phase 2 wires capture)

**C1. A page can get attacker-chosen values saved to the real contact card with no user input.**
- Where:
  - `CaptureFilter.swift:63-71` (`decide`)
  - `CaptureFilter.swift:133-137` (`isCorroborated`: `!ownSections.isEmpty` is enough)
  - `CaptureFilter.swift:139-144` (`isTaggedInAccountForm`)
  - `web/src/messages.ts:120-135` (the contract carries no provenance)
  - `spikes/capture/Extension/Resources/content.js:39-40` and `:85-92` (the pattern Phase 2 mirrors)
- Every signal that promotes a value to `.save` is controlled by the page:
  - `hasPassword`: a hidden `<input type=password>` is enough.
  - The `autocomplete` and `name` attributes.
  - A `name` field whose words are a subset of the card's name. A single word such as "Alex" passes (`OwnerName.matches`).
- The spike collector reads every non-`type=hidden` input: CSS-hidden, off-screen and script-set fields included. It has no `isTrusted` check and no user-typed check on `submit`, `click`, `pagehide` or `visibilitychange`.
- The current tests assert this behaviour. `aTaggedEmailInASignUpFormIsSaved` and `aNewValueNextToYourNameIsSaved` both expect `.save`.
- Exploit:
  1. The victim opens a page.
  2. The page script fills `<input autocomplete=email value=attacker@evil.com hidden-by-CSS>` and a hidden password input.
  3. It calls `form.requestSubmit()`.
  4. The `submit` event is UA-dispatched, so `isTrusted` is true and there is no user gesture. Verify this on Safari in the Phase 2 test.
  5. The handler saves `attacker@evil.com` to the card.
- Impact:
  - The value syncs to iCloud and appears in the QuickType bar. On small cards it is boosted into the visible slots on every site (see M3).
  - The person can then autofill an attacker email, phone or address into account-recovery or shipping forms.
  - The saved capture also records a usage event for the attacker's host.
- Fix, content script (the real gate):
  - Keep a `WeakMap<field, snapshot>` filled only from capture-phase `input` and `change` events with `isTrusted === true`, registered on `window` at `document_start`.
  - Send only fields in that map, and only if the live value still equals the snapshot.
  - Require visibility: `checkVisibility()`, non-zero rect, not `inert` or `aria-hidden`, not disabled or readonly.
  - Require `event.isTrusted` plus `navigator.userActivation.isActive` at submit time.
  - Compute `hasPassword` only from a visible password input.
- Fix, contract:
  - Add per-field `userTyped: true` and a top-level `trigger: "submit" | "flush"`.
- Fix, native:
  - Never promote to `.save` from `hasPassword` or an own-name word alone. Auto-save needs a card-matching value typed in the same form.
  - A `flush` trigger (abandoned form on `pagehide`) is always `.review`.
  - Add tests with a hidden-field fixture and a script-submitted fixture.

## HIGH

**H1. Card numbers and other digit strings can be saved as phone numbers.**
- Where:
  - `CaptureFilter.swift:92`
  - `FieldWords.swift:8-33`
  - `spikes/capture/.../content.js:20` (`type === "tel"` returns phone before any name or label check)
- Phone acceptance is: 7 or more `Character.isNumber` characters, no maximum, any other text allowed. `isNumber` also accepts ½, ², ٣ and similar.
- The sensitive-word check needs exact word equality against `password, passcode, otp, cvv, cvc, csc, ssn`, plus the substring `cardnumber`. These all slip through: `cvv2`, `ccnum`, `cc_num`, `card_no`, `pwd`, `passwd`, `pin`, `securitycode`, `routing`, `account`, `iban`, `social`, `dob`, `token`, `mfa`.
- Many sites use `type=tel` for card number, ZIP, DOB, SSN and bank numbers, often without `autocomplete=cc-number`.
- Scenario: a checkout field `<input type=tel name=ccnum>` in a form with an email already on the card. `isCorroborated` is true, so `.save(.phone("4111111111111111"))` writes the card number onto the contact card, syncs it to iCloud and offers it in the phone slot.
- Fix:
  - Classify phone only on positive evidence: a `tel*` autocomplete token, or name or label matching phone words. Never on `type=tel` alone.
  - Run a negative-pattern pass first (card, cc, cvv, pan, expir, routing, account, iban, ssn, social, tax, dob, birth, pin, otp, code, token, secret, pass, pwd).
  - In Swift, accept phone only if it has characters `[0-9+()\-. ]`, ASCII digits, 7 to 15 digits, and is not a Luhn-valid 13 to 19 digit run.
  - Exclude any field that has ever been `type=password`. Observe `type` mutations; "show password" toggles turn it into `type=text`.

**H2. Private Browsing is not handled.**
- `research/REPORT.md:143` says "Since Safari 17 a site grant covers all profiles and Private Browsing". The plan never mentions incognito.
- Private tabs would therefore:
  - send `pageContext` and `capture`;
  - write card values and card reorders;
  - record `host` into `UsageEvent` and `Capture` in the Keychain. That history outlives the private session.
- Fix:
  - In `background.ts`, drop every message unless `sender.tab?.incognito === false` (fail closed).
  - Verify on iOS 27 that Safari populates `sender.tab.incognito`. If it does not, tell the person that Private Browsing is not covered.
  - Add a test.

**H3. No size or semantic limits anywhere.**
- Where:
  - `messages.ts:84` (strings), `messages.ts:99-106` (`arrayOf`, `shape`)
  - `relay.ts:6` (forwards the original object, extra keys included)
  - `Messages.swift:55-88` (Codable, no bounds)
  - `CaptureFilter.swift:32-39` and `:98-102`
  - `Documents.swift:45-66` (`maxCaptures` and `maxUsage` cap counts only; the "about 400 bytes per capture" comment is false without a per-value cap)
- Weaknesses:
  - Unbounded `fields`, `host`, `value`, `name`, `label`, `autocomplete` and extra keys.
  - Sparse arrays pass `every`.
  - `evaluate` is O(n²) (`decide` and `isCorroborated`), so n large means handler jetsam.
  - `isEmail` only checks one `@` and a dot in the domain. It accepts internal whitespace, newlines, control characters, bidi overrides (U+202E), zero-width characters, `<>` and quotes, and any length. These go onto the real card and into the review UI.
- Failure scenarios:
  - A 50 MB `value` is stored in the `ext-events` Keychain item. `appendEvents` then throws forever. Only `DecodingError` is recovered (`KeychainStore.swift:40-47`). The item survives uninstall (M1), so the DoS persists.
  - 200 junk captures evict the person's pending reviews and Undo records through `suffix(maxCaptures)`.
- Fix:
  - Validate in JS and again in Swift. Suggested caps: host at most 253 characters `[a-z0-9.-]`, at most 32 fields, email at most 254 ASCII with local part at most 64, phone at most 32 characters, address parts at most 120 characters, `autocomplete`, `name` and `label` at most 64 characters, whole message at most 8 KB.
  - Reject Cc, Cf, Zl and Zp characters.
  - Reject kind/payload mismatches.
  - Rebuild the outgoing payload from an allow-list instead of forwarding the page-derived object.
  - Cap the Keychain document by bytes. A failed events write must never block card operations.

## MEDIUM

**M1. PII persists after uninstall.**
- `KeychainStore.swift:74` and `:49-54`.
- iOS keeps Keychain items after the app is deleted. They hold `AppState.values`, `CardLink.original` (the full original card), site pins, usage hosts and raw captured values.
- `removeAll()` exists only on `KeychainStore`. It is not on `SharedStore`, `AppGroupStore` has no equivalent, and nothing calls it.
- Fix:
  - Add `removeAll()` to the protocol.
  - Add a Settings "Delete Prefill data" action.
  - Purge on first launch using a `UserDefaults` sentinel. `UserDefaults` is deleted with the app, the Keychain is not.
  - Consider a time-to-live on usage hosts.

**M2. `background.ts:5-7` trusts the message.**
- No check of `sender.id`, `sender.tab`, `sender.frameId` or `sender.url`, and `host` comes from the message.
- Fix: require `sender.id === browser.runtime.id`, `sender.tab` present, `frameId === 0` and an `https:` `sender.url`. Overwrite `host` with `new URL(sender.url).hostname`. Make the check structural.
- No exploitable page-to-extension message path exists. Safari has no externally-connectable messaging and the manifest sets none. This is defense in depth.

**M3. Any page can rewrite the real card and skew ranking without a user gesture.**
- Where: `pageContext` flow, `CardWriter.swift:96`, `Ranker.swift:89-94`.
- A page sends `pageContext` on load and on every `focusin`. A script-called `focus()` still yields UA focus events. Alternating `autocomplete="work email"` and `home email` hints can cause repeated `CNSaveRequest`s. Each one re-mints every `CNLabeledValue` identifier, so iCloud sees all values as changed on every device.
- A fresh usage event adds up to +0.5 recency to a value's score (`recencyWeight`). A just-captured value at the bottom of a card with at most 4 values ties or beats slot 2 on every site for about two weeks (14-day half-life).
- Fix:
  - Debounce `pageContext` in the content script: one per load, then only when the (kind, section) set changes, with a minimum interval of 2 s and at most 5 per page.
  - Rate-limit natively: a card write for a given hint set only after 60 s since the last write, and at most a few writes per minute.
  - Reduce the recency weight for `captured` sources, or require `saved` plus use on 2 or more hosts before boosting.

**M4. "Someone else's data" heuristic is a short deny-list.**
- `FieldWords.swift:6-8` and `:37-41`: recipient, friend, gift, invit, referr, `to_`, "send to".
- Missing: teammate, colleague, guest, attendee, member, contact, emergency, spouse, parent, guardian, beneficiary, reference, referee, patient, student, employee, client, cc, bcc, "share with", "add people".
- Corroborated forms such as HR or emergency-contact pages auto-save third-party data to the card and the bar.
- Fix: default to review. Auto-save only when positive evidence says the value is the person's own. See C1.

**M5. Last-line protection against dropping card values is only in the planner.**
- `CNContactStoreGateway.swift:19-39` and `CardWriter.swift:96`.
- `save()` re-fetches and compares `record == basis`, which is good. But nothing in the gateway enforces never-drop.
- `syncLock` is process-local, so the app and the extension can race. The window between the basis check and `execute` is small but real, and iCloud sync can land in it.
- Fix:
  - In `save`, throw unless every `basis` entry (kind plus key) is in `target`, with at most N additions per kind.
  - Re-fetch after `execute` and verify. If a value was lost, re-add it.
- The planner itself (`CardPlan`, `fresh()`, `placing`, `duplicates`) looks correct. I traced the duplicate-key handling and could not break it.

**M6. History retention is a quiet browsing log.**
- `CaptureFilter.usage(from:)` (`:52-61`) records a (host, value) pair for every `.save` and `.duplicate`, up to 500 events. This includes login and sign-up forms.
- Fix: time-to-live (about 90 days). Do not record hosts for `pageContext`. Show a "Clear history" control. Disclose it in the privacy policy.

**M7. Content script scope.**
- `manifest.json:24`: `<all_urls>` also matches `file:` and non-web schemes. Plain `http:` pages can be modified by a network attacker.
- Fix: `matches: ["https://*/*"]`. In JS, bail unless `window.isSecureContext && window === window.top`.

## LOW / INFO

- **L1.** `AppGroupStore.swift:17`, `:29`, `:46` (AppStore build): no explicit file protection and no backup exclusion. Set `.completeFileProtectionUntilFirstUserAuthentication` on files and directory, and `isExcludedFromBackup = true`.
- **L2.** `SharedStore.swift:40` logs `String(describing: backend)` as `.public`, which includes the container path and keychain group. Log the case name only.
- **L3.** `ContactValue.swift:80-96`: the "ID is not the value itself" comment is wrong. An unsalted SHA-1 of an email or phone is dictionary-reversible. Fine functionally, but it gives no privacy property.
- **L4.** `content.ts` pings on every page load of every site, which wakes the native handler (about 1.3 s cold). It also leaks page-load cadence into the unified log. Ping once per session or only on pages with contact fields. The unhandled `sendMessage` rejection is harmless.
- **L5.** `KeychainStore.swift:86`: a nil access group silently uses the default group. `kSecAttrAccessible` is never upgraded on existing items. On macOS, tests use the legacy keychain unless `kSecUseDataProtectionKeychain` is set.
- **L6.** `project.yml:30`: `NS_CONTACTS_USAGE` says "reads and reorders" but not "adds values you submit in forms".
- **L7.** `Normalizer.registrableDomain` has no public-suffix list, so `*.github.io`, `*.vercel.app` and `*.herokuapp.com` share one site key (history and pins).
- **L8.** `Extension/Resources/*.js` are gitignored build output and the Xcode target marks them `optional: true`. An archive without a prior `pnpm build` ships a stale or missing extension. Add a build-phase guard.
- **L9.** Tracked `spikes/*/logs` in the public repo contain `/Users/tarunyadgirkar/...` paths (about 153 files), simulator UDIDs and team ID `5AKJYZ7USP`. No real emails, phones or secrets found; all contact values are example.* test data.
- **L10.** The same capture can arrive twice (submit plus submit-click). Concurrent handlers can then double-record events. Dedupe in the content script and natively.

## Checked and fine

- **Networking:** none in Swift, TS or JS sources. No `requestAccess` call anywhere. The Contacts write goes through the gateway only.
- **Logging:** all `Logger` calls are static strings, enum names or integers. `DecodingError` text is never logged (`MessageCoding.failureName`). No `print`, `NSLog`, `dump`, `fatalError` or `try!` in the sources.
- **Secrets:** none hardcoded. `pnpm audit` is clean, and there are no runtime JS dependencies in the bundles. The only secret-like string is a public team ID.
- **Passwords and card fields:** `FieldKind` has no password or card kind, so a password cannot be a typed field. It can only arrive if the classifier mislabels it, which is what H1 and C1 cover.
- **Prototype pollution:** `matches()` uses `Object.hasOwn(checks, type)`, so `toString`, `constructor` and `__proto__` types are rejected (tested). Messages are structured-cloned. I found no practical pollution path.
- **Response channel:** responses carry only counts, status and static reason strings, no contact values, and the content script is the only recipient.
- **Keychain:** `ThisDeviceOnly`, `AfterFirstUnlock` (appropriate for a Safari extension) and `kSecAttrSynchronizable: false`. The shared group is team-prefixed.
- **Messages:** carry `host` only, with no URL, path or query.
- **Manifest:** only `nativeMessaging`. No `web_accessible_resources`, no `externally_connectable`, no host permissions, no `"world": "MAIN"`.

## Phase 2 security requirements

**Content script**
1. Provenance (C1): trusted-input snapshot map, visibility check, trusted submit plus user activation, `userTyped` per field, `trigger` field, and `flush` always goes to review.
2. Classifier: negative patterns first, then positive evidence only. Never classify on `type=tel` or `type=text` alone. Name kind only from `name`, `given-name` and `family-name` autocomplete tokens, so usernames never go. Track fields that were ever `type=password` (mutation observer on `type`) and drop them.
3. DOM-clobbering safety: `<input name=elements>` shadows `form.elements`, and any named control can shadow `form.querySelectorAll`. Use `Reflect.apply` or `.call` on `HTMLFormElement.prototype` or `Element.prototype` getters. Never read `form.action`, `form.id`, `form.method` or `form.submit`. Use `composedPath()[0]` instead of `event.target`.
4. Never read `event.detail` or `postMessage` data, and never listen for page-dispatched custom events. Never write any DOM, attribute, class, `dataset` or badge. The spike's `showBadge` renders capture counts into the page, which is a readable oracle for whether a value is on the card.
5. Never block, delay or alter the page's submit based on the native result. Do not render the response anywhere.
6. Send `location.hostname` only, with no port, path, query, hash, `document.referrer` or title. Enforce the length and count caps at the source.
7. Rate limits: `pageContext` once per load, then on hint change only, at least 2 s apart and at most 5 per page. `capture` at most 3 per page, deduped. Bound the `lastValues` cache and clear it after flush or form reset.
8. Frames: keep `all_frames` unset. If `all_frames: true` is ever added, use each frame's own hostname, never aggregate across frames, treat cross-site frames as review-only, and keep `match_about_blank` and `match_origin_as_fallback` false. Add `window === window.top` defense in depth.
9. Gate: `isSecureContext`, https only. Pause in Private Browsing (H2).

**Background**
10. Check `sender.id`, `sender.tab`, `sender.frameId === 0` and `sender.tab.incognito === false`. Overwrite `host` from `sender.url`.
11. Rebuild the payload from an allow-list and enforce length caps and a total size cap before `sendNativeMessage`. Serialize native calls and coalesce duplicate `pageContext` per tab.
12. Return only `{ok}` or a status to the content script, with no `reason` strings.
13. Add `content_security_policy.extension_pages` with `connect-src 'none'; default-src 'none'; script-src 'self'`. Add ESLint `no-restricted-globals` for `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource`, `Image` and `sendBeacon`, plus a test that greps the bundles.

**Native**
14. Validate at the Swift decode boundary (H3). Keep `name`, `label` and `autocomplete` for classification only. Never persist or log them. Never persist `name` values.
15. Auto-save rules:
    - Require trigger = submit, `userTyped`, not private, https, and `saveNewInfo`.
    - Only a card-matching value typed in the same form counts as corroboration.
    - `hasPassword` and own-name hits may only choose review over ignore.
    - Cap auto-saves per host per day and overall. Overflow goes to review.
    - Never evict `saved` records from the Undo list in favor of review spam.
16. `cardIdentifier` comes only from `AppState.cardLink`, never from a message. With no `cardLink`, return `failed(.cardMissing)` and write nothing. Under full Contacts access the extension could otherwise touch any contact. Onboarding should steer toward limited access with just the person's card.
17. Add the never-drop invariant and post-save verification in the gateway (M5). Cap additions per capture. Undo must remove only the exact (kind, key, label) Prefill added.
18. "Restore original card" must be additive by default, restoring missing originals and order. It may remove values only after an explicit confirmation that lists them.
19. Write order: if the card write fails, do not record or report `saved`. If the Capture record write fails after a successful card write, still return success and log a static string. A store failure must never block card operations.
20. Logging policy: static strings, enums and integers only. `host` and values are never `.public`. Add a SwiftLint custom rule forbidding `privacy: .public` on non-Int/enum arguments, and forbidding `print`, `NSLog`, `dump`, `debugPrint` and `String(describing:)` on requests or `DecodingError`. No `fatalError` or `precondition` message may contain values.
21. Data lifecycle: protocol-level `removeAll()`, Settings "Delete data", first-launch purge, file protection and backup exclusion on AppGroup files, retention TTL for usage hosts.
22. Adversarial tests:
    - Hidden-field fixture and script `requestSubmit()` without activation.
    - Password-reveal toggle.
    - `type=tel` card number.
    - Bidi or control characters in an email.
    - 10 MB value and 100k fields.
    - `__proto__` and `constructor` keys.
    - `<input name=elements>` clobbering.
    - Duplicate submit.
    - Private-tab drop.
    - `flush` never saves.
    - Rate-limit overflow goes to review.
    - Swift decode fuzz.
22. Phase 6: add `PrivacyInfo.xcprivacy` with required-reason APIs (`UserDefaults` for the sentinel, file timestamp APIs) and contacts and browsing-history disclosure. Update the Contacts purpose string (L6).

Key files reviewed:
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Capture/CaptureFilter.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Capture/FieldWords.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Messages/Messages.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Card/CNContactStoreGateway.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Card/CardWriter.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Store/KeychainStore.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Store/AppGroupStore.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Model/Documents.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/web/src/messages.ts`
- `/Users/tarunyadgirkar/TarunsCode/prefill/web/src/background.ts`
- `/Users/tarunyadgirkar/TarunsCode/prefill/web/src/relay.ts`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Extension/Resources/manifest.json`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Extension/SafariWebExtensionHandler.swift`
- `/Users/tarunyadgirkar/TarunsCode/prefill/spikes/capture/Extension/Resources/content.js`
- `/Users/tarunyadgirkar/TarunsCode/prefill/project.yml`
- `/Users/tarunyadgirkar/TarunsCode/prefill/Config/`