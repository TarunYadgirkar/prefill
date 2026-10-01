# Plan: Prefill v1

**Source**: `research/REPORT.md` and the spikes in `spikes/`
**Complexity**: Large
**Mode**: polished, SF Symbols, system font (SF Pro), SwiftUI, iOS 27.0 deployment target

## Summary

Prefill makes Safari's own contact AutoFill smarter instead of adding a second suggestion UI. The QuickType bar above the keyboard keeps showing Apple's suggestions, with Apple's labels, the "AutoFill Contact" sheet and the up/down/done row. Prefill decides what is on the person's contact card and in which order. A Safari Web Extension tells Prefill what each page asks for and what the person submits. Prefill then (1) saves new emails, phones and addresses to the card, so they show up in the bar from then on, and (2) rewrites the card's order before the person taps a field, so the two values Safari shows first are the ones that fit that site.

## How it works

```
Safari page loads ──► content.js classifies fields (email / tel / address, section hints)
                         │ browser.runtime.sendMessage
                         ▼
                      background.js ──► sendNativeMessage ──► SafariWebExtensionHandler
                                                                 │ PrefillKit.Ranker: best two per kind for this host
                                                                 │ CardWriter: refetch, merge, rewrite fresh CNLabeledValues
                                                                 ▼
                                                     the person's contact card (Contacts)
                                                                 │ read by Safari on next field focus
                                                                 ▼
                                                     Apple's QuickType bar shows Prefill's top two

Form submitted ──► content.js capture (submit, submit-click, input cache flushed on pagehide/hidden)
                         ▼
                      handler ──► CaptureFilter ("is this yours?") ──► Store.recordUse / add value
                                                                 └─► CardWriter adds new value to the card
```

Facts this rests on (all observed on iOS 27.0, see REPORT.md "Spike results"):
- Slot 1 is the value with stored identifier 0, slot 2 the first other value; a fresh rewrite in one save renumbers 0..n, so the written order is the shown order.
- Limited Contacts access with only the person's card shared is enough to rewrite it.
- Safari picks up a card edit on the next field focus, with no relaunch.
- The extension handler inherits the app's Contacts grant; it must never call `requestAccess`.
- Safari never saves typed contact values itself.

## Patterns to mirror

| Category | Source | Pattern |
|---|---|---|
| Project generation | `spikes/capture/project.yml` | xcodegen, Swift 6, ad-hoc sim signing, App Group on app and extension |
| Extension messaging | `spikes/capture/Extension/Resources/{content,background}.js`, `SafariWebExtensionHandler.swift` | content to background to native, JSON payload in `SFExtensionMessageKey` |
| Capture triggers | `spikes/capture/Extension/Resources/content.js` | capture-phase submit plus submit-click, input cache flushed on pagehide and visibilitychange, skip password and one-time-code |
| Card rewrite | `spikes/contacts/Probe/Probe.swift` (`fresh()`, `save`) | rebuild arrays from fresh `CNLabeledValue(label:value:)` in ranked order, one `CNSaveRequest.update` |
| UI test driving | `spikes/capture/UITests/EnableTests.swift`, `spikes/datalist/UITests/DriverTests.swift` | XCUITest drives Settings and Safari; read "Typing Predictions" from the accessibility tree |
| Test runner hang | `spikes/capture/scripts/run-test.sh` | kill xcodebuild after the suite summary line |
| Errors and logging | none yet | new: `os.Logger` per subsystem, user-facing errors as plain sentences, never log values (PII) |

## Targets and layout

| Path | What |
|---|---|
| `project.yml` | xcodegen: `Prefill` app, `PrefillSafari` extension, `PrefillUITests` |
| `Packages/PrefillKit` | Swift package shared by app and extension: model, Keychain-backed store, ranking, card writer, capture filter. Swift Testing unit tests, runnable with `swift test` on the Mac. |
| `App/` | SwiftUI app: onboarding, Card, Sites, Recently added, Settings |
| `Extension/` | `SafariWebExtensionHandler.swift` plus `Resources/` (manifest, built JS, icons, locales) |
| `web/` | TypeScript (strict) for content and background scripts, built by esbuild into `Extension/Resources`, tested with Vitest, linted by ESLint with a complexity rule. pnpm. |
| `scripts/` | `bootstrap.sh`, `build.sh`, `test.sh`, `sim-setup.sh` (clone sim, load test card, set My Info) |
| `.swiftlint.yml` | cyclomatic complexity warning 8, error 12, function length, file length |

## Data model (PrefillKit)

- `ContactValue`: id (UUID), kind (email, phone, address), normalized key (lowercased email, digits-only phone with country code, folded address lines), display value, label (CNLabel or custom), source (card, captured, typed in app), createdAt.
- `UsageEvent`: valueID, host (registrable domain), at.
- `SitePin`: host, kind, valueID (person chose "use this email here").
- `Capture`: host, kind, raw value, at, verdict (saved, needs review, dismissed, duplicate).
- `CardLink`: contact identifier, container identifier, linked-member identifiers, snapshot of the original card taken on first run.
- `Settings`: matchEachSite (default on), saveNewInfo (default on).

Store: one `SharedStore` protocol with two backends, chosen at launch, so a single binary serves both distribution paths.

| Build | Signing | Entitlements | Backend |
|---|---|---|---|
| `Personal` configuration (simulator and your iPhone) | personal team `5AKJYZ7USP`, automatic | `keychain-access-groups` only (the free profile grants `5AKJYZ7USP.*`, no App Groups) | `KeychainStore` |
| `AppStore` configuration | paid team from `APP_STORE_TEAM_ID` (unset until you have one) | App Group `group.com.tarunyadgirkar.prefill` plus the Keychain group | `AppGroupStore` |

At launch `containerURL(forSecurityApplicationGroupIdentifier:)` returns a URL only when the App Group entitlement is present; otherwise the Keychain backend is used. Both backends keep one writer per item so the app and extension never race: the app writes `app-state` (value metadata, labels, pins, settings, card link, original-card snapshot) and the extension writes `ext-events` (usage events and captures, append-only, capped). Both read both. `AppGroupStore` uses two JSON files under `NSFileCoordinator`; `KeychainStore` uses two generic-password items in `$(AppIdentifierPrefix)com.tarunyadgirkar.prefill.shared` (the group reaches code through an Info.plist key). The values themselves live on the contact card, which both processes reach through the app's Contacts grant. Unit tests cover both backends.

Ranking per host and kind: site pin, then most recent use on this host, then the section hint from the page (`autocomplete="work email"`, a work-domain match), then the person's manual order weighted by recent use across all sites. The result is a full ordered list; only the top two matter for the bar.

CardWriter: refetch the card, import any values added elsewhere into the store, compute the target order, and skip the save when the card's first two already match. Otherwise rewrite all three arrays with fresh labeled values in one `CNSaveRequest` tagged with `transactionAuthor = "prefill"`. Never drop a value that is on the card.

CaptureFilter, "is this yours": save automatically when the form also contains a value already on the card (your name, another of your emails or phones), or the field is tagged `email`/`tel` in a form with a password or name field (sign-up, checkout). Put everything else in Recently added for review. Never capture passwords, one-time codes, card numbers, or fields whose name or label suggests someone else (recipient, friend, gift, invite, to).

## App UI (polished)

Recurring motif: a faithful replica of the QuickType bar (two slots, label over value, Liquid Glass). It appears on the onboarding pages, at the top of the Card screen, and on each site's page, always showing what Safari will offer there. When the person reorders a value, the replica's slots morph to the new values (`glassEffectID`), so the effect of the change is visible before they ever open Safari.

| Screen | Content |
|---|---|
| Onboarding 1: your card | One button that starts Contacts access. The system's limited-access picker already tags the My Info card "me". If more than one contact is shared, ask which is theirs. A one-line reminder with a small diagram for Settings > Apps > Safari > AutoFill > My Info. |
| Onboarding 2: Safari | Opens extension settings (`SFSafariSettings.openExtensionsSettings`), then checks `SFSafariExtensionManager` state on return. Shows exactly which two switches to flip (Allow Extension, All Websites: Allow), with live checkmarks. |
| Card | Bar replica, a kind switcher (Email, Phone, Address), the ranked list. The top two sit in their own group that matches the replica. Drag to reorder, swipe to delete, tap to relabel, add button. "Restore my original card" lives in Settings. |
| Sites | Sites Prefill has seen, each with its replica and the value it picks. Tap to pin a different value for that site. |
| Recently added | Values captured from forms: saved ones with Undo, review ones with Save and Dismiss. |
| Settings | Match each site, Save new info, restore original card, extension status. |

Haptics on reorder and save, symbol effects on state changes, Dynamic Type, VoiceOver labels on every control, dark mode. Load `better-interface`, `liquid-glass-design` and `swiftui-patterns` before UI work.

## Tasks

### Phase 0: Scaffold (one agent)
- Create `project.yml`, `Packages/PrefillKit`, `web/` (pnpm, TypeScript strict, esbuild, Vitest, ESLint complexity), `.swiftlint.yml` (`brew install swiftlint`), scripts. Bundle IDs `com.tarunyadgirkar.prefill` and `.safari`, team `5AKJYZ7USP`, Keychain access group `$(AppIdentifierPrefix)com.tarunyadgirkar.prefill.shared`, no App Group.
- Validate: `scripts/build.sh` builds app plus extension for the iOS 27.0 simulator; `swift test` and `pnpm test` run empty suites.

### Phase 1: PrefillKit core (one agent, test first)
- Model, Store, Normalizer, Ranker, CardWriter (behind a `ContactsGateway` protocol so tests run without Contacts), CaptureFilter.
- Validate: `swift test` covers ranking order, skip-when-unchanged, merge of values added elsewhere, never-drop, capture filter rules.

### Phase 2 and 3 in parallel (separate worktrees)
**Phase 2: Safari extension**
- `web/src/classify.ts` (autocomplete token grammar, then Chromium-derived patterns with attribution), `context.ts` (page needs on load and focusin), `capture.ts`, `background.ts`; handler routes `pageContext` to Ranker plus CardWriter and `capture` to CaptureFilter plus Store plus CardWriter.
- Validate: Vitest on the testbed pages (smoke only, no generated tuning data); handler unit tests through PrefillKit.

**Phase 3: App UI**
- Onboarding, Card, Sites, Recently added, Settings, bar replica component.
- Validate: SwiftUI previews compile; snapshot screenshots in the simulator for light, dark and the largest Dynamic Type size.

### Phase 4: Integration and end-to-end (orchestrated)
- XCUITest flows on a fresh clone of the configured simulator: onboarding, enable extension, submit a new email on site A, then confirm Safari's bar offers it; use the work email on site B and the personal one on site C, then confirm the bar differs by site.
- Reviews: `react`-equivalent SwiftUI review, `security-reviewer` (PII, all-sites content script, App Group store), complexity lint as a hard gate.
- Screenshots to `assets/generated/`.

### Phase 5: Your iPhone
- Sign with personal team `5AKJYZ7USP`, install with `xcrun devicectl` through `scripts/install-device.sh` (rerun weekly, since free-team apps expire after 7 days). Check on device: a linked iCloud card, sync to your other devices, and the bar on real sites.

### Phase 6: App Store readiness (prepare only; submitting needs a paid account and your go-ahead)
- `PrivacyInfo.xcprivacy` for app and extension (no tracking, no collected data, required-reason API declarations), `ITSAppUsesNonExemptEncryption = NO`, app icon built for iOS 26+ Liquid Glass (layered, light, dark and tinted), App Store screenshots from the simulator, a privacy policy page published from the public repo, and App Review notes that explain why the extension asks for all websites and how Prefill edits the person's own card.
- `AppStore` configuration archives cleanly with `xcodebuild archive` once a paid team ID is set.

## Validation

```bash
scripts/build.sh
swift test --package-path Packages/PrefillKit
pnpm --dir web test && pnpm --dir web lint
swiftlint --strict
scripts/test.sh e2e
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Rewriting the real card per site causes iCloud sync churn, and the order on your Mac changes with it | High | Save only when the first two change; setting to turn off per-site matching; never drop values; original-card snapshot with restore |
| An edit made on another device is overwritten by a stale save | Medium | Refetch and merge right before every save; transaction author plus change history to tell Prefill's saves from yours |
| Linked iCloud and Gmail cards: which member an edit lands on is undocumented | Medium | Fetch with `unifyResults = false`, write to the iCloud member on purpose; device test in Phase 5 |
| Cold extension handler takes about 1.3 s, so a fast tap can still see the old order | Medium | Send page context at load and again on focusin; the old order is still valid values, so this degrades gracefully |
| Extension left on "All Websites: Ask" silently does nothing | Medium | Onboarding checks state and shows the two switches; Settings screen shows status |
| Saving someone else's details (a gift address, an invite email) | Medium | "Is this yours" filter, review inbox, undo |
| Slot rule is private behavior and could change in an iOS update | Low | An end-to-end test that reads the bar and fails loudly |
| Free personal team: no App Groups, apps expire after 7 days, at most 3 sideloaded apps | Certain | Keychain-shared store instead of an App Group; reinstall weekly with `scripts/install-device.sh` |

## Out of scope for v1

Separate identity cards for "Other Contact...", the text-insert provider (insert failed in the simulator, needs a device check), a custom keyboard, and the datalist mode (works, but shows WebKit's dropdown over the page and unlabeled, wrapped values).
