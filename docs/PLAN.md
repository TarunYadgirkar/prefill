# Prefill v2 plan

Written 2026-10-06. This is the working plan for the next round of Prefill. It's meant to be run in a loop: each iteration reads the **Progress** list, takes the first unchecked task, finishes it, checks it off and commits. Read [AGENTS.md](../AGENTS.md) and [PRODUCT.md](PRODUCT.md) first. This plan changes some of the decisions in PRODUCT.md, and says so where it does.

## Direction

Prefill grew one request at a time, and it shows. On the iPhone there are two suggestion systems: the Me card rewrite that steers Safari's bar, and Prefill's own list under each field. On the Mac there are two engines. The data model is whatever iCloud Contacts can hold, and the app's screens are organized around that model (Emails, Phones, Addresses, Links, Custom, Sites, Recent, Sharing, Restore). Meanwhile most of the real use is job applications.

v2 keeps everything that works and gives the product one shape:

1. **Click a field, pick a value.** That's the default way to use Prefill, everywhere. Prefill's list opens under the field you clicked or tabbed into, with the best answer first. **Fill form** stays as an option beside it, never the default.
2. **Picking is remembering.** Choose your work email on a site once and it's first there from then on. No Sites screen, no settings.
3. **An answer is the basic unit.** Email, phone, LinkedIn, "School" and "Are you authorized to work in the US?" are all answers to questions. One memory holds them all, with where each was used. Contacts is how that memory syncs, not how the product is organized.
4. **The Me card is for sharing.** It holds your name and the phone you choose, and Prefill stops rewriting it per site. Everything else is offered by Prefill's own list.
5. **The app is an inbox.** It opens on what Prefill learned recently, for you to confirm or fix. Everything else sits behind one searchable list.
6. **Your resume sets you up.** Drop in a PDF and the on-device model pulls out your answers, so the first application already has them.

### What we're not changing

- The safety rules in AGENTS.md: gestures, frames, sensitive fields, sign-in forms, capture only of typed values, never dropping data, nothing off the Me card without the person confirming the exact list.
- iCloud Contacts as the only sync layer. There's still no paid account, CloudKit or App Groups.
- The Contacts encoding of stored data (`contactRelations` for custom fields, `urlAddresses` for links, the Prefill contact's department marker). The note field would hold a blob nicely, but reading or writing notes needs the `com.apple.developer.contacts.notes` entitlement, which the free team can't get. So the memory model is a layer in code over the existing encoding, and older builds on other devices keep reading the same data.
- Lean testing: a few unit tests and one real end-to-end check per feature.

## How to run this plan

**Each loop iteration:**
1. `git -C <main checkout> pull`, then read this file's Progress list. Take the first unchecked task. If its phase has a **Gate**, check the gate first.
2. Work in a worktree: `git worktree add .claude/worktrees/<phase-slug> -b feat/<phase-slug>` (reuse it for every task in the phase). Never switch the main checkout's branch. Leave other sessions' worktrees (for example `bug-sweep`) alone.
3. Do the task. Keep to the files it names unless the code says otherwise; if it does, note the change under the task.
4. Run the checks for what you touched (see **Checks**). Run all of them before merging a phase.
5. Commit with a conventional subject and no trailers. Check the task off here in the same commit.
6. At the end of a phase: run every check, merge with `--no-ff` into `main`, push, reinstall on the Mac (`zsh scripts/install-mac.sh`) and, when the phone is reachable, the iPhone (`zsh scripts/install-device.sh 00008150-000A3C241108401C`). Update **Ongoing** in AGENTS.md.
7. If a task is blocked (needs the phone unlocked, a privacy toggle, a decision), mark it `[~]` with one line saying why, and move to the next task that doesn't depend on it.

**Checks:**

```bash
pnpm --dir web test && pnpm --dir web lint && pnpm --dir web typecheck
(cd Packages/PrefillKit && swift test)
swiftlint --strict
zsh scripts/build.sh
```

Plus the Mac build (`scripts/install-mac.sh` builds and installs it). End-to-end:
- Safari in the simulator: `zsh scripts/test.sh e2e`
- Chromium with a stand-in host: `pnpm --dir web build && node web/src/e2e/fillChrome.ts assets/generated` (set `PREFILL_CHROMIUM` for a local Chromium)
- Mac: `zsh scripts/e2e-mac-chrome.sh`, `zsh scripts/e2e-mac-ax.sh` (unlocked screen)

**Limits to design around:** ESLint `complexity: 8`; SwiftLint `--strict` with cyclomatic 8, function body 40, file 400, type body 250. Split files before they reach the limit.

**Message changes:** any new or changed message updates all of: `web/src/messages.ts`, the Swift contract in `Packages/PrefillKit/Sources/PrefillKit/Messages/` (`Messages.swift`, `MessageLimits.swift`), `docs/messages.md` and `docs/message-examples.json`. Both test suites check the examples file.

## Progress

- **Phase 1: Picks remember**
  - [x] 1.1 `picked` page message in both contracts, docs and examples
  - [x] 1.2 Router: a pick pins the value for the site without rewriting the card
  - [x] 1.3 Dropdown reports picks; contact suggestions send them
  - [x] 1.4 Links honor pins and report picks
  - [x] 1.5 Custom answers remember the pick per question
  - [x] 1.6 Mac panel reports picks
  - [x] 1.7 End-to-end check and merge
- **Phase 2: Honest suggestions**
  - [x] 2.0 Update three stale Safari tests to read Prefill's list, not the keyboard bar
  - [x] 2.1 Suggestions carry where each value came from
  - [x] 2.2 The list shows it (detail line and style)
  - [x] 2.3 A later answer replaces a learned one, with Undo
  - [x] 2.4 Fill form says what's left and jumps to it
  - [x] 2.5 Keep Prefill's list clear of Safari's suggestion bubble (done in Phase 1)
  - [x] 2.6 End-to-end check and merge
- **Phase 3: One memory**
  - [x] 3.1 `Answer` and `Memory` types over `CardSplit`
  - [x] 3.2 Suggestion routers read from `Memory` (narrowed, see 3.2)
  - [x] 3.3 Usage history per answer ("Used on")
  - [x] 3.4 Merge
- **Phase 4: Freeze the Me card** (Gate: Tarun says go)
  - [x] 4.1 Stop per-site card rewrites (card writes never rank, not just host-less)
  - [x] 4.2 Safari shows Prefill's list for every contact kind (MinimalCardE2ETests passes)
  - [x] 4.3 Short card for everyone: Inbox offer, phone pick, Mac flow, and setup reuses the Inbox offer
  - [x] 4.4 Remove the datalist path and `offCard`
  - [x] 4.5 Sheet pins without rewriting (PopupE2ETests updated and passes)
  - [ ] 4.6 Device check (NameDrop, Share Contact, bar) and merge
- **Phase 5: The app is an inbox**
  - [x] 5.1 iPhone: Inbox tab
  - [x] 5.2 iPhone: You tab (search, groups, value detail)
  - [x] 5.3 iPhone: Settings trimmed
  - [x] 5.4 Mac menu mirrors the inbox
  - [x] 5.5 UI tests and screenshots, merge (large-text tour and empty-inbox shot not run)
- **Phase 6: Cuts**
  - [x] 6.1 Remove Siri intents, Shortcuts and the Focus filter
  - [x] 6.2 Remove the Sites tab
  - [x] 6.3 Match words leave the UI
  - [x] 6.4 Merge
- **Phase 7: Resume import** (dropped Oct 6 by Tarun; setup has no resume step)
  - [ ] 7.1 Text from a PDF, rule pass for contact values and links
  - [ ] 7.2 On-device model pass for answers
  - [ ] 7.3 Review screen on the iPhone
  - [ ] 7.4 Mac import
  - [ ] 7.5 Onboarding offers it; check and merge
- **Phase 8: One Mac engine** (Gate: phases 1 and 2 merged)
  - [x] 8.1 The extension owns Chromium pages it's running in (Oct 6: until that browser quits, not 60 s; the stand-down is gone)
  - [x] 8.2 Accessibility stays for everything else
  - [x] 8.3 Mac checks and merge (Oct 7: both scripts pass; found and fixed two content script copies in one tab)
- **Phase 9: Setup in three steps**
  - [x] 9.1 New onboarding flow (two steps, since Phase 7 was dropped; the card step keeps today's optional short-card offer until Phase 4)
  - [x] 9.2 Mac first run
  - [x] 9.3 Tour test and merge
- **Phase 10: Docs**
  - [x] 10.1 PRODUCT.md, AGENTS.md and README.md describe v2 (as built so far; update again after Phases 4 and 6 to 9)
- **Phase 11: Outside Safari on the iPhone** (Gate: the iPhone plugged in and unlocked; both spikes run on the device, not the simulator)
  - [x] 11.1 Spike: insert a value from the long-press menu (AutoFill › Prefill). Free team refused: the ASCredentialProvider entitlement needs a paid membership.
  - [x] 11.2 Spike: a Prefill keyboard that reads the person's values. The keyboard reads a shared keychain item with Full Access on, and works on the device.
  - [x] 11.3 Decide with Tarun, then build the one that works: the Prefill keyboard (`feat/keyboard`), built; the device check is the lead's.
- **Phase 12: Keyboard v2** (from Tarun's use on Oct 7)
  - [x] 12.1 Compact row layout, like the QuickType bar (`feat/keyboard-v2`, 112 pt, no kind filter)
  - [x] 12.2 Put the likely value first without field labels (`KeyboardSnapshot.ranked(for:)`)
  - [ ] 12.3 Device check and merge
- **Phase 13: Answers that are right, not just remembered** (from the Oct 7 product review)
  - [x] 13.1 Abstain when more than one option fits
  - [x] 13.2 Scoped learning: keep the question and what it applies to
  - [x] 13.3 Memory kinds: facts, contextual facts, preferences, drafts
  - [x] 13.4 The model sees the question, the options and the candidate answers
  - [x] 13.5 Fill, verify, and ask before changing an answer everywhere
  - [x] 13.6 Held-out real forms and an accuracy score
  - [x] 13.7 Docs: browser first, keyboard and Mac panel as fallbacks
  - [x] 13.8 Fix rules the held-out score exposed
- **Phase 14: Storage off Contacts** (Gate: the paid Apple Developer account; Tarun is getting it)
  - [ ] 14.1 CloudKit for answers, picks, usage and the inbox; Contacts stays as optional import/export
  - [ ] 14.2 Normal signing and distribution (no weekly reinstall), and retry the long-press AutoFill route

---

## Phase 1: Picks remember

**Why first:** it's the core of the click-and-pick default, it's small, and it touches no stored data. Today a pick in Prefill's list fills the field and is forgotten: `dropdown.ts` `pick` calls `fillField` and `close` and nothing else, and because `fillField` dispatches untrusted events, neither `capture.ts` nor `learn.ts` notices it. Pins exist, but only Safari's sheet can make one (`pin`/`unpin` are sheet requests, refused from pages by `parsePageRequest`), and making one rewrites the card.

**Done when:** in Chrome, Arc, Safari and the Mac panel, picking a value that wasn't first puts it first on that site from the next field focus on, across devices that share the store (per-device state doesn't sync, which is fine), without a Contacts write.

### 1.1 The `picked` message

A page request, so it goes through `relay.ts` (which overwrites `host` with the sender's host) like every other page request.

```ts
picked: object({
  type: literal("picked"),
  host: hostName,
  kind: oneOf(PICK_KINDS),          // "email" | "phone" | "address" | "link" | "custom"
  value: text(LIMITS.customValue),   // the text that was filled
  question: optional(text(LIMITS.fieldText)), // custom only: the field's text
}),
pickedResult: object({ type: literal("pickedResult"), remembered: boolean }),
```

- Identify the value by its text, not an ID. The suggestion replies carry plain strings today, and the router can derive `ValueID.make(kind:key:)` from the normalized text (`ContactValue.swift:86`), which is the same on every device. This keeps the suggestion replies unchanged.
- For addresses the filled text is one line of the address (street, city...), not the whole address. Send `kind: "address"` with the street line only when the field was the street field; skip other address parts in 1.3.
- Files: `web/src/messages.ts` (page request and response, `PICK_KINDS`), `Messages/Messages.swift` (`ExtensionRequest.picked`, `ExtensionResponse.picked`), `Messages/MessageLimits.swift`, `docs/messages.md`, `docs/message-examples.json`. The exhaustive `switch` in `MessageRouter+Popup.swift` `sheet(_:)` gains the new case.
- Tests: the existing contract tests pick up the example. A `custom` pick without `question` is rejected by the router (it can't be matched), not by the parser.

### 1.2 Router: pin without rewriting

New file `Messages/MessageRouter+Picks.swift`:

- `picked(_:)` runs under `eventLock`.
- Contact kinds and links: read the card (`gateway.fetchCard`), find the entry whose normalized key matches the picked text (`Normalizer` for that kind). If none matches, reply `remembered: false` (the page can't pin a value the person doesn't have).
- If `state.pinnedValue(kind, on: site)` already equals the ID, reply `true` without appending. Otherwise append `PinEvent(host: site, kind: kind, valueID: id, date: now())`. Also append a `UsageEvent` for the value on the site, so `usedHere` ranking has it even when the pin is later cleared.
- Don't call `CardWriter`. The sheet's `choose` keeps rewriting until Phase 4.
- Respect `matchEachSite`: when it's off, reply `false` and append nothing.
- Rate: `ExtensionEvents.pins` is capped at 100; add a per-minute cap of 10 picks (same pattern as `maxCardWritesPerWindow`) so a stuck page can't churn the event log.
- Tests (`PicksTests.swift`): pin appended for a card value; no append for a value not on the card; no duplicate append; off when `matchEachSite` is false; `contactSuggestions` puts the picked value first on the next call (this proves the ranker reads the folded pin).

### 1.3 Dropdown reports picks

- `Choice` gains `onPick?: () => void`. `dropdown.ts` `pick` calls it after `fillField`, only for a pick made by a trusted click or Enter (both paths already require `isUserEvent`).
- `suggestions.ts`: when building choices (`suggestionOptions`, around line 99/195) attach `onPick` that sends `{type: "picked", host, kind, value}` through `browser.runtime.sendMessage`. Fire and forget; ignore the reply except in tests.
- Don't report a pick of the value that was already first (index 0): it carries no new information and saves a round trip.
- Done for contact fields. `installFilledPicker` in `fill.ts` builds its own choices (`applyText`), so a pick on a field Fill form filled isn't reported yet; that moves to 2.4.
- Tests (`suggestions.test.ts` or `dropdown.test.ts`): picking the second row sends one `picked` message with the right kind and value; picking the first sends none; a synthetic click sends none.

### 1.4 Links

- Links are ordered by `ManualOrder` in `LinkMessages.swift` and then by `linkOptions` in `links.ts` (combined "A - B" first, then one per type, max 3). A pin should win inside a type: if the person picks their personal site over their portfolio for "Website", that one comes first on the site.
- In `LinkMessages.swift`, after `ManualOrder`, stable-sort so the value pinned for `(site, .link)` comes first.
- In `links.ts`, attach `onPick` for single links. A pick of the combined "A - B" choice isn't a single value; don't report it.
- Test: one Swift test that a pinned link comes first; one TS test that a link pick sends `picked`.

### 1.5 Custom answers

Custom fields are matched by words (`CustomFieldMatcher.values`), up to 3, plus model guesses. When several match ("School" vs "High school") the person's pick should come first next time, on any site, for questions with the same words.

- Store per-device: `ExtensionEvents` gains `answerPicks: [AnswerPick]` where `AnswerPick{words: String (CustomFieldMatcher.words of the question, sorted, joined), label: String, date}`. Cap 200, newest wins.
- `customSuggestions` reorders each field's `values` so the picked label's value comes first when the words match.
- Picking a **guess** (`detail: "Suggested"`) records the same pick. Since a guess is always one of the person's own custom values (the model picks among them), the pick alone makes it a real value for that question next time, with no Contacts write. (Built this way instead of saving the guess as a learned answer: nothing new needs storing on the card.)
- Tests: reorder by pick; a guess pick becomes a value next time; cap respected.

### 1.6 Mac panel

- `MacApp/Autofill/AutofillEngine.swift` `pick` (around line 218) calls the router directly (the engine already holds a `MessageRouter`) with the same `PickedRequest`, using the host from `FieldReader.host`. Skip when the host is empty (native apps).
- `mac/autofill.ts` `rows` returns the kind per row already; add `question` for custom rows so the Swift side can send it.
- Test: one Swift unit test at the engine boundary if it's testable without Accessibility; otherwise rely on `scripts/e2e-mac-ax.sh` with one added step.

### 1.7 Check and merge

- Real check: `web/src/e2e/fillChrome.ts` gains a case on `testbed/` with two emails: click the email field, pick the second, reload, click again, the second is first. The fake host (`fakeHost.py`) needs to keep pins between calls; if that's too much fake, run the same steps by hand in Chrome against the installed Mac app and record a screenshot in `assets/generated/`.
- Safari: one `UITests` step in `ExtensionE2ETests` (pick the second email in Prefill's list, refocus, it's first). Only Prefill's list changes in this phase; Safari's own bar still follows the card.

---

## Phase 2: Honest suggestions

### 2.0 Stale Safari tests

`CustomFieldsE2ETests`, `LinksE2ETests` and `MinimalCardE2ETests` still expect Prefill's values in Safari's keyboard bar (the datalist path). Since `d070f61` Safari shows Prefill's own list under the field instead, so the bar shows keyboard predictions ("I", "The") and all three fail (seen in the full run on 2026-10-06; none was changed after `d070f61`). Change each to find Prefill's rows in the web view, as `PickE2ETests.row(_:)` does, and keep their intent: School offers the custom answer, GitHub/Portfolio offers the links in order, a minimal card's moved emails are still offered. Run the whole suite (`zsh scripts/test.sh e2e`; it takes about 15 minutes and must not overlap another session's run on port 8846).

**Why:** with click-and-pick as the default, the list is the product. It should say why each value is there, so a person trusts the first row and knows when the last row is a guess.

**Done when:** every row in the list has a true detail line from a small fixed set, guesses look different from known values, and Fill form tells you which fields still need you.

### 2.1 Where each value came from

Add an optional `why` to each suggested value in the three replies:

| `why` | Meaning | Detail line shown |
|---|---|---|
| `pinned` | Picked on this site before | "Used here" |
| `used` | Typed or picked on this site before | "Used here" |
| `card` | On your card or Prefill's contact | the kind or label ("Work email", "LinkedIn") |
| `learned` | Saved from a form you submitted | "From <site>" |
| `guess` | The on-device model's pick | "Suggested" |
| `resume` | From the resume import (Phase 7) | "From your resume" |

- Wire shape: keep the arrays of strings for compatibility and add parallel arrays, `emailWhy: [Why]` etc., or switch each array to `{value, why}`. Prefer `{value, why}`: both sides ship together and there's no older extension in the wild. Bump the examples file.
- Swift: `Ranker` already knows the tier that put each value where it is (`pinned`, `usedHere`, ...). Expose it: `Ranker.rank` returns `[(ContactValue, Tier)]` via a new `rankWithTiers`, and the suggestion routers map tiers to `why`.
- Learned answers know their host (`LearnedAnswer.host`).

### 2.2 The list shows it

- `dropdown.ts` `Choice` gains `tone?: "guess"`. Guess rows show the value in the muted text color and the detail in the accent color, with no new font; everything else is unchanged. Keep the "Prefill" footer.
- `suggestions.ts`, `links.ts`, `custom.ts` and `mac/autofill.ts` build `detail` from `why` through one shared function (`web/src/why.ts`), so all three surfaces say the same words.
- Mac `SuggestionPanel` renders the same detail and tone.
- Tests: one table test for `why.ts`; one dropdown test that a guess row has the tone.

### 2.3 A later answer replaces a learned one

Today a learned answer is never replaced (AGENTS.md open item). With click-and-pick, the person often types a newer answer into a field Prefill offered an old one for.

- In `learn.ts`, when a submitted value differs from the learned answer for the same question, send it with `action: "replace"`.
- Router: replace the custom field's value through `gateway.save(scope: .personEdit)`, only for a field Prefill learned (match `ExtensionEvents.answers` by label), never for one the person wrote in the app. Keep the old value in the event for Undo.
- The page shows the existing "Saved" pill as "Updated your answer" with Undo.
- Tests: replace happens for a learned field; refused for a hand-written one; Undo restores.
- Built differently: the page can't tell which answers Prefill learned, so `learn.ts` keeps sending `action: "learn"` and the router decides, replacing only a field whose value matches one of its learned answers. The reply gained `updated`; there's no `replace` action.

### 2.4 Fill form says what's left

Fill form stays optional (the pill beside a field, Fill in Safari's sheet, Fill form in the Mac panel).

- After a fill, the pill reads "Filled 9 · 4 need you". Clicking "4 need you" focuses the first empty, visible, editable field in page order (`findSlots(fillScope(...))` minus what was filled), which opens Prefill's list there by the normal focus path. Each next click moves to the next one.
- Focus moved by Prefill's own button is a trusted gesture from the person's click, but `gesture.ts` won't see it as one. Unlock exactly the focused field for 1 s through a new `gate.allowNext(field)` that only the pill can call (it's in the closed shadow root).
- Guesses are still never filled.
- A pick on a filled field (`installFilledPicker`, choices built in `applyText`) reports `picked` like any other list (carried over from 1.3).
- The pill's count today counts recognized fields, so "Fill form 13 fields" can end as "Filled 9". Change the count to fields Prefill has an answer for (it already fetched them for the prefetch), so the promise matches the result.
- Tests: the "need you" count; the jump focuses the right field; `allowNext` unlocks one field once.
- Built: the grant is shared by every gate on the page (each list keeps its own gate) and ends when the field loses focus, another takes focus, or after 1 s. The pill's count is async now: it gathers the form's answers on focus (only for forms with at least 3 recognized empty fields). A filled field's list uses `SAFARI_CONTACT` for contact fields in Safari; whether Safari's bubble shows on a filled field wasn't checked in the simulator, it's assumed from it showing on any contact field. `testbed/sites/application.html` gained "Why do you want to work here?", which nothing answers, for the jump.
- Known and accepted: whether the pill shows (and its count) tells a page, after the person's click or Tab, that Prefill has answers for at least 3 of its fields. It's inherent to offering a pill only where it would fill something.

### 2.5 Keep the list clear of Safari's bubble

**Done early, in Phase 1** (`feat/picks`), because it broke click-and-pick on the iPhone: Safari doesn't just cover the first row, it swallows every tap in a band under a contact field. In the simulator a tap 72 pt under the field reached nothing, one 122 pt under it reached the page, and Prefill's list got no pointer, mouse or click event for a tap on its second row. Built: `SAFARI_CONTACT` placement in `dropdown.ts` (list above the field, clear of the Fill form pill, else 124 pt below, else the roomier side, cut to fit and scrolling), used only for contact fields in Safari (`page.ts`). Rows are now buttons. Still open: the list on a field Fill form filled (`installFilledPicker`) uses the default placement; check whether Safari's bubble shows on a filled field and apply the same placement if it does (with 2.4). Also measure the band at the largest Dynamic Type size.

Original notes:

Seen in the Phase 1 simulator run (`assets/generated/e2e-ext-pick-a-before.png`): on an email field with card values, Safari draws its own suggestion bubble ("home" / "work") directly under the field, over Prefill's first row, which is the row the person most needs.

- In Safari only, when the field is one Safari suggests for (a contact kind while the card holds values of that kind), place Prefill's list below the bubble's band (about 60 pt) or above the field when there's more room there. Chromium is unchanged.
- The band height can't be read from the page; measure it in the simulator at the default text size and at the largest Dynamic Type size, and keep the offset as one named constant in `dropdown.ts`.
- Phase 4 removes most of the cause (a short card leaves Safari nothing to suggest for email and address), so keep this small and remove it there if the bubble no longer shows.
- Check: `PickE2ETests` asserts the first row's frame doesn't intersect the bubble.

### 2.6 Check and merge

- `FillE2ETests` (Safari) and `fillChrome.ts`: the "need you" jump on the Greenhouse testbed page.
- Screenshot of the list with a guess row in light and dark, into `assets/generated/`.

---

## Phase 3: One memory

**Why:** every feature so far reaches into `CardRecord`, `CustomField`, `LearnedAnswer` and the events separately. One read model makes the inbox, the You tab, resume import and "Used on" straightforward, and keeps Contacts details in one place.

**Done when:** suggestion routers and the app's lists read `Memory`, and nothing outside `Card/` knows how custom fields are encoded.

### 3.1 Types

New folder `Packages/PrefillKit/Sources/PrefillKit/Memory/`:

```swift
public struct Answer: Identifiable, Hashable, Sendable {
    public enum Question: Hashable, Sendable { case kind(ContactKind), custom(label: String) }
    public let id: UUID            // ValueID for contact values and links, a v5 UUID of "custom:<label>" for custom fields
    public let question: Question
    public let text: String         // display text
    public let label: String?       // "work", "GitHub", nil
    public let origin: Origin       // .card, .captured(host), .learned(host), .typedInApp, .resume
    public let place: Place         // .meCard, .prefillContact (where it's stored now)
    public let createdAt: Date?
}

public struct Memory: Sendable {
    public let answers: [Answer]
    public let name: (given: String, family: String)
    public func answers(for question: Answer.Question) -> [Answer]
}
```

- `Memory.read(gateway:, state:, events:)` builds it from `CNContactStoreGateway.fetchCard` (+ `placement` for `place`), `AppState.values` (origin and dates), `ExtensionEvents.answers` and `captures`.
- Writes stay where they are (`CardWriter`, `CardEditor`, the answers path). `Memory` is read-only in this phase.
- Tests: built from a fake gateway with a minimal and a full card, both give the same answers with different `place`.
- Done as: `Memory.read(card:placement:state:events:)` is the pure core and `Memory.read(gateway:identifier:state:events:)` wraps it. `name` is a `Memory.Name` struct (a tuple isn't `Hashable`), `.captured(host:)` takes a `String?` because the capture can age out of the events, and a custom field's `label` is nil (the question carries it).

### 3.2 Routers read `Memory`

- `contactSuggestions`, `linkSuggestions`, `customSuggestions`, `popupState`, `savedAnswers` take their values from `Memory`. Ranking stays in `Ranker`.
- No behavior change; the existing tests are the check.

**Done differently (Oct 6):** the routers keep reading `CardRecord`. They rank with `CardPlan` and `Ranker`, which work on card entries and labels, and the custom matcher needs each field's match words, which `Answer` doesn't carry; rerouting through `Memory` would mean converting back inside every router for no change in behavior. `Memory` is the read model for the app's screens (Phase 5, `MemoryLookup`) and for "Used on". What 3.2 did change: a custom answer picked from Prefill's list now records the site (`AnswerPick.host`), so it shows under "Used on".

### 3.3 "Used on"

- `Memory.uses(of: Answer) -> [Use{site, date}]` from `UsageEvent`s, picks (Phase 1) and learned answers.
- Used by the You tab's value detail (5.2) and the inbox.
- Done as: `Memory.Use` (sites are registrable domains). Contact picks count through the UsageEvent and PinEvent they leave; a picked custom answer can't, because `AnswerPick` keeps no site.

### 3.4 Merge

Full checks. No device step.

---

## Phase 4: Freeze the Me card

**Gate:** ask Tarun before starting, in one line: "Phase 4 stops Prefill from reordering your contact card per site. Safari's own bar will show only your name and phone; Prefill's list under each field shows everything else. Go?" Don't start without a yes.

**Why:** with Prefill's list on every field (`showDropdown` in Safari since `d070f61`), rewriting the card per site is duplicate work. It also costs: every rewrite syncs to every device, it renumbers identifiers, and it's what disturbed NameDrop's picked number. The card should be the thing you share.

**Done when:** Prefill never writes the Me card except when the person edits it in the app or confirms a move; a fresh setup ends with a name-and-phone card; Safari shows Prefill's list for emails, phones, addresses, links and custom answers.

### 4.1 Stop per-site rewrites

- Delete `web/src/context.ts` and its install in `page.ts`; `pageNeeds.ts` uses `contactFields()` from it, so move that function into `classify.ts` or a small `fields.ts` first.
- Remove the `pageContext` message from both contracts, docs and examples, and `MessageRouter.pageContext`, `noteCardWrite`, `ExtensionEvents.cardWrites`. Keep reading `cardWrites` from old stores (decode and ignore).
- `CardWriter.sync` keeps working for additions (capture saves) but always with a host-less plan, so it never orders by site.
- App: `AppModel.syncCard(host:)` callers (`reorder`, `add`) sync without a host. `Settings.matchEachSite` now only controls Prefill's list order; rename its label to "Put the value you used on a site first".
- Test: `CardWriter` with a host gives the same target as without; capture still saves.

### 4.2 Prefill's list for every contact kind in Safari

- `page.ts` already installs `installSuggestions` with `showDropdown` on both browsers. Check the Safari path doesn't skip contact kinds when the card has values (the old reason was "Safari fills them from the card").
- Name fields: Safari's bar keeps offering the name from the card, so Prefill's list skips name fields in Safari to avoid two lists.
- Simulator check (`MinimalCardE2ETests` updated): email, phone, address fields show Prefill's list; the bar shows name and phone only.

### 4.3 Short card for everyone

- Onboarding: the Sharing step stops being optional. It shows the exact list that will move to Prefill's contact and one button, "Keep only name and phone on my card". "Not now" stays, and leaves the card as it is (Prefill still works, Safari's bar just shows card values too).
- Existing users: on the first launch after this phase, if the card isn't minimal, the inbox (Phase 5) or, before then, a sheet on launch shows the same list and button once. Never move without that confirmation (AGENTS.md rule).
- The phone kept on the card is the one the person picks; default the first. `CardSplit.minimalCardEntries` already never reorders it.
- Mac: the Sharing section gets the same one-button flow and "Put back on card" (an AGENTS.md open item), using `moveOntoCard`.

### 4.4 Remove the datalist path and `offCard`

- Delete `web/src/datalist.ts`; `links.ts`, `custom.ts` and `suggestions.ts` take `attach` as required, with `showDropdown` passed from `page.ts`.
- Remove `offCard` from `messages.ts`, `SuggestionMessages.swift` (`leavingOut`, the minimal branch), `fakeHost.py`, docs and examples.
- Tests: delete datalist tests; contract tests pass.

### 4.5 The sheet pins without rewriting

- `MessageRouter+Popup.swift` `choose` appends the `PinEvent` and stops; no `CardWriter`.
- The sheet's header changes from "Safari will suggest here" to "First on this site". Its bar replica goes; it lists values with the pinned one first.
- `PopupE2ETests` updated: a pick in the sheet puts the value first in Prefill's list (not the bar).

### 4.6 Device check and merge

On the iPhone (unlocked, cable or Wi-Fi):
1. NameDrop with another phone sends name and the chosen number only.
2. Share Contact sends name and phone.
3. A Greenhouse form: email, phone, LinkedIn, School all offer through Prefill's list; Safari's bar shows name and phone.
Record what was checked in AGENTS.md Ongoing. If the phone isn't reachable, mark 4.6 `[~]` and merge anyway after the simulator checks, then come back.

---

## Phase 5: The app is an inbox

**Why:** the person shouldn't manage a database. They should glance at what Prefill learned, fix the odd one, and leave.

**Done when:** the iPhone app has three tabs, Inbox, You and Settings, and the Mac menu shows the inbox first.

### 5.1 Inbox (iPhone)

- Replaces "Recently added". One list, newest first, of everything Prefill added or wants to add: captured values waiting for review, captured values saved, learned answers, picks that changed a site's first value (from Phase 1), and, in Phase 7, resume answers.
- Each row: the value, one line saying what happened ("Saved from greenhouse.io", "Learned: Graduation date"), and actions that fit: Keep / Remove for saved items, Add / Dismiss for waiting ones, Edit for answers.
- Empty state: "Nothing new. Prefill adds what you type into forms, and it shows up here."
- Badge on the tab: items waiting for a decision only.
- Source: `RecentCaptures`, `ExtensionEvents.answers`, picks, via `Memory`. `RecentScreen.swift` is the starting point; rename to `InboxScreen.swift`.
- Done as: "Needs you" (waiting) on top, then "Recently". Each row leads with a state mark (ring, check, minus, pin, sparkle; `Palette.attention` for waiting). A value removed or dismissed stays in Recently with Add, so nothing leaves the list. Picks come from `ExtensionEvents.pins` still in force (`AppModel.firstPicks`); a pin made in the app isn't an event, so it doesn't show.

### 5.2 You (iPhone)

- Replaces the Card tab. A search field on top, then groups: Contact (emails, phones, addresses), Links, Answers. No segmented control.
- A row opens a detail: the value, its label, where it's stored ("On your card" / "Only in Prefill"), "Used on" (3.3) with sites and dates, and Edit / Remove. Pins show here as "First on: greenhouse.io, lever.co" with a remove control per site.
- Add: one "Add" button with a menu (Email, Phone, Address, Link, Answer).
- Reorder stays for emails and phones (it sets the default order when no site rule applies), in an Edit mode, not always on.
- The student starter set moves into the Add menu as "Common student answers…".
- Done as: `YouScreen`, `YouList` and `AnswerDetail` read `Memory` for "Used on" and where a value is stored. A contact value has no value editor, so its Edit is the label menu (with "Custom label…"); an answer edits in `CustomFieldSheet`. "First on" lists `AppState.pins` for the value, and removing one unpins it. The Sites screen moved under Settings, and the Card tab's bar and kind picker are gone (`KindHeader` stays for the site screen). Added rows sit below the fold, so the e2e tests search for them.

### 5.3 Settings

Keep: Save new info (toggle), Put the value you used on a site first (toggle), Sharing your card (row with status "Name and phone"), Intelligence status line, Choose a different card, Restore original card, Delete Prefill data. Group the last three under "Advanced".

Done as: Advanced also holds Sites until 6.2 removes it. The Safari section (the extension's two switches and "Open Safari settings") stays, since nothing else in the app says when the extension is off. The Safari sheet's popup still says "Reorder for each site"; that copy lives in `web/`.

### 5.4 Mac menu

- `MenuContent`: the inbox first (from `ReviewList`, extended with learned answers and resume items), then the engine toggle, then "Open Prefill Settings…".
- `SettingsView`: You (searchable list like 5.2, with `CustomFieldsSection` folded in), Sharing, Browsers, Advanced.
- Done as: the menu shows the card status only when something stops Prefill (no access, no My Card), otherwise the inbox: "Needs you" with Add / Dismiss and the last three learned answers with Remove, or "Nothing new". Settings searches with a plain field, since a Settings window has no toolbar for `.searchable`; the switches sit after the lists, and Advanced holds the card status and the switch for every app. `Memory.answer(forValue:)`, `answer(for:)` and `useCount` (PrefillKit `AppSupport/MemoryLookup.swift`) serve both apps.

### 5.5 UI tests and merge

- `AppTourTests.testTour` walks the new tabs and refreshes screenshots.
- `LinksE2ETests` and `CustomFieldsE2ETests` add values through the You tab's Add menu.
- Load the `better-ui`, `better-layout` and `better-writing` skills before building the screens.

---

## Phase 6: Cuts

**Why:** each of these costs maintenance and none is part of click-and-pick.

### 6.1 Siri, Shortcuts and the Focus filter

- Delete `App/Intents/` (GetValueIntent, BarPreviewSnippet, PromoteValueIntent, PreferInfoFocusFilter, PrefillShortcuts, IntentTypes, AppModel+Intents) and `PrefillApp.swift`'s AppIntents dependency registration.
- Delete `AppSupport/ValueLookup.swift` if nothing else uses it, `Settings.focusLabel` and the Ranker's `focusLabel` tier (decode and ignore the old setting).
- Remove `IntentsHostTests.swift`.

### 6.2 Sites tab

- Delete `App/Screens/Sites/`. Pins are managed in the You tab's value detail (5.2); a muted site ("Don't save on this site") is listed under Settings › Advanced › Sites Prefill doesn't save on.

### 6.3 Match words

- Remove the match-words field from `CustomFieldSheet` and the Mac `CustomFieldForm`. Keep decoding the third label part and keep using stored match words in `CustomFieldMatcher`, so existing fields keep matching. The model's guesses cover what match words were for.

### 6.4 Merge

Full checks.

---

## Phase 7: Resume import

**Why:** the first application is where Prefill has to earn trust, and today it knows nothing until you've filled a few forms by hand.

**Done when:** on the iPhone and the Mac, the person picks a PDF, sees the answers Prefill found with checkboxes, and saves the ones they keep. The next job application offers them.

### 7.1 Text and rules

- `Packages/PrefillKit/Sources/PrefillKit/Resume/ResumeText.swift`: PDFKit `PDFDocument(url:).string`, capped at 20 000 characters. Fail with "This PDF has no text. Export it again from your editor, or try another file." for scanned PDFs.
- `ResumeRules.swift`: emails, phones (by `Normalizer.phone`), and links (`LinkURL`, `LinkType.of`) by pattern. These never need the model.
- Tests: three real resumes' text (anonymized, Tarun's own with his OK, or public samples) as fixtures in `Tests/.../Fixtures/`.

### 7.2 Model pass

- `ResumeReader.swift` in `Intelligence/`: a FoundationModels session with a `@Generable` struct for the answers that `JobQuestion` and `StudentStarter` already name (school, degree, major, graduation date, current company, title, years of experience, city, work authorization only if the resume states it). Every field optional; the instructions say to leave out anything not written in the text.
- Validate each value through `CustomField.make` limits and drop anything that isn't found verbatim (or as a normalized date) in the text. That stops invented answers.
- Without Apple Intelligence, only the rule pass runs and the review screen says so in one line.

### 7.3 Review screen (iPhone)

- Entry: You tab › Add › "Import from resume…", and onboarding (7.5).
- `.fileImporter` for PDF. Then a list grouped like the You tab, each row checked by default, values editable inline, rows already in memory shown as "Already saved" and unchecked.
- "Save N" writes contact values through `CardWriter` additions (they go to Prefill's contact on a minimal card), links through the links path, answers through `gateway.save(scope: .addAnswers)`. The never-drop guard's "at most 3 additions per kind" applies; if a resume has more, save the first 3 per kind and say how many were left out.
- Each saved answer's origin is `.resume`, recorded in `AppState.values` / a new event, so `why: resume` shows in the list.
- The PDF is read and dropped; nothing of it is kept.

### 7.4 Mac import

- Settings › You › "Import from resume…" with `NSOpenPanel`, then the same review as a sheet. Shares `ResumeText`, `ResumeRules`, `ResumeReader` from PrefillKit.

### 7.5 Onboarding and merge

- Onboarding gains an optional step after the card: "Have a resume? Prefill can read it and fill in your answers." with Import and Skip.
- Real check: import a real resume on the simulator, then the Greenhouse testbed page offers School and Graduation date with "From your resume".

---

## Phase 8: One Mac engine

**Gate:** Phases 1 and 2 merged (the extension and panel then behave the same).

**Why:** today, when the Accessibility engine is on and trusted, it owns suggestions everywhere and the extension stands down (`AutofillMode` in `AutofillWorker.swift`, applied in `RelayServer.serve`). But in Chromium the extension has the page itself: real `autocomplete` attributes, React-Select, picks, capture, learning. The engine reads a delayed Accessibility tree without those.

**Done when:** in a Chromium browser where Prefill's extension has talked to the app in the last minute, the extension's list shows and the panel stays away; everywhere else the panel works as today.

### 8.1 The extension owns pages it's running in

- `RelayServer` records the last request time per browser bundle ID (the host already checks its parent's signature, so the app knows which browser).
- `AutofillEngine.focused` skips a field when the front app is in `FocusWatcher.chromium` and that browser's extension spoke within 60 s.
- `AutofillMode.standDown` applies only to browsers without a recent extension request.
- As built: `ExtensionPresence` keeps the browser's pid from the host's parent and counts the browser until that process quits, so a long stay on one page never brings the panel back beside the extension's list. Only browsers running the extension send requests, so the stand-down had nothing left to do and is gone; Fill form in Chrome gets the card's values again.
- Tests: unit test on the decision function (front app, last request time, now).

### 8.2 Accessibility for everything else

- No change for Safari on the Mac, Electron apps and native apps. Keep `Fill form` in the panel.
- Note in AGENTS.md: Arc, Safari, Electron and Firefox are still untested in the panel.

### 8.3 Checks and merge

`scripts/e2e-mac-chrome.sh` with the engine on: the extension's list shows, not the panel. `scripts/e2e-mac-ax.sh` in a non-browser app still works. Both need an unlocked screen; if it's locked, mark `[~]`.

---

## Phase 9: Setup in three steps

**Why:** setup today is card, chooser, sharing, Safari switches, then on the Mac Contacts, Accessibility and an unpacked extension. Most of that is unavoidable; the order and the words can be much better.

### 9.1 iPhone onboarding

1. **Your card.** Find it (or choose one), show it, and offer "Keep only name and phone on my card" with the exact list (4.3). Until Phase 4 is approved this is today's optional Sharing offer.
2. **Turn on Prefill in Safari.** The switches, with a live check that turns green when the extension has seen a page (the existing `lastPageSeen` signal).

The "Your answers" step (resume import, 7.5) went with Phase 7.

As built: `OnboardingStepLayout` shows "Step 1 of 2"; the linked card step lists the card's emails, phones and addresses; `SafariStep` rereads the extension's state every 2 seconds while it's on screen; `DoneStep` finishes.

Done screen: "Click any field in Safari and pick a value."

### 9.2 Mac first run

The menu shows a three-item checklist until each is done: Allow Contacts, Turn on Accessibility (with the exact Settings path and an "Open" button), Add the browser extension (Copy folder path, Open chrome://extensions instructions). Each item checks itself.

As built (`MacApp/Views/SetupChecklist.swift`): Contacts is the authorization status; Accessibility is `AXIsProcessTrusted` (or done while "Suggest in every app" is off); the extension is done once the relay has answered Prefill's host (stored, so it survives relaunch) or the person chose "Skip this step". The menu rechecks every 2 seconds while open.

### 9.3 Tour test and merge

`AppTourTests.testTour` covers the new flow.

---

## Phase 10: Docs

### 10.1 Describe v2

- PRODUCT.md: part 1 gains the Oct 6 request row; part 2 rewritten around click-and-pick, the memory, the short card and the inbox; the diagram loses the card-reorder arrow; "Decisions worth knowing" records why the card freeze and the single list replaced card steering.
- AGENTS.md: data model section names `Memory`; open items updated; Ongoing reset.
- README.md: what the iPhone gets is "Prefill's list under each field", not "Apple's own suggestion bar".

---

## Phase 11: Outside Safari on the iPhone

**Why:** asked for on Oct 7 after Partiful's in-app form (opened from Messages) got nothing from Prefill. On the iPhone, Prefill only runs in Safari: iOS lets a Safari Web Extension into Safari pages and nowhere else. In other apps today, the only reach is the contact card, which iOS's own bar offers on fields an app marks as email, phone or address; links and custom answers never get there.

**Done when:** in a third-party app (Partiful is the reference: "What is your Github profile link?", "What is the name of your company?"), the person can put a saved link or custom answer into a field in two taps or fewer, on Tarun's iPhone, with the free personal team.

### 11.1 Spike: long-press insert

- `research/REPORT.md` (Spike results, "Text insert") found a credential provider that declares only `ProvidesTextToInsert` is listed under the field's edit menu (AutoFill › Passwords › provider), but the inserted text never landed in the Simulator ("requires a valid sessionID"), and `ASSettingsHelper.requestToTurnOnCredentialProviderExtension` never prompted. Code is in `spikes/textinsert`.
- Re-run that spike on the iPhone, signed with the personal team (check the credential-provider entitlement is allowed there; if it isn't, record that and stop).
- Check in a native app (Notes, then Partiful) and in Safari: is Prefill listed, how many taps, does the text land, can it offer links and custom answers (read from the Prefill contact through Contacts, which the extension can reach if it inherits the app's grant; verify).
- Also note whether iOS's own edit menu "AutoFill › Contact" offers fields from the person's card, including URLs, since links already live on the Prefill contact and could be put on the card.
- Record results with screenshots in `assets/generated/spike-device-textinsert-*.png` and a row in REPORT.md's spike table.

### 11.2 Spike: Prefill keyboard

- A minimal custom keyboard extension (new target, `spikes/keyboard` first, not in the shipping project) with one suggestion row above a standard key layout, or only the suggestion row plus a globe key to switch back.
- The open question is data: the free team has no App Groups (AGENTS.md). Try, in order, and record which works on the device:
  1. The keyboard with `RequestsOpenAccess` reading Contacts directly (does a keyboard extension get Contacts access at all, and does it inherit the app's grant?).
  2. A shared Keychain access group (is `keychain-access-groups` allowed for the personal team?) holding a small export of values the app writes.
  3. Values carried on the Prefill contact only, read through Contacts.
- Show values matched to the field the way the Mac panel does: the keyboard sees the host app's `textContentType`, `keyboardType` and the text around the cursor (`documentContextBeforeInput`), not the field's label, so measure how well it can guess the question (Partiful's fields are plain text boxes) and fall back to a short list (email, phone, LinkedIn, GitHub, most-used answers).
- Note the costs to tell Tarun: switching keyboards, no secure fields, apps that refuse third-party keyboards, and Full Access's privacy prompt.

### 11.3 Decide and build

- Bring both results to Tarun with the tap count and what each can offer. Build only the chosen one, as its own branch, with the same safety rules as the extension (never in password or one-time-code fields, nothing sent anywhere).
- Results: 11.1 stopped at signing, since the free team can't get the AutoFill credential provider entitlement (it needs a paid membership). 11.2 worked on Tarun's iPhone: with Full Access on, the keyboard read 9 values from a keychain item the app wrote. The spikes stay in `spikes/` as the record. Tarun chose the keyboard.
- Built as: target `PrefillKeyboard` (`Keyboard/`, bundle ID `<app>.keyboard`, `RequestsOpenAccess`), embedded in the app for both configurations, with the app's keychain group (and App Group for AppStore); no new restricted entitlements.
  - Data: `PrefillKit/Keyboard/`. `KeyboardSnapshot.make(memory:)` turns `Memory` into up to 80 `KeyboardValue`s (name parts, emails, phones, one-line addresses, links, answers; each kind most recently used first, from `uses(of:)`). `KeyboardShare` stores it as the `keyboard-values` document in the same store as the app state (keychain item or App Group file), and the keyboard writes `keyboard-seen` each time it's shown. Both go with "Delete Prefill data". The app writes the snapshot after each card refresh and each `commit` (`AppModel+Keyboard.swift`), only when the values changed.
  - UI: `KeyboardUI/` is shared by the keyboard and the app (its debug preview, `App/Preview/KeyboardPreview.swift`, launched with `-keyboardPreview`). A 290 pt panel: ABC (next keyboard) on the leading edge, return (labeled from `returnKeyType`) and delete (repeats on hold) on the trailing edge, then key-shaped rows grouped "For this field" (from `textContentType`/`keyboardType`), Contact, Links, Answers. A tap types the value and switches back to the person's keyboard. Password, one-time-code and card fields get a line saying Prefill doesn't type there. Colors come from `KeyboardPalette`, which the app's `Palette` also reads.
  - App: Settings › "Use Prefill in other apps" explains the three steps and shows "On" once the keyboard has been shown.
  - Checked in the simulator: screenshots `assets/generated/keyboard-*.png` (light, dark, a 375 pt phone, the largest text size before the accessibility sizes, empty state), and the real keyboard enabled in a simulator (`keyboard-sim-installed.png`, before Full Access). Not yet checked on the iPhone.

## Phase 12: Keyboard v2

**Why:** Tarun likes the keyboard but finds the full-width list too big and prefers the spike's row of chips, and in real apps (Partiful) "For this field" never appears, because most apps set no `textContentType` and iOS never gives a keyboard the field's label.

### 12.1 Compact row

- Height close to the system keyboard's suggestion area plus one key row (about 110 to 130 pt), not 290.
- Row 1: a horizontally scrolling row of chips, caption over value like the QuickType bar, each chip sized to its content up to a maximum width with middle truncation. Chips never clip at the edges: the row has leading and trailing insets, and the next chip peeks to show the row scrolls.
- Row 2: ABC on the leading side; a small kind filter in the middle (All, Contact, Links, Answers) only if it fits without crowding; return then delete on the trailing side, delete rightmost.
- Tapping a chip types it and returns to the person's keyboard, as now.

- As built (`feat/keyboard-v2`): the panel is 112 pt (6 top, a 52 pt chip row, 6, a 44 pt key row, 4). Chips are key-shaped, caption (footnote) over value (callout), sized to their text up to 70% of the keyboard's width, value truncated in the middle. The row scrolls inside the keys' 3 pt edge, so the first chip lines up with ABC. `KeyboardChipLayout` makes sure the next chip peeks in: a chip that would end near the edge (hiding the next, or cut by less than 48 pt so it looks clipped) gives up width so the next shows 28 pt. The row scrolls back to the start whenever the order changes. Text is capped at xLarge so the height holds. Row 2 is ABC, then return and delete, delete rightmost. The kind filter is left out: on a 375 pt phone ABC, return and delete leave about 150 pt, and four segments need more without crowding; the ranking does that job. Empty states are one line in the chip row ("Open Prefill once to share your info.", "Turn on Allow Full Access for Prefill in Settings.", "Prefill doesn’t type passwords or codes."). Screenshots: `assets/generated/keyboard-v2-{light,dark,375,large-text,empty,not-here,typed-git}.png`, from the app's debug preview (`-keyboardPreview`, now also `-keyboardTyped git`).

### 12.2 The likely value first

Signals, strongest first:
1. What's already in the field (`documentContextBeforeInput`): "git" or "github.com/" narrows to GitHub, "@" to emails, digits to phones; matching is on the value and its caption.
2. The field's content type and keyboard type, as now.
3. What the person picked in this keyboard most recently (kept by the keyboard in its own defaults, most recent first, per kind), then what was used most recently anywhere (`lastUsed` in the snapshot).
4. A fixed fallback order: name, primary email, phone, LinkedIn, GitHub, website, then answers.
The row re-sorts as the person types (`textDidChange`). No field label exists to use, so nothing claims "for this field" without a signal.

- As built: `PrefillKit/Keyboard/KeyboardRanking.swift` and `KeyboardTyped.swift`, pure, tested in `KeyboardRankingTests`. Sort keys in order: typed score (3 the value, its link without scheme or `www.`, or its caption starts with the last typed word; 2 contains it; 1 the kind it suggests, an "@" for emails; for a word of phone characters, phones by digits, with or without the leading 1), the field's traits (`FieldTraits.hint`), the keyboard's recent picks (`KeyboardRecents`, by value id, most recent first, capped at 30, kept by `Keyboard/KeyboardPicks.swift` in the keyboard's own `UserDefaults`, no Full Access needed), the snapshot's `lastUsed`, the fallback (full name, primary email, primary phone, LinkedIn, GitHub, website, answers, then the rest), then the snapshot's order. A value the field already ends with is left out. A tap replaces the word that led to the value (as QuickType does: "github.com/" becomes the full link) and records the pick. The row re-sorts on `textDidChange`. "For this field" and the groups are gone.

### 12.3 Device check

Install on Tarun's iPhone, check in Partiful and Messages, screenshots light and dark.

## Phase 13: Answers that are right, not just remembered

**Why:** the Oct 7 review (`outputs/prefill-product-review.md` in Tarun's notes) found Prefill remembers strings better than it knows when they apply. Decisions: demographic questions keep today's rule (decline when offered, otherwise "No"); storage stays on Contacts until Phase 14.

### 13.1 Abstain on ambiguity
- `web/src/choices.ts`: when more than one option matches the answer with similar strength (two "Yes…" options that mean different things), Fill form leaves the field and marks it "2 options fit, pick one"; it counts toward "need you". Real markup fixtures for the case.
- Built: `matchOption` scores every option and counts those within 0.1 of the best; an exact match wins outright. Fill form leaves a select, radio group or React-Select box with more than one fit, outlines the select or group (dashed amber, until the person's own change or Undo), and the pill shows the note when "need you" reaches it (`noteFor`). The pill's offer count leaves such fields out. Fixture: `web/src/fixtures/ats-lever-sponsorship.html` (Lever card markup, wording from real custom questions). The Mac's Fill form fills text fields only, so it never chooses options and needed no change.

### 13.2 Scoped learning
- `learn.ts` sends the question as asked (and a select's or radio group's options), not only a `JobQuestion` category.
- The router keeps scope in the stored label so it still syncs through Contacts: "Work authorization (US)", "Work authorization (Canada)", "Graduation date". Scope words (country, school, employer, term) come from the question text by rules first.
- A question whose scope differs from a stored answer's gets no fill, and the list says "No answer for Canada yet"; what the person types becomes a separate answer.
- History and last-confirmed dates live in per-device events until Phase 14.
- Built: `answers` entries carry `text` (the question as the page words it) and `options` (up to 10, 100 characters each; not stored yet, for 13.4). `AnswerScope` (`PrefillKit/Capture/AnswerScope.swift`) reads a country (authorization, sponsorship) or a term (those and GPA) from the text; the label becomes "Work authorization (US)". Matching scores a field on its label without the scope, then `ScopeFit` sorts each match: same scope (or both unscoped) fills; same kind but different scope is withheld and the entry says `noAnswerFor`; anything else (one side unscoped, or country against term) goes in the new `suggested` list, offered and never filled. Replacement, the once-a-day guard, Undo and `replaceAnswers` work on the scoped label, so they stay within one scope. Employer and school scopes were left out: the real forms name an employer only where the answer doesn't depend on it ("authorized to work for Braeburn"). A question that names two countries has no country scope. Per-device history waits for 13.3.

### 13.3 Memory kinds
- `Answer` gains `kind`: fact, contextual fact, preference, draft. Drafts allow line breaks and long text (lift the 200-character cap for drafts only, stored on the Prefill contact as before), are only ever suggested, never filled.
- The You tab shows the kind, scope, source and history on an answer's page. The inbox shows only exceptions: changed answers, guesses, answers to confirm before reuse.
- Built: `Answer.kind` comes from how an answer is stored: a draft custom field is `draft`, a label with a scope in brackets is `contextualFact` (with `scope`), everything else `fact`; `Memory.preferences` holds the demographic rule, shown read-only under Rules in the You tab. A draft (Add › Draft answer…) takes line breaks and up to 2,000 characters and is stored on Prefill's contact as a related name labelled `<Label> · Prefill draft`; older builds don't read that marker as Prefill's, so they skip the draft and keep it on rewrites (`DraftTests`). `customSuggestionsResult` carries `drafts` (why `draft`, caption "Draft · Cover letter") only for a one-field request; Fill form, the Mac's Fill form and picks never use them. An answer's page shows Kind, Applies to, Source and History (saves and replacements from this device's events). The inbox keeps waiting captures, answers a form changed (Keep, Change back, Edit) and the model's guesses (Use it records a pick; Not this caches none); saved captures, new learned answers and picks left it.

### 13.4 A model that sees the question
- The Mac panel and the iPhone app's background pass give the on-device model the question, nearby headings, a select's options, and the candidate answers with their scopes; it returns use-this / needs-a-new-answer / unsure. Only use-this shows as "Suggested", never filled.
- Cached guesses carry a revision of the answer store and are dropped when answers change.
- Built: `customSuggestions` fields may carry `heading` (the last heading before the field) and, from Fill form, `options`; the handler keeps both on the `FormQuestion`. `AnswerJudging` (`Intelligence/AnswerJudge.swift`) takes an `AnswerQuestion` and `AnswerCandidate`s (label with its scope, value; drafts left out) and returns `AnswerVerdict` use / needsNew / unsure; `checked` turns a label that isn't a candidate into unsure and a scope clash into needsNew. `Intelligence` implements it with FoundationModels; `AnswerGuessing.ask` (iPhone background pass) and `.suggestion` (Mac panel, live) drive it. The cache key holds `AnswerRevision.of` (FNV-1a over sorted labels and values), so verdicts made against other answers are ignored and the question is asked again. Tests use a fake judge (`AnswerJudgeTests`); the web side is checked on the Lever fixture (`question.test.ts`).

### 13.5 Fill, verify, ask
- After filling, read each field back and count only values that took; the pill reports the rest as "need you".
- When the person changes a filled answer and submits, the pill asks "Update everywhere" or "Just here" instead of replacing silently.
- Built: `fillForm` waits one turn after filling and reads every field back (`Filled.took`); only fields that kept the value count, the rest are undone, noted ("This one didn't take, check it") and returned by `fieldsLeft`. Fill form remembers the shown answer it put in a custom field (`filledAnswer`); `learn.ts` marks an answer `changedFill` when the person submitted something else. The app holds back a replacement for such an answer and replies `ask`; the pill offers "Update everywhere" (`action: update`, the existing replace path with its guards and Undo) and "Just here" (`action: keepHere`, an `AnswerOverride` event per site; no card write). A kept value is offered on that site only as a suggestion ("Used here"), never filled, because the page supplied it, and the same change there isn't asked about again. History on the answer's page shows it. After the security review: drafts come only with a `focused` request for a text area, keepHere needs `changedFill` and a learned answer, cached verdicts also key on the question's heading and options, drafts have their own limit of 5, a reformatted value still counts as taken, and Undo forgets what Fill form put in a field.

### 13.6 Accuracy you can measure
- `web/src/fixtures/heldout/`: real forms never used to tune rules, each with the expected answer per field. A script scores right / wrong / missing separately and the number goes in AGENTS.md. Add forms Tarun meets (Meta, Partiful's web form, Google booking forms, Dorm Room Fund).
- A short guide in `docs/` for watching 5 to 10 people apply with Prefill: time including review and correction, wrong vs missing answers, second-application reuse, setup without help.
- Built: 11 forms saved on Oct 7 in `web/src/fixtures/heldout/` (Greenhouse: Figma, Anthropic; Lever: Palantir; Ashby: OpenAI; Workable: Hugging Face; Meta; Jotform; Tally x2; Airtable: Dorm Room Fund; Luma), each with an expectations file for Alex Rivera (`alex.json`). `pnpm --dir web run score` (`heldout.test.ts`, `heldoutScore.ts`, `heldoutHost.ts`, `heldoutCombobox.ts`) runs Fill form with a stand-in app and counts right / wrong / missing / left; it fails only if a sensitive field is filled. First score, 140 fields: 64 right, 4 wrong, 14 missing, 58 correctly left. Wrong: a company-website question got Alex's own site (Dorm Room Fund); a phone box with `maxlength=10` got "+1 (510) 555-0134" (Jotform); Lever's "Name pronunciation" got "Alex Rivera"; Meta's single "Website (LinkedIn, GitHub, portfolio)" box got the combined "site - LinkedIn" text. Missing, with causes: hex ids with a digit before "cc" make a phone sensitive (`NOT_PHONE`'s `[^a-z]cc`, Tally; the first Airtable capture too); `name.*on.*card` matches any Lever question with "name", "on" and the `cards[...]` field name (Lever "Preferred name"); a question that starts with "If" is taken for a follow-up (Figma's "If you are currently enrolled..., expected graduation"); "May 2027" doesn't match "2027" or "May" (Lever year and month selects); Meta's radios have no `name`, so its demographic groups aren't declined; Workable asks for GitHub and LinkedIn in text areas, which aren't links; Ashby's Yes/No buttons and location box aren't filled. Not yet in the set: a Google Form (the public ones found needed sign-in or had closed) and a Google Calendar booking page. Guides: `docs/ACCURACY.md`, `docs/USER-STUDY.md`. Oct 7 (13.8): five of these forms moved to the regular fixtures after their bugs were fixed; replaced by Lever (Zoox), Workable (Blueground), Tally (HackHub), Airtable (IBM for Startups) and Meta (DFX intern). New score: 68 right, 9 wrong, 12 missing, 57 left of 146 fields; after the second round of 13.8, 74 / 3 / 12 / 83 of 172.

### 13.7 Docs
- README and PRODUCT.md lead with the browser extensions; the app manages and reviews; the Mac panel and the keyboard are manual fallbacks; no "every app" promise.
- Built: README and PRODUCT.md open with "Your verified information, ready for the next application." and who it's for (people applying to many jobs, fellowships, accelerators and events), then the extensions (Safari on the iPhone, Chrome and Arc on the Mac), the app for managing and reviewing, and the Mac panel and keyboard as fallbacks with their limits. There is no Safari extension for the Mac, so the docs say Safari on the Mac gets the panel for now. Still to change outside the docs: the Mac setting is labeled "Suggest in every app".

### 13.8 Fix rules the held-out score exposed
- Built (Oct 7, `fix/heldout-rules`): the five held-out forms that showed rule bugs moved to `web/src/fixtures/` (`scoredForms.test.ts`) and new real forms of the same kinds took their place. Fixed: "cc" counts as a card word only on its own or as a card token, so ids like `8019a3b2-28cc-...` no longer make a phone sensitive (`NOT_PHONE`, `SENSITIVE`); "name on card" needs the words together, so Lever's `cards[...]` names don't make a question sensitive; name pronunciation, phonetic and "how do you say" questions aren't the name; a company, startup or organization link is never the person's (`ORG_LINK`); a text area whose short label asks for a link is a link field (`classify.ts`, `links.ts`, the Mac panel); a box that lists examples ("Website (Examples: LinkedIn, GitHub, portfolio)") gets one link, website first, and `linkOptions` joins two links only when exactly two kinds are wanted; a saved "May 2027" picks "2027" or "May" from a year or month list when exactly one option fits (`choices.ts`). Left for `fill.ts`: `linkWant` still skips text areas, the phone `maxlength`, the "If..." follow-up rule and Meta's nameless radios. Score after the swap: 68 right, 9 wrong, 12 missing, 57 left of 146 fields.
- Second round (Oct 7, `fix/fill-answers`): seven forms moved to `web/src/fixtures/` with regression tests in `scoredForms.test.ts` (Figma, Jotform MY-HACK, Meta DFX, Workable Blueground, Lever Zoox, Airtable IBM, Tally HackHub). Fixed: only a question that refers to an earlier answer ("If yes...", "If you answered...") is a follow-up; a phone box with `maxlength` gets the number without "+1" or digits only, or nothing (`fillFit.ts`); radios without a name group by their radiogroup or fieldset; link text areas are filled; "E.U." and "EEA" are the EU scope (`AnswerScope`); words a question gives only as examples ("(e.g., grants, sponsorships)") don't match, and School fills only a question that names it early or asks which school (`CustomFieldMatcher`, mirrored in `heldoutHost.ts`); startup, company, team and project names aren't the person's (`patterns.ts`); inputs hidden from screen readers and out of the tab order aren't filled; a form's only address box gets the whole address on one line; a `type=tel` combobox is filled as a phone box. The scorer now reads a combobox it doesn't stand in for by its value, and ignores a list's own default. Old set after the fixes: 75 / 1 / 7 / 60. Replaced by Greenhouse (Datadog), Lever (Shield AI), Workable (Unified Patents), Jotform (AdaHack), Tally (SF Hacks), Airtable (Airtable for Startups), Meta (DCT intern): 72 right, 5 wrong, 13 missing, 91 left of 181 fields. Then Shield AI's race radios came back "Hispanic or Latino" (same on main): Lever puts a question's buttons inside its own label, so the click bubbled and checked the first button. Fill form now keeps only the button it chose (`clickOnly`), `declineOption` takes "No" only when the list also has a yes ("Yes", "I am", "I identify"), and the score fails the build when a demographic question gets anything but a decline or "No"; `scoredForms.test.ts` checks every fixture the same way. Shield AI moved to fixtures, replaced by Lever (Veeva): 68 right, 2 wrong, 12 missing, 80 left of 162 fields. Then Veeva's "require sponsorship for work authorization" got the work authorization answer and AdaHack's masked phone box got "+1". Fixed: a question with sponsorship words (sponsor, visa, H-1B) takes only the Sponsorship answer, one that asks whether the person is authorized or eligible to work takes only Work authorization, and one that asks both is left and not learned (`workQuestion.ts` for the stand-in and `learn.ts`, `WorkQuestion.swift` for `CustomFieldMatcher`); the score fails the build when the two cross. A box with "tel-national" or a "(000) 000-0000" mask gets the national number, or nothing for another country's number. Veeva and AdaHack moved to fixtures, replaced by Greenhouse (Roblox) and Jotform (Poco Run Club): 74 right, 3 wrong, 12 missing, 83 left of 172 fields. Still wrong: the run club's emergency contact name and phone get Alex's own, and its waiver's "Name of Participant" gets his name.

## Risks and what to do about them

| Risk | Where | What to do |
|---|---|---|
| Safari's own suggestion bubble covers the first row of Prefill's list | Phase 2 | Seen in the Phase 1 run. Task 2.5 moves the list clear of it; Phase 4 removes most of the cause. |
| Losing Safari's AutoFill Contact for emails and addresses | Phase 4 | That's the trade. Fill form covers whole forms; the gate makes Tarun decide. |
| The old Safari bar order and Prefill's list disagree during Phases 1 to 3 | Phase 1 | Accept for now. Phase 4 ends it. |
| Pins from a page are written by a content script | Phase 1 | Only after a trusted click or Enter in Prefill's closed shadow root, only for values already in memory, capped per minute. Run the `security-reviewer` agent on 1.1 to 1.3. |
| Resume model invents answers | Phase 7 | Verbatim-in-text check, review screen, unchecked "Already saved". |
| Moving values off the card on upgrade | Phase 4 | Only through the existing one-request move with read-back, after the person confirms the exact list. |
| SwiftLint and ESLint limits | All | Split files early; new files per feature (`MessageRouter+Picks.swift`, `why.ts`). |
| Per-device state doesn't sync, so picks on the Mac don't move the iPhone | Phase 1 | Fine for v2. If it matters, a later phase can carry pins on the Prefill contact (for example as labeled `urlAddresses` with a `prefill-pin:` scheme), which syncs. |

## Review rules

- Any task that changes what a page can send or receive (1.1 to 1.5, 2.1, 2.3, 4.1, 4.4): run the `security-reviewer` agent before merging the phase.
- Any change to `.tsx`/web UI or SwiftUI screens: run the `code-review` skill once per phase, not per task.
- A review that finds nothing gets one line in the merge commit's PR notes, nothing more.
