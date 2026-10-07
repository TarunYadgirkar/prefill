# Working on Prefill

Read this first, then [docs/PRODUCT.md](docs/PRODUCT.md) for why things are the way they are, and [research/REPORT.md](research/REPORT.md) for the evidence behind the platform facts below.

## Platform facts (verified, don't re-litigate)

- **No public API adds third-party values to Safari's iPhone QuickType bar.** Safari fills it from the My Info card.
- **Safari's My Info and the Contacts My Card are one setting.** Both settings screens call the same private `setMeContact`. So the card Safari reads is the card NameDrop and Share Contact send.
- **Bar order:**
  - Slot 1 is the value whose stored identifier is 0.
  - Slot 2 is the next value in array order.
  - A fresh rewrite in one `CNSaveRequest` renumbers identifiers.
  - Safari picks the change up on the next field focus.
- **Datalist injection reaches the real bar only where Safari has no contact suggestion of its own:**
  - At most 3 values, no labels.
  - WebKit also opens its own list under the field.
  - On sign-up forms the bar shows Passwords instead, so the values appear only in WebKit's list.
- **Safari never offers to save typed contact values.** Prefill's extension captures them instead.
- **The free personal team (5AKJYZ7USP) can't use App Groups,** and its apps expire after 7 days.
  - Personal bundle IDs end in `.dev`.
  - The AppStore config exists in case the user ever pays.
  - Assume they won't: all sync goes through iCloud Contacts.
- **Chrome extensions can't reach Contacts.** On the Mac, data flows: native host → Unix socket → Mac app.
- **Chromium exposes web fields to Accessibility only after `AXManualAccessibility`/`AXEnhancedUserInterface` is set,** and builds that view a few seconds later. Browsers don't expose the `autocomplete` or `name` attributes.

## Data model

- **The person's own card (Me card):** what Safari's bar reads.
  - In **minimal mode** it holds only the name and the phone numbers the person chose to keep.
  - Otherwise it also holds emails, phones and addresses.
- **The Prefill contact:**
  - An organization card named `Prefill · <Name>`, in the same account as the Me card.
  - Recognized by its department field: `Links and custom fields for Prefill`, or `Contact details for Prefill` when minimal mode is on.
  - Holds links (urlAddresses), custom fields (contactRelations labeled `<Label> · Prefill[ · match words]`) and, in minimal mode, the moved emails, addresses and phones.
  - Copies from two devices merge, and copies are never deleted.
- **`CNContactStoreGateway`:**
  - Reads both contacts as one `CardRecord` and writes each part back to its own contact.
  - Callers (`CardWriter`, never-drop guard, readers, Mac) don't know about the split.
- **`Memory`** (`PrefillKit/Memory/`): a read-only view of every answer (contact values, links, custom fields) with its origin, where it's stored and `uses(of:)` ("Used on"). The app's Inbox and You screens read it through `AppSupport/MemoryLookup.swift`. The message routers still read `CardRecord` directly (see PLAN 3.2).
- **Per-device app state** (pins, usage, picks, muted sites, review queue):
  - iPhone: the Keychain store for Personal, the App Group store for AppStore.
  - Mac: `~/Library/Application Support/Prefill/Store`.
  - It does not sync.

## Layout

| Path | What |
|---|---|
| `web/src` | One TypeScript codebase for the Safari extension, the Chromium extension and the Mac Accessibility classifier (`web/src/mac/autofill.ts`, run in JavaScriptCore). `atsFrames.ts` lists the job application frames it runs in. `classify.ts` decides what a field is. `capture.ts` saves typed values. `learn.ts` saves answers to job application questions. `links.ts`/`custom.ts`/`suggestions.ts` give values, `why.ts` words the line under each, `picks.ts` reports picks. `dropdown.ts` is Prefill's own list, in Safari and Chromium. `gesture.ts` is the click-or-Tab gate. `fill.ts` is one-tap fill (`fillChip.ts` its button, `choices.ts` matches select and radio options, `combobox.ts` drives searchable dropdowns like Greenhouse's React-Select, `demographics.ts` declines self-identification questions). |
| `Packages/PrefillKit` | Shared Swift code: `Card/` (gateway, split, writer, never-drop), `Messages/` (router, limits, validated contracts), `Capture/`, `Ranking/`, `Store/`, `Keyboard/` (the values shared with the keyboard), `Autofill/` (Mac field rules bridge), `Intelligence/` (on-device FoundationModels labels). |
| `App/` | iPhone app: Inbox, You (search, groups, value detail, Add menu), Settings (Sharing your card, Advanced: sites Prefill doesn't save on, Restore, Delete). |
| `Extension/` | Safari Web Extension handler; it inherits the app's Contacts grant and never calls `requestAccess`. |
| `Keyboard/`, `KeyboardUI/` | The Prefill keyboard for other apps (`PrefillKeyboard` target): a value picker that reads the snapshot the app shares through the store (`PrefillKit/Keyboard/`), types a value and switches back. `KeyboardUI/` is shared with the app for its debug preview and colors. |
| `MacApp/` | Menu bar app. `Autofill/` is the Accessibility engine (focus watcher, panel, key tap, filler). `Relay/` is the socket server and host-manifest installer. `Views/` holds the menu (with the first-run checklist, `SetupChecklist.swift`) and settings. |
| `MacHost/` | The `prefill-host` native messaging executable. It checks its parent browser's signature and relays to the app. |
| `MacShared/` | Code identity checks and the socket used by both sides. |
| `docs/messages.md` | Every message between page, extension, app and host, with limits. Update it with any new message. |
| `testbed/` | Local test pages (Greenhouse-style, signup, checkout) for the e2e tests. |
| `scripts/` | build, test, install-device, auto-reinstall (and its launchd installer), install-mac, e2e-mac-chrome, e2e-mac-ax. `web/src/e2e/fillChrome.ts` runs one-tap fill in real Chromium with a stand-in host (`fakeHost.py`), on Linux or the Mac, including a page built with the real React-Select (`testbed/react-select/`). Run `pnpm --dir web build` first; set `PREFILL_CHROMIUM` to use a local Chromium. |

## Rules that keep it safe

- **Frames:** the content script runs only in the top frame and in `https` frames on the job application hosts in `web/src/atsFrames.ts` (exact hosts, or a listed domain and its subdomains), each in a secure context and under its own host. `page.ts` and `relay.ts` both check it. Add a host only for a real embedded application form.
- **Field rules:**
  - Never act on password, card, code, bank or government-ID fields.
  - Never act on sign-in forms (a `current-password` field in the form).
- **Values reach a page only after a real click or Tab on that field,** within 1 second, and only while the field is visible (`gesture.ts`). One Tab unlocks one field, and so does a click on the Fill form pill's "need you", for the field it moves to.
- **One-tap fill is the one exception, and it takes the person's own tap on Prefill's button:** the pill beside a field they just clicked or tabbed into (closed shadow root, trusted clicks only), or Fill in Safari's sheet.
  - It fills only visible, empty, editable fields of the form the person is in, never sensitive ones or sign-in forms, and never overwrites what they typed.
  - Demographic questions (gender, race, ethnicity, veteran, disability, orientation) always get the declining option, or "No" when there is none, and a text box asking one is left alone.
  - Searchable dropdowns (React-Select) are opened the way a person would: type the answer, or press the down arrow to decline, then click the option.
  - Follow-up questions ("If other, please specify") are left alone.
  - A list where more than one option fits the saved answer about equally ("Yes" against "Yes, now" and "Yes, in the future") is left, outlined, and counted as "need you" (`choices.ts` `matchOption`).
  - Undo puts every field back, and a tap on a filled field offers the other values.
- **Capture:** only values the person typed, on a trusted submit, never in private tabs, within the size caps.
- **The card sends only name and phone (Tarun's rule):** when he AirDrops, NameDrops or Share Contacts his card, it carries only his name and phone number.
  - Prefill never orders the card for a site: no page message rewrites it, `CardWriter` never ranks, and the sheet's pick only pins in Prefill's list.
  - On a minimal card nothing new lands on it: captured, added and learned emails, phones, addresses, links and custom fields go to Prefill's contact (`CardSplit.writes`).
  - The phone kept on the card is never rewritten or reordered (`CardSplit.minimalCardEntries`, `CNCardMapping.isStored`).
  - Something goes back on the card only when the person asks ("Put on your card", "Put back on card", Restore).
  - Not yet covered: a card that isn't minimal (the person tapped "Not now") still gets new emails, phones and addresses, and links and custom fields too until Prefill's contact exists.
- **Never drop data:**
  - Card rewrites go through `CardWriter` plus the never-drop guard.
  - Moves are one save request, read back afterwards.
  - Nothing comes off the Me card without the person confirming the exact list.
- **Mac relay:** the app answers only Prefill's own signed host, and the host talks only to Prefill's own app.
- **The extension's `key` in `web/chromium/manifest.json` is a public key.** It's in `.gitleaksignore` on purpose.

## Workflow

- **Testing:** the user wants it lean. Add a few unit tests plus one real end-to-end check per feature. Don't build big test suites, and never tune field rules on generated data; use real page markup as fixtures.
- **Before pushing:** run `pnpm --dir web test`, `pnpm --dir web lint`, `pnpm --dir web typecheck`, `swift test` in `Packages/PrefillKit`, `swiftlint --strict`, `scripts/build.sh` and the Mac build.
- **Commits:** conventional, short subjects, no Co-Authored-By. Merge with `--no-ff` into `main` and push. The repo is public.
- **Parallel agents:** work in your own worktree under `.claude/worktrees/`. Never switch the branch of the main checkout.
- **Devices:**
  - The user's iPhone 17 Pro has UDID `00008150-000A3C241108401C`.
  - CoreDevice error 4016 or 10002 means it's locked.
  - Main test simulator: `D03EE1A5-5538-4E81-BB43-5ABF852199F4`; its My Info is the Alex Rivera test card.
- **Your own permissions:** you can't toggle Accessibility, Contacts or other privacy settings for the user, and computer-use can only look at browsers, not click in them. Hand those steps to the user.

## Open items

- **Device-only check not yet done:** iCloud carrying custom-field labels between devices.
- **Minimal mode:**
  - Safari's bar shows only the name and kept phone; Prefill's list under each field shows everything else, and Safari skips name fields in Prefill's list.
  - AutoFill Contact no longer fills emails and addresses; Fill form does.
  - The Mac puts values back one at a time ("Put back on card"); it has no Restore yet.
  - The one-time offer for existing users is the "Keep your card short" section at the top of the Inbox. "Not now" sets `declinedShortCard` in UserDefaults; onboarding's Sharing step (Phase 9 / 4.3) should set the same key when the person declines there.
- **Mac Accessibility mode:**
  - In a browser whose Prefill extension has sent the app a request, the panel stays out until that browser quits and the extension gives every list and Fill form (`ExtensionPresence`).
  - It doesn't save new values; only the extension does.
  - Arc, Safari, Electron apps and Firefox are untested.
  - The first field clicked right after switching to Chrome may get nothing.
- **Weekly reinstall:** the free-team iPhone build expires every 7 days.
  - `scripts/install-auto-reinstall.sh` sets up a daily launchd agent that runs `scripts/auto-reinstall.sh`, which reinstalls when due and retries while the phone is locked.
  - It's untested on the Mac: codesign's keychain access from launchd and whether Xcode fetches a fresh profile after the old one is moved aside are unconfirmed.
  - Install it from the main checkout: the job keeps the path it was installed from.
- **One-tap fill:**
  - Checked in Safari on the simulator (`FillE2ETests`), not yet on the iPhone.
  - In Safari every recognized field gets Prefill's own list under it (`showDropdown`), as in Chrome; the datalist path is gone. Safari's own suggestion bubble can cover the list's first row.
  - Undo clears a React-Select box with Backspace, which React-Select ignores unless the box is clearable, so a non-clearable box keeps Prefill's pick. Undo leaves a box alone once it shows something other than Prefill's pick.
  - The pill counts the fields the app has an answer for, and after a fill says how many "need you"; a click there moves to the next empty field and opens its list (the gate's one-field `allowNext`).
- **Guessed answers:** a field no rule matches gets the on-device model's pick among the custom fields, shown as "Suggested" and never used by Fill form. The Mac panel asks live; on the iPhone the handler notes the question and the app asks on its next launch, so the guess shows from the next visit. Nothing shows until Apple Intelligence is on.
- **Learned answers:**
  - Only native text inputs, selects and radios, on a real form submit. React-Select dropdowns and forms that post without a submit event aren't read.
  - A later answer replaces a learned one that still reads as learned, with Undo; an answer the person wrote or edited in the app is never replaced.
  - Answers can be scoped by the question's words: "Work authorization (US)" and "(Canada)" are separate fields (`AnswerScope`). A US answer is never offered for a Canada question (the list says "No answer for Canada yet"); an unscoped answer for a scoped question, or the reverse, is offered but never filled.
- **Mac "Fill form":** text fields only. `scripts/e2e-mac-ax.sh` covers it; that script needs an unlocked screen and Chrome for Testing left in front for about 15 seconds.
- **Prefill keyboard:** built in `feat/keyboard`, checked only in the simulator. Needs Full Access to read the keychain item; not yet run on the iPhone.
- **NameDrop:** a minimal card's phones are never reordered (`CardSplit.minimalCardEntries`). The check with a real NameDrop on the iPhone is still to do.

## Ongoing

Working from [docs/PLAN.md](docs/PLAN.md), the v2 plan; its Progress list is the to-do list. Done on Oct 6: Phases 1, 2, 3, 5 and 6 (cuts: Siri, Shortcuts, the Focus filter, the Sites screen and the match-words field are gone), task 2.0 (the Safari tests read Prefill's list) and 10.1 (docs as built so far).

Phase 4 (freeze the card to name and phone) is built on `feat/phase4-freeze-card` except 4.3's onboarding wording (Phase 9's setup is merged; its card step doesn't offer the short card yet) and the device check 4.6. Phase 7 (resume import) was dropped. Phase 3.2 was narrowed: the routers keep reading `CardRecord` (reason in PLAN 3.2).

Phase 11 (Oct 7, merged): the Prefill keyboard (`Keyboard/`, `KeyboardUI/`, PrefillKit `Keyboard/`) brings saved values to every app on the iPhone. The app writes a capped snapshot to the shared keychain group; the keyboard reads it with Full Access, types the tapped value and returns to the person's keyboard. The long-press AutoFill route is out: Apple refuses the credential-provider entitlement for the free team. Signing profiles were renewed through Oct 14 now that Xcode is signed in; the daily reinstall job can renew from here. Not yet checked by a person: the keyboard on the phone itself (installed Oct 7, needs adding in Settings with Full Access).

Simulator runs: one at a time. Before `scripts/test.sh e2e`, check that `lsof -nP -iTCP:8846 -sTCP:LISTEN` is empty and `pgrep -x xcodebuild` finds nothing (not `pgrep -f`, which matches its own shell). Run classes one by one with `PREFILL_E2E_ONLY`; the whole suite takes longer than the script's 15-minute limit. Revert the screenshots a run rewrites unless they're the point of the change.

Not yet checked by a person: picking from Prefill's list on the iPhone itself, the new Inbox and You tabs on the phone, the Mac menu, its first-run checklist and the Settings window on screen (only built), the large-text tour, Safari's bubble on a field Fill form filled, and the Advanced list of sites Prefill doesn't save on (only built).
