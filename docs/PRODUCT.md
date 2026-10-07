# Prefill: requests, product and build log

This document has three parts:
1. What Tarun asked for, in order.
2. What the product is now.
3. How it was built, so later sessions and agents can extend it.

## 1. What was asked for

| When | Request | Outcome |
|---|---|---|
| Oct 1 | "Make a better autofill." Safari's iPhone contact suggestions are bad and don't keep multiple emails. Research the common problems first, then build. | `research/REPORT.md`: problem survey, simulator findings and spikes |
| Oct 1 | Make it "as Apple as possible", ideally replacing the built-in suggestions rather than adding a new bar. | Prefill steers Safari's own bar by rewriting the contact card. There's no new bar. |
| Oct 1 | Polished build, SF Symbols, public GitHub repo. Free Apple ID, but build an App Store version too. | Personal and AppStore build configurations, picked at runtime |
| Oct 2 | Keep testing lean: "no need to do an excessive amount of tests." | Standing rule: a few unit tests plus one real end-to-end check per feature |
| Oct 2 | Install on the iPhone 17 Pro. Fix the Settings screen wrongly showing All Websites as not allowed. | Installed. Status now comes from the extension having seen a page. |
| Oct 2 | Job forms: fill "GitHub/Portfolio" with GitHub, website, or both as `github - website`, and "LinkedIn" with the LinkedIn link. | Links feature |
| Oct 2 | New app icon. | Four new directions; the user picked "Lifted Row" |
| Oct 2 | A Mac version that works in Arc and Chrome, synced with the phone. | Chromium extension plus Mac menu bar app plus native host; sync through iCloud Contacts |
| Oct 2 | Explain why a "key" was flagged in the repo. | It's the extension's public key, committed on purpose |
| Oct 3 | Passwords weren't offered for saving (on Chase). | Not caused by Prefill, since the Chase app had the same problem. Prefill now stays off sign-in forms anyway. |
| Oct 3 | Save the GitHub, website and LinkedIn links. | Added to the card, and later moved to the Prefill contact |
| Oct 3 | Save any field and value with no contact equivalent, like School = "University of California, Berkeley". | Custom fields with optional match words |
| Oct 3 | The extension did nothing on the Pear Airtable form. | Fixed: Prefill now runs in tabs that were open before the extension loaded, and Chromium uses its own dropdown, which works on textareas |
| Oct 3 | Sharing my contact must send only name and number, not all this info. A clone contact is fine. | Proved Safari's card and the shared card are one and the same. Built the Prefill contact plus minimal mode. |
| Oct 3 | Don't count on the $99 developer account. | No CloudKit and no App Groups; everything syncs through iCloud Contacts |
| Oct 3 | Why can't the extension read Contacts? Make it an app then. | Mac Accessibility engine that suggests in any app; the extension is now optional |
| Oct 3 | Finish everything, then write docs for future sessions. | This document, `README.md` and `AGENTS.md` |
| Oct 4 | "Not seamless enough, like AirDrop." Only name and phone may go out when sharing by tapping phones. Research how Apple does it and what other job-application fillers do. | Verified NameDrop sends only the name, one chosen number or email, and the poster. Web audit fixes. Research on Apple's patterns and on Simplify, Jobright and others. |
| Oct 5 | One-tap fill is fine, but tapping a field must still let me pick another value. Demographic questions: always decline or "No". | One-tap fill: a pill beside the field and a Fill button in Safari's sheet fill the whole form, including selects and yes/no radios, decline demographics, tint what they filled, undo in one tap, and a filled field still lists the other values. |
| Oct 6 | Look at Prefill like a YC startup: how clean it is to use and how it's layered, and whether there's a smarter way. Then: clicking a field and picking a value stays the default, with Fill form as an option. | The v2 plan in `docs/PLAN.md`. Done so far: picks are remembered per site and per question (Phase 1), every row says why it's there and Fill form says what's left (Phase 2), one read model for every answer with where it was used (Phase 3), and the app became Inbox, You and Settings (Phase 5). Phase 6 removed Siri, Shortcuts, the Focus filter, the Sites screen and the match-words field. Found and fixed on the way: Safari's own suggestion bubble swallowed taps on the first rows of Prefill's list on the iPhone. |

## 2. The product

**The problem:** Safari on iPhone suggests contact info from one card. It shows the first two values, never learns which email you use where, never saves a new email you type, and knows nothing about the questions job applications ask.

**The idea:** Click a field, pick a value. Prefill shows its own list under (or over) every field it recognizes, with the best answer first and a line saying why it's there, and it remembers what you pick. Fill form, which fills a whole application at once, stays one tap away but is never the default.

Underneath, Prefill still manages your contact card, because Safari's own bar and NameDrop read it:
- it adds the values you type;
- it reorders them per site, so Safari's bar agrees with Prefill's list (Phase 4 of the plan would freeze the card to name and phone instead; not started);
- it keeps links, custom answers and, in minimal mode, emails and addresses on a separate Prefill contact.

### What a person gets

**In Safari on the iPhone, and in Chrome and Arc on the Mac:**
- Prefill's list on each recognized field. Each row says why it's there: "Used here", "From greenhouse.io", "Suggested" (the on-device model's guess), or what it is ("Work email", "School").
- A value you pick comes first on that site from then on. An answer you pick, including a guess, comes first for that question on every site.
- New values are saved when you submit a form; answers to job application questions are learned the same way, and a newer answer updates one Prefill learned, with Undo.
- Fill form fills every empty field it has an answer for, declines demographic questions, and then says how many still need you and jumps to them.
- On contact fields in Safari the list sits above the field, because Safari's own suggestion bubble takes every tap in a band under it.

**The iPhone app:**
- **Setup:** two steps. Choose your contact card and see what's on it (with the optional offer to keep it to name and phone), then turn on the Safari extension, with checks that turn green on their own. It ends on "Tap any field in Safari and pick a value."
- **Inbox:** what needs a decision first (values Prefill wasn't sure are yours), then what Prefill did recently, each with a mark you can read at a glance.
- **You:** everything Prefill knows, searchable, grouped into Contact, Links and Answers. A value's page shows where it's stored, which sites it was used on, and which sites it's first on.
- **Settings:** the two switches, Sharing your card, the Apple Intelligence status, Safari's switches, and Advanced (sites Prefill doesn't save on, card, restore, delete).

**Mac:**
- A menu bar app that opens on the same inbox and suggests in any app through Accessibility. Until setup is done, the menu starts with a checklist (Contacts, Accessibility, the browser extension) whose items check themselves.
- An optional Chrome/Arc extension saves new values you type and shows Prefill's list when the Accessibility mode is off.

**Sharing your card:**
- **NameDrop** sends only your name, one number you pick, and your poster.
- **Minimal mode** keeps your own card to name and phone, so Share Contact sends only that. Everything else lives on the "Prefill · <Name>" contact.

### How the pieces connect

```
iPhone Safari page
  └─ Prefill Safari extension (web/src)
       ├─ Prefill's list under each field (dropdown.ts) ◄── suggestions with why, ranked per site
       ├─ picks ─────────────► remembered per site / per question (no card write)
       ├─ reorders the Me card per site ─────────────► Safari's own bar
       └─ saves typed values and learned answers ─► Extension handler ─► PrefillKit ─► Contacts (iCloud)

Mac, any app
  └─ Prefill.app Accessibility engine ─► panel under the field ─► types the value in

Mac, Chrome/Arc (optional)
  └─ Prefill extension ─► prefill-host ─► Unix socket ─► Prefill.app ─► Contacts (iCloud)

iCloud Contacts
  ├─ Me card: name, phone (plus emails and addresses unless minimal)
  └─ "Prefill · <Name>": links, custom fields (plus everything else in minimal mode)

PrefillKit Memory: one read-only view of every answer, where it's stored and where it was used,
for the app's Inbox and You screens.
```

## 3. How it was built

### Process

1. **Research (Oct 1):**
   - Parallel research agents surveyed AutoFill complaints, Apple docs and WebKit source.
   - Simulator spikes then tested each assumption: bar slot order, card rewrites, whether a datalist reaches the bar, whether Safari offers to save, and a text-insert provider.
   - Results are in `research/REPORT.md`, under "Spike results" and the appendices.
2. **Plan:** `.claude/plans/prefill-v1.plan.md` set out the phases: core, extension, app, intelligence, device and App Store prep.
3. **Build:** phases ran as parallel agents in separate git worktrees, each merged into `main` with `--no-ff`.
4. **Security review** after the core: `.claude/reviews/security-core-2026-10-01.md`. Its critical finding was fixed: a page could trigger saves.
5. **Iterate from use:** after the iPhone install, each request in part 1 became one focused agent with:
   - its own worktree;
   - lean tests;
   - one real end-to-end check (simulator, Chrome for Testing, or the real Airtable form);
   - a security review whenever the change touched what a page could see;
   - merge, push, and reinstall on the Mac and phone.

### Decisions worth knowing

- **Card rewrite instead of a custom keyboard or bar.** It's the only way to stay in Apple's own bar.
- **Prefill's own list everywhere, not a datalist.** Safari's bar shows at most three values with no labels; Prefill's list shows every value with why it's there. The datalist path is no longer used.
- **Picks are remembered without writing the card.** A pick goes into per-device events; the card only changes when the person adds, edits or confirms something.
- **The list sits clear of Safari's bubble.** On contact fields Safari swallows taps in a band about 100 pt under the field, so there Prefill's list goes above the field.
- **iCloud Contacts as the sync layer.** It's free, needs no server, and works with the free Apple ID.
- **A separate Prefill contact** keeps the shared card short. Safari's card and the shared card can't be separated (spike in REPORT.md).
- **Chromium's own dropdown instead of a datalist.** Airtable-style forms use textareas, and a datalist leaves values in the page.
- **Accessibility on the Mac.** It works in every app with no extension, and uses the same TypeScript field rules run in JavaScriptCore, so the Mac and the extensions can't disagree.

### How to add a feature

1. Read `AGENTS.md`, `docs/messages.md` and the closest existing feature. Links (`web/src/links.ts` plus its Swift messages) is the usual template.
2. If a page needs a new kind of value, add a validated message in both contracts (TypeScript `messages.ts` and Swift `Messages/`), plus `docs/messages.md` and `docs/message-examples.json`.
3. Store new personal data on the Prefill contact through `CNContactStoreGateway`, so it syncs and stays off the shared card.
4. Put field detection in `web/src/classify.ts`, so Safari, Chrome and the Mac app all get it.
5. Write a few unit tests and one real check, then run the full check list in `AGENTS.md`, merge, push, and reinstall (`install-mac.sh` and `install-device.sh`).
