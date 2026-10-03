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

## 2. The product

**The problem:** Safari on iPhone suggests contact info from one card. It shows the first two values, never learns which email you use where, and never saves a new email you type.

**The idea:** Apple doesn't let apps add to Safari's suggestion bar, but the bar reads the contact card. So Prefill manages the card:
- it adds the values you type;
- it reorders them per site, so Safari's own bar puts the right one first;
- it fills anything Safari can't do on its own (links, custom answers and, in minimal mode, emails and addresses) by offering suggestions the page passes on to the bar.

### What a person gets

**iPhone:**
- Safari's bar shows the right email, phone or address for each site.
- New values are saved when you submit a form.
- GitHub/Portfolio and LinkedIn fields get your links.
- Questions like "University" get your saved answer.
- The app lets you:
  - edit everything (Emails, Phones, Addresses, Links and Custom tabs);
  - pin a value for a site;
  - review recently added values;
  - restore your original card.
- Siri can read a value, and a Focus filter can switch Prefill off.

**Mac:**
- A menu bar app suggests in any app through a native-looking popup under the field.
- An optional Chrome/Arc extension saves new values you type and shows its own dropdown when the Accessibility mode is off.

**Sharing your card:**
- **NameDrop** sends only your name, one number you pick, and your poster.
- **Minimal mode** keeps your own card to name and phone, so Share Contact sends only that. Everything else lives on the "Prefill · Tarun Yadgirkar" contact.

### How the pieces connect

```
iPhone Safari page
  └─ Prefill Safari extension (web/src)
       ├─ reorders the Me card per site  ───────────►  Safari's own bar
       ├─ links / custom / minimal-mode values as a page datalist ─► Safari's own bar
       └─ saves typed values ─► Extension handler ─► PrefillKit ─► Contacts (iCloud)

Mac, any app
  └─ Prefill.app Accessibility engine ─► popup under the field ─► types the value in

Mac, Chrome/Arc (optional)
  └─ Prefill extension ─► prefill-host ─► Unix socket ─► Prefill.app ─► Contacts (iCloud)

iCloud Contacts
  ├─ Me card: name, phone (plus emails and addresses unless minimal)
  └─ "Prefill · <Name>": links, custom fields (plus everything else in minimal mode)
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
- **Datalist only where Safari has nothing.** Safari's own suggestions always win, so Prefill fills the gaps.
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
