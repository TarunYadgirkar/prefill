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
  - Callers (`CardWriter`, never-drop guard, readers, Siri, Mac) don't know about the split.
- **Per-device app state** (pins, usage, muted sites, review queue):
  - iPhone: the Keychain store for Personal, the App Group store for AppStore.
  - Mac: `~/Library/Application Support/Prefill/Store`.
  - It does not sync.

## Layout

| Path | What |
|---|---|
| `web/src` | One TypeScript codebase for the Safari extension, the Chromium extension and the Mac Accessibility classifier (`web/src/mac/autofill.ts`, run in JavaScriptCore). `atsFrames.ts` lists the job application frames it runs in. `classify.ts` decides what a field is. `capture.ts` saves typed values. `learn.ts` saves answers to job application questions. `context.ts` reorders the card. `links.ts`/`custom.ts`/`suggestions.ts` give values. `dropdown.ts` is Chromium's own list. `gesture.ts` is the click-or-Tab gate. `fill.ts` is one-tap fill (`fillChip.ts` its button, `choices.ts` matches select and radio options, `combobox.ts` drives searchable dropdowns like Greenhouse's React-Select, `demographics.ts` declines self-identification questions). |
| `Packages/PrefillKit` | Shared Swift code: `Card/` (gateway, split, writer, never-drop), `Messages/` (router, limits, validated contracts), `Capture/`, `Ranking/`, `Store/`, `Autofill/` (Mac field rules bridge), `Intelligence/` (on-device FoundationModels labels). |
| `App/` | iPhone app: Card (Emails/Phones/Addresses/Links/Custom), Sites, Recent, Settings (Sharing your card, Restore), Siri intents. |
| `Extension/` | Safari Web Extension handler; it inherits the app's Contacts grant and never calls `requestAccess`. |
| `MacApp/` | Menu bar app. `Autofill/` is the Accessibility engine (focus watcher, panel, key tap, filler). `Relay/` is the socket server and host-manifest installer. `Views/` holds the menu and settings. |
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
- **Values reach a page only after a real click or Tab on that field,** within 1 second, and only while the field is visible (`gesture.ts`). One Tab unlocks one field.
- **One-tap fill is the one exception, and it takes the person's own tap on Prefill's button:** the pill beside a field they just clicked or tabbed into (closed shadow root, trusted clicks only), or Fill in Safari's sheet.
  - It fills only visible, empty, editable fields of the form the person is in, never sensitive ones or sign-in forms, and never overwrites what they typed.
  - Demographic questions (gender, race, ethnicity, veteran, disability, orientation) always get the declining option, or "No" when there is none, and a text box asking one is left alone.
  - Searchable dropdowns (React-Select) are opened the way a person would: type the answer, or press the down arrow to decline, then click the option.
  - Follow-up questions ("If other, please specify") are left alone.
  - Undo puts every field back, and a tap on a filled field offers the other values.
- **Capture:** only values the person typed, on a trusted submit, never in private tabs, within the size caps.
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

- **Device-only checks not yet done:** Siri, the Focus filter, snippet buttons, and iCloud carrying custom-field labels between devices.
- **Minimal mode:**
  - At most 3 values with no labels.
  - WebKit's in-page list always shows.
  - AutoFill Contact no longer fills emails and addresses.
  - The Mac has no "put back on card" or Restore yet.
- **Mac Accessibility mode:**
  - It doesn't save new values; only the extension does.
  - Arc, Safari, Electron apps and Firefox are untested.
  - The first field clicked right after switching to Chrome may get nothing.
- **Weekly reinstall:** the free-team iPhone build expires every 7 days.
  - `scripts/install-auto-reinstall.sh` sets up a daily launchd agent that runs `scripts/auto-reinstall.sh`, which reinstalls when due and retries while the phone is locked.
  - It's untested on the Mac: codesign's keychain access from launchd and whether Xcode fetches a fresh profile after the old one is moved aside are unconfirmed.
  - Install it from the main checkout: the job keeps the path it was installed from.
- **One-tap fill:**
  - Checked in Safari on the simulator (`FillE2ETests`), not yet on the iPhone.
  - In Safari every recognized field now gets Prefill's own list under it (`showDropdown`), as in Chrome; the datalist path is unused. Safari's own suggestion bubble can cover the list's first row.
  - Undo clears a React-Select box with Backspace, which React-Select ignores unless the box is clearable, so a non-clearable box keeps Prefill's pick. Undo leaves a box alone once it shows something other than Prefill's pick.
  - The pill counts fields it recognizes, so "Fill form 13 fields" can end as "Filled 9" when the card has no link or answer for some.
- **Guessed answers:** a field no rule matches gets the on-device model's pick among the custom fields, shown as "Suggested" and never used by Fill form. The Mac panel asks live; on the iPhone the handler notes the question and the app asks on its next launch, so the guess shows from the next visit. Nothing shows until Apple Intelligence is on.
- **Learned answers:**
  - Only native text inputs, selects and radios, on a real form submit. React-Select dropdowns and forms that post without a submit event aren't read.
  - A later answer replaces a learned one that still reads as learned, with Undo; an answer the person wrote or edited in the app is never replaced.
- **Mac "Fill form":** text fields only. `scripts/e2e-mac-ax.sh` covers it; that script needs an unlocked screen and Chrome for Testing left in front for about 15 seconds.
- **NameDrop:** a minimal card's phones are never reordered (`CardSplit.minimalCardEntries`). The check with a real NameDrop on the iPhone is still to do.

## Ongoing

Working from [docs/PLAN.md](docs/PLAN.md), the v2 plan: click a field and pick a value is the default, Fill form is optional. Its Progress list is the to-do list; take the first unchecked task.

Phase 1 (Oct 6, merged): a value picked from Prefill's list (`picked` message) is pinned for the site without a Contacts write, links too, and a picked custom answer or guess is remembered for the question's words (`ExtensionEvents.answerPicks`). The Mac panel reports picks. In Safari, Prefill's contact list now sits above the field, because Safari's own suggestion bubble swallows every tap in a band about 100 pt under a contact field (found by the new `PickE2ETests`; before this, the first two rows couldn't be tapped on the iPhone). Rows are buttons. Installed on the Mac; the iPhone wasn't connected, so the daily reinstall job will pick it up. After a reinstall, reload the unpacked extension in Chrome and Arc.

Known: `CustomFieldsE2ETests`, `LinksE2ETests` and `MinimalCardE2ETests` fail because they still read Safari's keyboard bar from before `d070f61` (task 2.0). A full `scripts/test.sh e2e` takes about 15 minutes and collides with another session's run on port 8846 and the simulator; check `lsof -iTCP:8846` first.

Not yet checked by a person: picking from the list on the iPhone itself, and the list placement above the field at large Dynamic Type sizes.

Bug sweep (Oct 6, merged as `fix/bug-sweep`): failures that were silently ignored now show (Mac card read, saving answers, Undo on learned answers). A passing Contacts error no longer creates a duplicate Prefill contact. Custom-field edits apply to the card as read at save time. A move or merge that hits a label or key collision keeps both values. Mac Fill form skips hidden fields and text typed during the fill. Web Undo covers every fill run, and a learned answer counts only after the person's own press. Not fixed: the host's parent-PID browser check can be spoofed with exec (a residual risk), and the Prefill contact is matched by account, not by the card's name.
