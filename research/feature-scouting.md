# Feature scouting for v1

Scouted 2026-10-01 by four parallel agents (on-device intelligence, Safari popup, system integrations, app icon) and ranked by a product-lead agent. The person chose icon direction A.

Prefill v1 focuses on finishing a few things inside Safari and Siri rather than starting many. The ranking weighs three things: fixing the real problem (Safari forgetting emails and offering the wrong one), feeling like part of iOS, and build cost.

**Build in v1 (14 picks, 4 of them folded into others):**
- **Safari popup.** A half-sheet holding the "Safari will suggest here" bar replica, tap to use a value on this site, and recent saves with Undo plus "Don't save on this site". The "pin from Safari" pick is the same popup feature, so it's merged in.
- **Page-menu badge.** Shown only when a captured value is held back for review.
- **Smart ordering.** A small intelligence layer in PrefillKit runs only in the app. It drives automatic labels (rules first, model for ties, no custom "Shopping" label) and a trimmed version of site sense (rules plus cache in the Safari handler, model batch in the app, a new Ranker step).
- **Capture notes.** Template-only "is this yours" sentences.
- **System surfaces.** A Siri and Shortcuts question ("Which email do I use on Netflix?") that answers with an interactive bar snippet, and a Work Focus filter that puts work values first.
- **Ground rules.** Intents live in the app target with allowedExecutionTargets = .main, and there are no new extension targets.

**Later:**
- Auto-opening save sheet
- Per-site icon state
- Address tidying
- Paste from text
- Siri pin and Siri add
- Spotlight
- Control Center toggle
- Visual Intelligence

**Skip:** icon directions B and C.

**Corrections to the scouted designs:**
- Undo can't be keyed on the CNLabeledValue identifier, because CardWriter writes every value fresh and renumbers identifiers on each save. Key undo on the ContactValue UUID and normalized key, and only for values Prefill captured.
- The Safari handler should not call the model in v1, because the background rate limit and cold-start cost are unknown.
- Intents should go in the app target, not an AppIntentsPackage in PrefillKit, which avoids an untested metadata-extraction step for SwiftPM libraries.

**Sequencing:** these become a new Phase 4a, after the phase-2 (extension) and phase-3 (app UI) worktrees merge. The popup touches web/, Extension/ and the Messages/Ranker code in PrefillKit, and the snippet needs the bar replica moved out of App/. That lets this work start without touching the two worktrees in progress.

**What's verified and what isn't:**
- Read directly in the iOS 27 SDK interfaces: prewarm(promptPrefix:), GenerationGuide.anyOf, the modelNotReady and rateLimited cases, SnippetIntent, UndoableIntent, IndexedEntity and allowedExecutionTargets. The scouts' intent probe (typecheck only) and the spike results also back the design.
- Inferred and not run: the popup detents, where the badge draws, openPopup, the App Intents metadata processor, signing with the free team, and every runtime behavior of Siri, Focus and snippets. Each in-Safari item lists the single simulator check it needs.

No project files were changed and nothing was committed. Files read:
- /Users/tarunyadgirkar/TarunsCode/prefill/.claude/plans/prefill-v1.plan.md
- /Users/tarunyadgirkar/TarunsCode/prefill/research/REPORT.md
- /Users/tarunyadgirkar/TarunsCode/prefill/Packages/PrefillKit/Sources/PrefillKit/Model/Documents.swift
- /Users/tarunyadgirkar/TarunsCode/prefill/Extension/Resources/manifest.json
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-*.png

## Icon

Recommendation: go with direction A, Slot. I read all three on the contact sheet and as 1024 px renders. A is the only one where someone who has used AutoFill sees \"the keyboard picked this for me\". It also matches the bar replica that shows up in the app, the Safari popup and the Siri snippet, so the icon and the product use one picture. B looks like a Reminders or to-do icon and shrinks to a single orange bar. C looks like a flag on a pole before it reads as a P.

Refinements for design/icon/a-slot.icon:
1. Make light and dark actually different. The current light rendition is already dark teal, so the two look the same. Light should be a Frost #EEF4F3 to pale-teal background with a Harbor #14505A bar. Dark keeps the Harbor to Night harbor gradient.
2. Simplify the keycap row. Right now five full keys make a busy band at 60 px and compete with the chip. Either crop one row of shorter keys at the bottom edge so it reads as the top of a keyboard, or drop the keys and move the bar down. Check both at 60 px.
3. Make the chip read as lifted, not as a toggle. Give the marigold slot a slightly stronger drop shadow and a 2 to 4 pt offset above the bar. Add space between the chip and the hairline divider so the left end doesn't look like a switch knob.
4. Make the text marks bigger. The label and value lines in both slots are thin. Thicken them and give the value line more contrast so the label-over-value structure still shows on the home screen.
5. Render the Tinted and Clear versions with ictool (--rendition TintedDark and ClearLight). In those modes the marigold has to stand out through glass depth and lift, not through hue.
6. Carry the palette into the app: Harbor for the tint and Marigold only as the slot-one glow and small marks in the replicas, never as a button fill.

## Picks

### Build in v1

#### Prefill popup as a native half-sheet on iPhone

When someone taps Prefill in Safari's page menu, a system sheet rises to half height with a grabber and can be pulled up to full height. On iPad the same page opens as a popover anchored to the menu. The sheet chrome (Liquid Glass sheet, navigation bar) is Safari's own, so if the HTML inside uses system type and colors it reads as part of Safari, not as a web page.

Why: This is the cheapest way to put Prefill inside Safari's own chrome. Safari supplies the system sheet, the grabber and the medium/large detents, so the popup reads as part of iOS. The only manifest change is adding default_popup. Every in-Safari feature below lives here, so it has to come first.

Build notes: Do this as a new Phase 4a in the plan, after the phase-2 worktree merges. Don't touch web/ or Extension/ until then. Add "action": {"default_popup": "popup.html", "default_icon": ...} to Extension/Resources/manifest.json, which today has no action key. Add web/src/popup.ts and popup.html/css, built by the existing esbuild into Extension/Resources. CSS: font -apple-system-body plus the other -apple-system text styles for Dynamic Type, color-scheme: light dark, tokens on :root, inset-grouped list styling, env(safe-area-inset-bottom), and an explicit root width of about 375px for the iPad popover (WebKit caps it at 800x600). Design for the medium detent first. Liquid Glass can't be drawn inside the WKWebView, so leave glass to Safari's chrome and don't fake it with backdrop-filter. Run one simulator check and screenshot it to assets/generated/: does iOS 27 Safari add its own title or Done button? Status: the symbols are verified in the iOS 27 sim binary. The detent and nav-controller behavior is inferred from WebKit source.

Evidence:
- Verified (binary, iOS 27.0 sim dyld cache 24A434): Safari implements -[SFWebExtensionsController webExtensionController:presentPopupForAction:forExtensionContext:completionHandler:] and -[SFWebExtensionPageMenuController showPopupOrPerSitePermissionsForTab:parentViewController:popoverSourceInfo:], and WebKit ships _WKWebExtensionActionViewController with adaptivePresentationStyleForPresentationController:traitCollection:, _updateDetentForSheetPresentationController:, _updatePopoverContentSize. Strings dump: scratchpad/webext-action-strings.txt, scratchpad/safari-ext-strings.txt
- Inferred from WebKit main source (same class and method names as the shipping binary; constants not confirmed in the binary): WebExtensionActionCocoa.mm:415 compact width -> UIModalPresentationFormSheet, else popover; :428-436 sheet wrapped in UINavigationController; :462-478 on iPhone width forced to the device's portrait width; :493-501 detents = medium + large, prefersEdgeAttachedInCompactHeight; :66-74 popover max 800x600, min 50x50; :1016 viewport forced to width=device-width, scale 1, user-scalable=no. Saved copy: scratchpad/WKWebExtensionAction.mm (https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Extensions/Cocoa/WebExtensionActionCocoa.mm)
- Observed: the extension row already appears in the iOS 27 page menu even without an action key (assets/generated/spike-capture-grant-1-page-menu.png, grey icon before grant, colored after in spike-capture-grant-5-page-menu-after.png)
- spikes/datalist/Extension/Resources/manifest.json declares "action": {"default_icon": ...}, the only manifest change needed is default_popup
- MDN BCD webextensions/api/action.json: every action.* entry for safari_ios mirrors desktop Safari 15.4+ (action.setTitle is the exception: present but not visible on iOS)

Risks:
- The detent values and nav-controller wrapping come from WebKit open source. The shipping binary has the same symbols, but the exact iOS 27 Safari behavior (for example whether Safari adds its own Done button or title) is unverified until a simulator run with a default_popup
- No Liquid Glass or SwiftUI inside: the content is a WKWebView, so glass has to be imitated with backdrop-filter or skipped
- -apple-system-* color keywords may not all be exposed to extension pages. Fall back to plain light/dark tokens
- navigator.vibrate does not exist on iOS, so the popup cannot play haptics

#### "Safari will suggest here" bar replica inside the popup

The sheet opens on a replica of the QuickType bar for this site: the two emails (or phones, or addresses) Safari will offer in its first two slots, with Apple's lowercase labels, and every other value on the card listed under it. Only the kinds this page actually asks for get a tab, so a newsletter box shows emails only.

Why: It answers the user's actual complaint ("which email is Safari about to offer me here?") at the moment it matters, and it carries the app's bar-replica motif into Safari. The top two of the ranked list are exactly the bar's two slots, which the contacts spike observed directly.

Build notes: PrefillKit/Messages: add ExtensionRequest.popupState(host, kinds) and a response {kind: {slots, rest, pinnedID?, siteKind?, recentCaptures}}. Fold the site-history data into this one reply so a cold open costs one 1.3 s round trip, not two. Route it in MessageRouter through Ranker plus a ContactsGateway read only, with no write. Popup flow: tabs.query({active, currentWindow}), then tabs.sendMessage(tabId, {type:'pageNeeds'}) so content.js returns the kinds it classified, then runtime.sendNativeMessage. Only show a kind tab when the page asks for that kind. Paint the last reply for the host from browser.storage.local right away, swap in the live reply when it lands, and clear that cache on Restore. Match the app's SwiftUI replica geometry: two slots, label over value, lowercase system labels, marigold glow on slot one as a mark rather than a fill. If tab.url is unavailable (an activeTab question nobody has verified on iOS), drop the site name and keep the list. If Contacts isn't granted, show an "Open Prefill" state and never call requestAccess.

Evidence:
- Doc (verified, developer.apple.com messaging-between-the-app-and-javascript-in-a-safari-web-extension): native messages can be sent "from a background script or from extension pages that provide a user interface". Content scripts cannot. The popup counts as an extension page
- SDK: SFExtensionMessageKey API_AVAILABLE(ios(15.0)), SFExtensionProfileKey ios(17.0), in SFSafariApplication.h
- MDN BCD runtime.json: runtime.sendNativeMessage safari_ios 15
- Observed in the capture spike: the handler inherits the app's Contacts grant and can read and save the card. Cold handler about 1.3 s, warm about 10 ms (research/REPORT.md Spike results)
- Observed in the contacts spike: slot 1 is identifier 0, slot 2 is the first other value, so the ranked list's top two are exactly what the bar shows
- spikes/capture/Extension/SafariWebExtensionHandler.swift shows the message-routing pattern to extend with new message types

Risks:
- Cold handler latency means a first open can show cached or skeleton state for about a second
- Reading tab.url needs host permission for the site (onboarding asks for all sites) or activeTab, which is unverified on iOS. If neither is present, show the per-kind list without a site name
- The popup holds PII (the person's emails, phones, addresses) in extension storage. Cache only what is needed and clear it on Restore/Reset
- The handler must never call requestAccess (spike finding). If Contacts is not granted, the popup shows an Open Prefill state instead

#### Tap to use a value on this site (pin plus instant card rewrite)

Tap any value in the list and it slides into slot 1 of the replica, and Prefill rewrites the card right away. The next time the person taps the email field, Safari's own bar shows that value first. A small pin mark shows the site is locked to that choice, and tapping it again unpins.

Why: This is the direct fix for "offers the wrong one". One tap in Safari, and the next focus on that field shows the chosen value in slot 1. The rewrite path is proven: the handler saved a reordered card in the capture spike, and Safari picked up the edit on the next focus.

Build notes: ExtensionEvents gains pinEvents: [PinEvent(host, kind, valueID?, at)] (a nil valueID means unpin). This keeps the single-writer split: the extension appends and the app folds events into AppState.pins on launch. Ranker.Signals merges AppState.pins with pinEvents, and the newest wins. New messages pin and unpin run Ranker, then CardWriter for the host, and reply with the new slots. Animate the slot swap with the View Transitions API or FLIP and show a check mark. Try window.close() after the reply, and if it does nothing let the person swipe the sheet down. Tell the person to re-tap the field, because programmatic focus won't raise the keyboard (inferred). Add Swift Testing cases for the pin-event merge in Ranker. That's the only new test this needs.

Evidence:
- Observed (contacts spike): a rewrite of fresh CNLabeledValues in ranked order in one CNSaveRequest renumbers identifiers 0..n, and Safari shows the new order on the next field focus with no relaunch (research/REPORT.md Spike results)
- Observed (capture spike): the extension handler, not only the app, saved a reordered card using the inherited Contacts grant
- Doc: popup -> sendNativeMessage -> SafariWebExtensionHandler.beginRequest is the supported path (developer.apple.com messaging doc)
- Plan: SitePin(host, kind, valueID) and CardWriter's skip-when-unchanged already exist in .claude/plans/prefill-v1.plan.md Data model
- Inferred, not tested: the field the person was on loses focus when the page menu opens. Programmatic focus() from the content script without a user gesture will not raise the keyboard on iOS, so the person re-taps the field

Risks:
- Each pin rewrites the real card and syncs to iCloud, so the order on the Mac changes too. Already a plan risk, mitigated by skip-when-unchanged
- A pin written while the card is mid-edit elsewhere can lose that edit. Refetch-merge right before save, as the plan says
- The pin storage path conflicts with the plan's one-writer-per-item rule unless pins go through ext-events as described
- window.close() from an iOS popup is unverified. If it does nothing, the person swipes the sheet down

#### Pin a value for the current site from Safari (extension popup, share sheet, Shortcut)

On any page the person opens Safari's page menu, taps Prefill, and sees "On example.com Safari will offer" with the bar replica and the full list. Tapping a value pins it there. People who reach for the share sheet get the same picker.

Why: Route A is the same feature as the popup pin above. Build it once, there. Route B (an Action extension) burns a free-team profile slot and has an untested Contacts grant. Route C falls out of PinValueIntent for free when that ships later.

Build notes: Merge into "Tap to use a value on this site": Route A only. Don't create an Action extension target in v1. Revisit Route B in Phase 6 only if App Review or users ask for the share sheet.

Evidence:
- No App Intents API places an intent directly in the share sheet: searched AppIntents.swiftinterface for share-sheet symbols and found none
- Foundation.framework/Headers/NSItemProvider.h:361 NSExtensionJavaScriptPreprocessingResultsKey (Action extension gets the page URL through JS preprocessing)
- Extension/Resources/manifest.json: MV3, <all_urls> content script, nativeMessaging, no action/popup yet
- Packages/PrefillKit/Sources/PrefillKit/Model/Documents.swift: app-state is app-only, ext-events is extension-only (single writer)

Risks:
- Route A edits Extension/ and web/, which other agents own right now. It is a proposal for after their merge.
- Inferred: iOS Safari shows MV3 action popups from the page menu. This is Doc-level knowledge and was not exercised here.
- Route B costs one more profile slot (see the free-team limit under the control). Unverified whether an Action extension inherits the Contacts grant.
- Route C depends on the person installing a shortcut, so it is a fallback rather than the main path.

#### Recent saves with Undo and "Don't save on this site"

Below the bar replica, the popup lists what Prefill saved from this site, each with Undo, plus a single switch to stop capturing on this site. Mistakes like a gift address or a friend's email get fixed in the moment, inside Safari, without opening the app.

Why: Capture is the half that fixes "Safari forgets my emails", and silent capture only feels safe if a mistake can be undone right where it happened. It's small and reuses the popup reply.

Build notes: Show it below the replica in the popup, using recentCaptures from the popupState reply. Correction to the scout's design: you can't key undo on the CNLabeledValue identifier. CardWriter rewrites every value as a fresh CNLabeledValue, so identifiers renumber 0..n on every save. Key undo on the ContactValue UUID and normalized key instead, and only allow it when source == .captured and the Capture verdict is saved. New messages: undoCapture(captureID), which appends a dismissed event and runs CardWriter (the app later folds it into rejectedValueIDs), and muteSite(host, on), which appends to ExtensionEvents and is checked by CaptureFilter. Make "Don't save on this site" a real switch row. Make "Open Prefill" a tabs.create({url:'prefill://sites/<host>'}) footer link. That custom-scheme open is unverified: if it fails, remove the link rather than shipping a dead control.

Evidence:
- Doc: popup can sendNativeMessage (developer.apple.com messaging doc)
- Observed: handler can save the card using the inherited Contacts grant (capture spike)
- Plan: Capture verdicts (saved, needs review, dismissed, duplicate) and 'Never drop a value that is on the card' rule in .claude/plans/prefill-v1.plan.md

Risks:
- Undo must never remove a value that was already on the card before Prefill added it. Key the undo on the identifier Prefill wrote
- Site mute written by the extension has to be folded into app-state by the app to respect the single-writer rule
- Custom-scheme open from an extension page may show Safari's 'Open in Prefill?' confirmation, or may not work. Unverified

#### Badge on Prefill's page-menu row for new saves and values to review

When Prefill saves a new email from a form, or holds one back as "is this yours?", its row in Safari's page menu carries a small badge. Safari also appears to mark the page-menu button itself until the person opens the menu. That gives a quiet, Apple-style "something happened here" with no in-page banner.

Why: It's the quiet, Apple-style "something happened" signal for captures held back for review, and it replaces any in-page banner. It costs a few lines, and setBadgeText is supported on Safari iOS per MDN BCD.

Build notes: background.ts: on a capture reply with review > 0, call browser.action.setBadgeText({tabId, text: String(count)}). Clear it with setBadgeText({tabId, text: ''}) when the popup handles the item. Rebuild the count from the handler reply each time, because the background script isn't persistent on iOS. Don't set a badge for auto-saved captures, since Undo in the popup already covers those and fewer badges keeps it quiet. Don't rely on color, which Safari ignores. Status: Safari's badge symbols are verified in the binary. Where the badge actually draws on iPhone is inferred, so take one simulator screenshot before designing copy around it.

Evidence:
- MDN BCD action.json: action.setBadgeText Safari 15.4, safari_ios mirrors; setBadgeText(null) and windowId param Safari 18; setBadgeBackgroundColor 'API exists, but has no effect'; setBadgeTextColor not supported
- Binary (iOS 27.0 sim): +[SFWebExtensionPageMenuController badgeViewForText:], -[WBSWebExtensionToolbarItem badgeTextForTab:], -[WBSWebExtensionToolbarItem hasUpdatedBadgeTextInTab:], -[WBSWebExtensionToolbarItem didViewBadgeInTab:], -[SFWebExtensionsController hasUpdatedToolbarItemBadgeTextInTab:], -[SFWebExtensionsController didViewToolbarItemBadgesInTab:], _SFPageFormatMenuBadgeView initWithText:/setBadgeText:, -[WKWebExtensionAction hasUnreadBadgeText]/setHasUnreadBadgeText:
- WebKit source WebExtensionActionCocoa.mm:1232-1243: setBadgeText sets hasUnreadBadgeText = !text.isEmpty(); :1095 opening the popup clears the unread flag
- Inferred, not observed: the badge renders on the extension's page-menu row and an unread indicator shows on the page-menu button in the address bar. Exact iOS 27 rendering needs a simulator screenshot

Risks:
- Where and how the badge draws on iPhone is inferred from symbols, not seen. Run one simulator check before designing around it
- Background is non-persistent on iOS, so a global count must be rebuilt from the handler's queue, not kept in memory
- Badge text fits only about 4 characters

#### Intelligence layer in PrefillKit (availability, prewarm, caching, fallback ladder)

Every smart feature below goes through one small actor, so Prefill behaves the same with Apple Intelligence on, off, still downloading, or on an older iPhone. With the model available, labels and explanations appear on their own. Without it, the same screens fill in from deterministic rules and nothing looks broken or empty.

Why: It's a small actor that lets automatic labels and site sense degrade cleanly on devices without Apple Intelligence. Build only the methods v1 uses (labelValue, siteKind). The others come later.

Build notes: Packages/PrefillKit/Sources/PrefillKit/Intelligence/Intelligence.swift, wrapped in #if canImport(FoundationModels). Package.swift also targets macOS 26, so swift test exercises the rules path. The API returns (result, source: .model | .rules). Use a fresh single-turn session per call with GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 40). Catch LanguageModelError and fall through to the rules. Prewarm from the app when Recently added or Sites appears. v1 calls the model from the app only, never from the Safari handler, because the background rate limit and cold-start latency are unknowns. Cache results in AppState (app-written) keyed by task, input and model variant. Settings shows one plain line for the modelNotReady and appleIntelligenceNotEnabled states, and nothing when the device isn't eligible. Never use PrivateCloudComputeLanguageModel. Never log prompts. Verified: prewarm(promptPrefix:) at swiftinterface :1961, anyOf at :1425, modelNotReady at :368 and rateLimited at :1529 all appear in the iOS 27 SDK.

Evidence:
- SDK swiftinterface :366-368 UnavailableReason deviceNotEligible / appleIntelligenceNotEnabled / modelNotReady
- SDK swiftinterface :389 SystemLanguageModel.init(useCase:guardrails:)
- SDK swiftinterface :1961 LanguageModelSession.prewarm(promptPrefix:)
- SDK swiftinterface :1529-1536 LanguageModelError.rateLimited / guardrailViolation / timeout (iOS 27)
- SDK swiftinterface :445 contextSize, :470 variant, :495/:501 Variant.core3 / coreAdvanced3 (iOS 27)
- SDK swiftdoc: rateLimited 'will only happen if your app is running in the background and exceeds the system defined rate limit'; 'If running in the background, use the non-streaming respond'
- Verified: grep finds 0 occurrences of ApplicationExtension / NS_EXTENSION_UNAVAILABLE in FoundationModels arm64e-apple-ios.swiftinterface, so nothing in the interface marks it extension-unavailable
- Observed on this Mac (macOS 27.0 26A428): availability .available, variant 'AFM 3 Core Advanced', contextSize 8192; inference runs out of process in TGOnDeviceInferenceProviderService (about 110 MB RSS), not in the client
- Probes: /private/tmp/claude-502/-Users-tarunyadgirkar/17d1533c-d1e2-486a-873f-dba3b0de6a41/scratchpad/fm/probe*.swift

Risks:
- Whether the Safari extension handler counts as 'background' for rate limiting is inferred, not tested; keep model calls in the handler rare and cached, and do bulk work in the app
- Observed numbers come from an M5 Pro Mac running the Core Advanced variant; iPhone may run the smaller core3 variant and be slower (inferred)
- Whether the iOS 27 Simulator answers model requests through the host Mac is not verified here; the rules path must be the tested default
- Guardrails can reject harmless prompts (see the ranking feature), so every call needs the rules fallback, not just availability checks

#### Automatic labels for newly captured values

When Prefill picks up a new email from a form, it already shows up in Recently added labeled School, Work, Personal or Shopping, so saving is one tap instead of a label picker. The label lands on the contact card as a real Contacts label, so it reads correctly in Contacts and in Safari's AutoFill sheet.

Why: A captured email that lands on the card unlabeled shows in Safari's bar under the generic word "email". Labeling it school, work or home makes the native bar read correctly and turns review into one tap. The rules handle most cases, and the model only breaks ties.

Build notes: Run it in the app when draining captures, never in the handler. Run the rules first and skip the model when they're confident: .edu, .ac.* or a known school domain means school; a non-freemail domain, or one that matches the capture host, means work; freemail means home. Only ambiguous freemail captures go to Intelligence.labelValue, with @Generable ValueLabel { @Guide(.anyOf([work, school, personal, shopping, unknown])) context }. Map the result to CNLabelWork, CNLabelSchool (iOS 13, verified in CNLabeledValue.h) or CNLabelHome. Drop the custom "Shopping" label: it shows as a raw custom string in other clients and in Safari's bar, so map shopping to home. Recently added shows the suggestion as a preselected Menu chip, with the apple.intelligence symbol only when the model picked it. Corrections are stored, so the same domain isn't asked again.

Evidence:
- SDK swiftinterface :1425 GenerationGuide.anyOf([String]) constrains a @Generable String to a fixed set
- SDK Contacts CNLabeledValue.h:55-57 CNLabelHome, CNLabelWork, CNLabelSchool (iOS 13)
- Observed (probe.swift, @Generable ValueLabel with .anyOf, greedy): alex.rivera@berkeley.edu on calcentral.berkeley.edu -> school; arivera@acme-robotics.com on github.com -> work; alex.r.shops@gmail.com on target.com -> shopping; alexrivera99@gmail.com on instagram.com -> personal. Latency 1074 ms on the first call, then 570-612 ms (Mac, Core Advanced)
- Observed: the reason strings it writes are bland ('It is a work email address.') and add little

Risks:
- Shopping versus personal is a judgment call on freemail addresses; keep the label editable and learn from corrections
- Custom 'Shopping' label shows as plain text in other Contacts clients
- Values are sent to the on-device model only; never log prompts (PII rule in the plan)

#### Site sense for sites Prefill has never seen

Open a .edu course site for the first time and Safari already offers your school email first; open a developer portal and it offers your work email. Prefill works out what kind of site it is, so the card is right before the person has ever picked a value there.

Why: This fixes "offers the wrong one" on a first visit, before any pin or usage exists. The rules alone cover the common cases (.edu, .gov, a host that matches one of the person's email domains). Scope it down to keep the handler fast and model-free.

Build notes: Trimmed v1: SiteKind enum (work, school, personal, shopping, finance, government, unknown) in PrefillKit. The handler uses host rules plus the cache only, and never calls the model. The app classifies hosts in a foreground batch on launch and after draining captures, then writes AppState.siteKinds. Drop the scout's fire-and-forget model call from the handler. Ranker gets a new tier after hintRelated: siteKindLabel, meaning prefer a value whose label matches the kind. Pins, use on this host and explicit autocomplete hints still win. The Sites screen shows the kind and lets the person correct it, and a correction is stored as a pin. Use the guardrail-safe neutral instruction that passed the probe, freeze it, and treat guardrailViolation as unknown. One Ranker unit test covers the new tier ordering.

Evidence:
- Observed (probe2.swift, host only, @Generable SiteKind with .anyOf): canvas.instructure.com -> school, developer.apple.com -> work, bestbuy.com -> shopping, irs.gov -> government, bcourses.berkeley.edu -> school, chase.com -> finance, etsy.com -> shopping, workday.com -> work, linear.app -> unknown, news.ycombinator.com -> unknown. Warm latency 322-565 ms per host (Mac)
- Observed (probe3.swift): putting the person's emails in the prompt and asking for an index picked the work email for canvas.instructure.com, which is wrong; classifying the host alone got it right
- Observed: the instruction wording 'a website they are signing in to or filling a form on' was rejected by the input guardrail ('May contain unsafe content', about 120 ms) every time, even with Guardrails.permissiveContentTransformations (SDK :343); neutral wording passed
- Observed: SystemLanguageModel(useCase: .contentTagging) (SDK :283) returned free-form tags ('Canvas, LMS, bcourses, berkeley, course page') in 1561 ms, which does not map onto Prefill's categories
- Report 'Spike results': cold extension handler about 1.3 s, warm about 10 ms; the plan sends page context on load and again on focusin

Risks:
- First visit may still show the old order if the model answer arrives after the person taps the field; the rules path covers .edu and .gov, the most common case
- Prompt wording can trip guardrails unpredictably; keep a fixed, tested instruction and treat guardrailViolation as 'unknown'
- Ambiguous hosts (linear.app, news.ycombinator.com) come back unknown and fall through to the global order, which is the right behavior but means no magic there
- Each kind change can trigger a card rewrite and iCloud sync churn; the existing 'save only when the first two change' rule limits this

#### One-sentence 'is this yours' notes in Recently added

Each value waiting for review carries a short note like 'Typed in a Recipient address field on etsy.com, so it may be a gift' instead of a bare Save / Dismiss pair. Saved items say why they were saved automatically, which makes the Undo feel trustworthy.

Why: A plain reason under each held-back value ("Typed in a Recipient address field on etsy.com") is what makes auto-save and Undo trustworthy. Ship it as deterministic templates. The probe showed the model's verdicts miss obvious someone-else cases and its phrasing is stiff, so the model adds little here.

Build notes: CaptureFilter returns a CaptureReason enum (rule, host, field label) alongside its decision, stored on the Capture. Keep one localized template per rule in the String Catalog. Show it in Recently added rows and in the popup's recent saves. No model in v1. Revisit model polish only if the templates name odd field labels badly.

Evidence:
- Observed (probe4.swift, @Generable Verdict with owner .anyOf and a one-sentence guide, facts only): etsy gift recipient address -> 'unsure', 'On etsy.com, the recipient address was entered without a name.'; evite 'Invite guests' email -> 'unsure'; notion sign-up work email -> 'mine'; opentable reservation phone -> 'mine'. 808-1763 ms each (Mac)
- So the model's verdict misses obvious someone-else cases and must not decide; its phrasing is passable but stiff
- Plan 'CaptureFilter' already defines the deterministic rules (value already on card, sign-up or checkout form, recipient/friend/gift/invite/to field names)

Risks:
- The model can state a reason that is not in the facts; constrain it to the CaptureReason fields and fall back to the template on any mismatch
- Roughly 1 s per row; generate lazily for visible rows and cache

#### Siri and Shortcuts: "What's my shipping address?" and "Which email do I use on Netflix?"

Siri shows the value Prefill would offer, with its label, and asks the person to unlock first on the Lock Screen. "Which email do I use on Netflix?" answers the question people actually forget. In Shortcuts the result is plain text that other actions can use.

Why: "Which email did I sign up with?" is the forgetting problem stated as a question, and Siri answering it with Prefill's bar snippet is the most iOS-native thing on this list. It's cheap: it's read-only, needs no card write and no new target.

Build notes: Put intents in the app target (App/Intents/, after the phase-3 merge), not in an AppIntentsPackage in PrefillKit. That skips the open question of whether metadata extraction works from a SwiftPM library, and v1 has no widget to share them with. GetValueIntent(kind: ValueKindEnum, site: SiteEntity?, label: LabelEnum?) uses authenticationPolicy = .requiresAuthentication, supportedModes = .background and allowedExecutionTargets = .main (iOS 27, verified at AI:3112). It returns .result(value: String, dialog:, snippetIntent: BarPreviewSnippet). The dialog says "Here's the email you use on netflix.com" and doesn't speak the value aloud. SiteEntity.id is the registrable domain, and its EntityStringQuery searches hosts from usage and captures. Register an AppShortcutsProvider with phrases "Which \(\.$kind) do I use on \(\.$site) in \(.applicationName)" and "What's my \(\.$kind) in \(.applicationName)". Run one xcodebuild to get past appintentsmetadataprocessor, because the typecheck alone doesn't prove the build. Test it through the Shortcuts app, not Siri voice.

Evidence:
- AI:3167 IntentAuthenticationPolicy (.requiresAuthentication, .requiresLocalDeviceAuthentication)
- AI:5050 iOS 27 IntentSystemContext.isVoiceOnly and locale
- AI:4561-4568 .result(value:dialog:snippetIntent:)
- VERIFIED: systemContext.isVoiceOnly and authenticationPolicy typecheck against iOS 27 (Probe.swift)
- Packages/PrefillKit/Sources/PrefillKit/Ranking/Ranker.swift (RankingContext(host:hint:now:matchEachSite:))

Risks:
- Speaking an address or phone aloud is a privacy hazard. Default the dialog to "Here's your home address" and show the value on screen.
- Inferred from the property name: what isVoiceOnly means. Its semantics are not documented in the interface.
- Inferred: writing to UIPasteboard from a background-mode intent may be restricted or may prompt. Fall back to opening the app.

#### Interactive bar snippet (the app's QuickType-bar motif inside Siri, Shortcuts and Spotlight)

Every Prefill intent result ends with a small replica of Safari's two-slot bar for that site. Tapping the other value swaps the slots right in the snippet, without opening the app, and the card is rewritten underneath.

Why: It makes the GetValue answer look like the thing Safari will show, and lets the person swap slots without opening the app. It's the motif carried into the system. The cost is mostly moving the replica view into a module the snippet can use.

Build notes: After phase 3 merges, move BarReplicaView out of App/ into a SwiftUI file the app target and intents share. With intents in the app target, that can just stay in the app target, no new package needed. BarPreviewSnippet: SnippetIntent(host, kind) reads AppState and ExtensionEvents from the store (one Keychain read), runs Ranker and returns .result(view:). Each slot is a Button(intent: PromoteValueIntent(valueID, host)), which uses .main and .background, upserts AppState.pins, runs CardWriter and calls BarPreviewSnippet.reload(). Expect glass and glassEffectID morphs to be dropped in the snippet container (inferred), and design it to look right flat.

Evidence:
- AI:3663 SnippetIntent, AI:3667 SnippetIntent.reload() (iOS 26)
- AI:4487 ShowsSnippetView, AI:4490 ShowsSnippetIntent
- SDK _AppIntents_SwiftUI.framework/.../arm64e-apple-ios.swiftinterface:186 Button(intent:label:), :237 Toggle(isOn:intent:label:)
- VERIFIED: BarSnippet: SnippetIntent returning .result(view:) with Button(intent:), plus BarSnippet.reload() called from another intent, typechecks (Probe.swift)
- Plan motif: .claude/plans/prefill-v1.plan.md lines 87-89 (bar replica with glassEffectID morph)

Risks:
- Inferred: whether Liquid Glass and glassEffectID morphs render inside the system snippet container. Animations may be dropped.
- The replica component is being built in App/ by another agent, and moving it is a cross-agent change.
- The snippet perform runs on every reload. Keep it to one Keychain read and no Contacts fetch.

#### Focus filter: Work Focus prefers work values

When Work Focus turns on, Safari starts offering the work email and phone first on every site without a pin, and Personal Focus switches back. The person sets it up under Settings > Focus > Work > Add Filter > Prefill, the same place Apple's own apps live.

Why: It's small, it's configured in the same Settings > Focus screen Apple's own apps use, and it improves the global order for every unpinned site at once. That's a genuine "part of iOS" moment with a real ranking payoff.

Build notes: App/Intents/PrefillFocusFilter: SetFocusFilterIntent with @Parameter preferredLabel: LabelEnum? and displayRepresentation "Prefer work info". perform writes Settings.focusLabel (a new field, app-only), then runs CardWriter with host nil, relying on skip-when-unchanged to limit iCloud churn. In Ranker, focusLabel is a tier below siteKindLabel and above the global order, and never above a pin. That ordering is the one test to add. Status: SetFocusFilterIntent typechecked against iOS 27. Background launch on a Focus change is standard behavior but wasn't exercised here.

Evidence:
- AI:10900-10911 SetFocusFilterIntent (appContext, suggestedFocusFilters(for:), invalidateFocusFilterAppContext)
- VERIFIED: a SetFocusFilterIntent with a label parameter and displayRepresentation typechecks against iOS 27 (Probe.swift)
- Packages/PrefillKit/Sources/PrefillKit/Ranking/Ranker.swift ranking order: pin, recent use on host, section hint, manual order

Risks:
- Card rewrite on every Focus change causes iCloud sync churn. The existing skip-if-top-two-unchanged rule limits it.
- Inferred: Focus changes launch the app in the background to run perform. This is standard Focus filter behavior but was not exercised here.
- Must never override an explicit site pin, or people will think pins are broken.

#### iOS 27 plumbing and what was checked and rejected

This is mostly invisible to the person. Intents run where the Contacts grant lives, Spotlight can ask Prefill to reindex, and nothing depends on private API.

Why: These aren't features, they're the rules every intent above follows: run in the app process under its Contacts grant, keep app-state single-writer, use no private API. They cost nothing beyond discipline.

Build notes: Every intent that touches the card or AppState gets allowedExecutionTargets = .main and supportedModes = .background. No AppIntents extension and no widget extension in v1. Before writing all the intents, run one xcodebuild with a single intent and entity to clear appintentsmetadataprocessor. Keep the rejected list from the scout (RelevantEntities, _ModelDelegationIntent, LongRunningIntent and the others) as a note in research/, not in code. Verified only by reading the iOS 27 SDK interfaces and a swiftc -typecheck. Build, signing with 5AKJYZ7USP and runtime behavior have not been run.

Evidence:
- AI:3571 IntentExecutionTargets (.default, .main, .appIntentsExtension, .widgetKitExtension), AI:3112 AppIntent.allowedExecutionTargets, AI:4409 EntityQuery/IntentValueQuery allowedExecutionTargets (all iOS 27)
- AI:4251 IndexedEntityQuery (iOS 27), AI:387-405 relatedAppEntityIdentifier (iOS 27)
- AI:5050 IntentSystemContext.isVoiceOnly/locale (iOS 27)
- AI:4815-4845 RelevantEntities / AppEntityContext (iOS 27): the only context is .audio(.nowPlaying), so rejected
- AI:2854-3071 _ModelDelegationIntent, IntentPrompt (iOS 27) are @_documentation(visibility: internal) and underscored, so rejected as not public
- AI:3603 LongRunningIntent, AI:3633 RunSystemShortcutIntent, AI:2652 SyncableEntity, AI:10652 EntityOwnership (iOS 27): no fit for Prefill
- WidgetKit.swiftinterface:951 systemExtraLargePortrait, :605 isDynamicIslandLimitedInWidth (iOS 27): no fit
- Probe: /private/tmp/claude-502/-Users-tarunyadgirkar/17d1533c-d1e2-486a-873f-dba3b0de6a41/scratchpad/intents/Probe.swift; `xcrun -sdk iphoneos swiftc -typecheck -target arm64-apple-ios27.0 -swift-version 6` exit 0

Risks:
- Typecheck is not a build. appintentsmetadataprocessor can still reject parameter or entity shapes, so run one xcodebuild of a minimal intents target before committing to the design.
- The runtime semantics of allowedExecutionTargets are inferred from its name and option cases. The interface has no doc comments.

#### App icon direction A, Slot: the iOS 27 contact suggestion bar with the chosen slot lifted

A small copy of the real iOS 27 contact suggestion bar. It has two slots split by a hairline, and each slot shows a short label line over a longer value line, the same layout as the 'work / c-1-work@example.com' bar in the spike screenshots. The left slot is a marigold glass chip that rises above the bar, and a row of five glass keycaps sits underneath. Anyone who has used AutoFill sees 'the keyboard picked this one for me' at a glance.

Why: It's the chosen direction. It draws the one thing Prefill changes (which value sits in slot one of Apple's bar) and it's the same motif as the in-app and popup replicas, so the brand repeats across the icon, app, popup and Siri snippet.

Build notes: Refine design/icon/a-slot.icon, then render with ictool into assets/generated/. Steps are in icon_recommendation.

Evidence:
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-a-slot-light.png
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-a-slot-dark.png
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-contact-sheet.png
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/a-slot.icon/icon.json
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/directions.py (PALETTES['a-slot'], DIRECTIONS['a-slot'])
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/ios27-order-casey-email.png (reference: real two-slot label-over-value bar)
- Verified: Xcode 27 ships ictool at /Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool (bundle-version 129, short 27.0); renders .icon bundles with --rendition Default/Dark/ClearLight/TintedDark
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/v1-contact-sheet.png (first pass, before refinement)

Risks:
- Light and dark renditions look almost the same because the light background is already dark; a paler teal light variant may be wanted
- At 60 px the keycaps blur into a band; the bar and chip still read
- The five keycaps add detail that Apple's simpler icons avoid; they could be cut if the bar alone reads well enough on a home screen
- Tinted and Clear renditions were not checked

### Later

#### "Save to your card?" sheet that opens itself after a submit

After a sign-up or checkout form with an email Prefill hasn't seen, Safari slides up Prefill's sheet with the value, a label picker (home, work, other) and Save / Not Now. It works like Safari's own save-password prompt, but for contact info, which Safari never offers to save.

Why: It's the most Safari-like idea, but openPopup's behavior in shipping iOS Safari is unverified, a submit usually navigates away, and an unprompted sheet is intrusive. The badge plus Recently added covers the same need quietly.

Build notes: After v1, run one simulator check: does browser.action.openPopup() present from background.ts with no user gesture? If it does, add setPopup({tabId, popup:'popup.html#review'}) on the post-navigation load for a queued needsReview capture, behind an off-by-default setting "Ask me right after I submit". Never show it more than once per site visit.

Evidence:
- MDN BCD: action.openPopup Safari 16, safari_ios mirrors
- WebKit source WebExtensionContextAPIActionCocoa.mm:175-229 (scratchpad/ctxAction.mm): openPopup fails only if the delegate lacks presentPopupForAction or another popup is open. No user-gesture check in WebKit (WebExtensionAPIActionCocoa.mm:654-673)
- Binary: Safari implements -[SFWebExtensionsController webExtensionController:presentPopupForAction:forExtensionContext:completionHandler:], so canProgrammaticallyPresentPopup() (WebExtensionActionCocoa.mm:1027-1036) returns true in Safari
- Observed: Safari never offers to save typed contact values (research/REPORT.md, Save offer spike)
- Inferred: Safari's own delegate may still refuse or rate-limit programmatic presentation, and the page may be navigating away when the submit fires

Risks:
- Unverified on shipping iOS Safari: openPopup might need a user gesture or be blocked in Safari's delegate. Needs one simulator check
- Submit often navigates, so the sheet may present over the next page or be torn down. Trigger on the post-navigation page load using the queued capture
- An unprompted sheet is intrusive. Keep it off by default and never open it twice per site visit

#### Per-site icon state in the page menu

Prefill's icon in the page menu changes when it has tuned this site: a filled glyph when a pin or a site-specific order is active, the normal glyph otherwise. Safari already greys the icon when Prefill has no access to the site. People can tell whether Prefill is working here without opening anything.

Why: At about 20 pt in a menu row, the difference between two glyphs is barely readable. Per-tab SVG support on iOS is unverified, and the popup already shows a pin state clearly.

Build notes: If revisited, return tuned: Bool in PageContextResponse and call action.setIcon({tabId, imageData}) with PNG imageData rather than an SVG path. The two glyphs must differ in shape, for example a pin mark, not only in fill.

Evidence:
- MDN BCD: action.setIcon Safari 15.4 (imageData 15.4, null 18), safari_ios mirrors
- Binary: -[SFWebExtensionPageMenuController iconForTab:size:], wantsGrayscaleIconForTab:, wantsTemplateIconForTab:, shouldShowWarningTriangleImageForTab:, -[SFWebExtensionPageMenuController webKitExtensionAction:didChangeForTab:] (Safari redraws the row when the action changes per tab)
- Observed: the icon is grey before the site grant and colored after (assets/generated/spike-capture-grant-1-page-menu.png vs spike-capture-grant-5-page-menu-after.png)

Risks:
- Icon is about 20pt in a menu row, so the difference must be shape, not just color
- Whether Safari honors per-tab SVG icons in the iOS menu (versus only PNG imageData) is unverified

#### Tidy messy values on import

Addresses typed as one run-on line, shouty capitals or 'apt 4' tacked onto the street come back split into proper street, city, state and postal code before they are written to the card, so Safari fills each address field correctly. Near-duplicates like 'Apt 4' and '#4' collapse into one entry instead of crowding the bar.

Why: Emails and phones are the user's pain, and their tidying is already deterministic in Normalizer. Address splitting matters less, and the model invented a country in the probe, so the safety checks cost more than the payoff in v1.

Build notes: When this comes, use NSDataDetector address components first (NSTextCheckingTypeAddress, verified in the SDK headers), the model only for leftovers, the token-subset check, country from the device region, and a before/after confirmation row. Put it in the app's review step and in first-run card import.

Evidence:
- Observed (probe.swift, @Generable CleanAddress): '2150 shattuck ave apt 4 berkeley ca 94704' -> street '2150 Shattuck Ave Apt 4', city 'Berkeley', state 'CA', postalCode '94704', country 'USA' in 965 ms (Mac). It filled country USA although the input did not say so, which breaks the instruction not to invent missing parts
- SDK Foundation NSTextCheckingResult.h:28 NSTextCheckingTypeAddress and :126/:132 NSTextCheckingStreetKey / ZIPKey give a deterministic address parser

Risks:
- Model fills in parts that were not there (observed with country); the token-subset check must reject those
- Non-US formats are untested; NSDataDetector and the model both vary by locale

#### Paste anything to add your info

In the Card screen the person can paste an email signature, a résumé header or a block from an old note, and Prefill pulls out the emails, phones and addresses as ready-to-add rows, already labeled. It is the fastest way to fill a sparse card on day one.

Why: The card is imported from the person's existing My Info, so day one is rarely empty. It's small and nice, but it competes for Card-screen polish time.

Build notes: Later, add a Card add menu item "Paste from text": NSDataDetector always, plus an optional @Generable Extracted list merged by normalized key, keeping only values that appear verbatim in the pasted text. Every row needs confirmation, and each goes through the auto-label rules.

Evidence:
- SDK swiftinterface :1425 anyOf guide and GenerationGuide.count / maximumCount for arrays (lines 1419-1482)
- SDK swiftinterface :445 contextSize (8192 observed on this Mac, 4096 back-deployed default) is ample for a pasted signature
- Inferred from the address and label probes above; extraction from free text was not run separately

Risks:
- The model may invent or reformat a value; the 'must appear in the input' check drops those
- Pasted text might contain other people's details (a colleague's signature); every row needs explicit confirmation

#### Siri and Shortcuts: "Use my work email on this site"

On a sign-up page in Safari, the person says "Use my work email here with Prefill" or runs it from Shortcuts. Siri answers with a small QuickType-bar snippet that shows the work email sliding into slot 1, and the next tap in the field offers it first.

Why: Siri can't read Safari's URL, so "this site" depends on a guessed most-recent host. That needs a new ExtensionEvents field written on page loads, which adds Keychain writes. The popup pin does the same job with no guessing.

Build notes: After v1: add ExtensionEvents.lastContext {host, at}, written only when the host changes, then PinValueIntent(value: ValueEntity, site: SiteEntity) with requestValue when there's no recent host. It reuses PromoteValueIntent's write path and BarPreviewSnippet. Name the host in the dialog.

Evidence:
- SDK root: /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks; 'AI' below = AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface
- AI:10728 AppShortcutsProvider, AI:10737 updateAppShortcutParameters(), AI:10937 AppShortcut(intent:phrases:shortTitle:systemImageName:)
- AI:4229 EntityStringQuery (match "work email" to a value)
- AI:3250 IntentModes (.background runs perform in the app process, so it has the app's Contacts grant)
- AI:3112, AI:3571 iOS 27 static allowedExecutionTargets / IntentExecutionTargets (.main, .appIntentsExtension, .widgetKitExtension)
- AI:3224 requestConfirmation(actionName:dialog:snippetIntent:)
- VERIFIED: swiftc -typecheck against the iOS 27 SDK passes for PinIntent (supportedModes, allowedExecutionTargets = .main, entity parameter, AppShortcut phrase with \(\.$value)) in /private/tmp/claude-502/-Users-tarunyadgirkar/17d1533c-d1e2-486a-873f-dba3b0de6a41/scratchpad/intents/Probe.swift
- Existing model: Packages/PrefillKit/Sources/PrefillKit/Model/Documents.swift (AppState.pins, single-writer split), Model/Events.swift (SitePin)

Risks:
- Inferred: the "this site" heuristic picks the wrong host if the person switched tabs without focusing a field. Mitigate by naming the host in the dialog.
- Adds a Keychain write per new host on page load (ExtensionEvents is a Keychain item on the free team).
- Inferred from the API name, not documented in the interface: allowedExecutionTargets = .main forces perform into the app process.
- Siri voice in the Simulator is unreliable. Exercise it through the Shortcuts app instead.
- Touches ExtensionEvents and the handler, which another agent owns right now. Coordinate the lastContext field.

#### Siri and Shortcuts: "Add an email to Prefill"

"Add an email to Prefill" asks for the address, asks Home, Work or other, saves it to the person's card and shows where it lands in the bar. It works as a Shortcuts action too, so a "new job" shortcut can add the work email and phone in one run, and Undo takes it back.

Why: Dictated email addresses are error-prone, and the Card screen's add button plus capture already cover adding values. It's useful mainly for power-user Shortcuts.

Build notes: Later: AddValueIntent with UndoableIntent, requestConfirmation with the snippet, Normalizer dedupe, and CardWriter add-without-drop. Ship one AppShortcut per kind, because phrases can't carry free text.

Evidence:
- AI:3179 requestChoice(between:dialog:), AI:3186 IntentChoiceOption (iOS 26)
- AI:3708 UndoableIntent with @MainActor undoManager (iOS 26)
- AI:3224 requestConfirmation(... snippetIntent:)
- VERIFIED: an AddValue: AppIntent, UndoableIntent that calls requestConfirmation(actionName: .add, snippetIntent:), registers an undo and returns ReturnsValue<ValueEntity> typechecks against iOS 27 (Probe.swift)
- Packages/PrefillKit/Sources/PrefillKit/Model/Normalizer.swift and Card/CardWriter.swift already provide dedupe and add-to-card

Risks:
- Dictated emails come out wrong ("at", "dot", homophones). Always confirm with the snippet before saving.
- Address parsing from one free-text string is lossy. Use NSDataDetector address components and show the parsed result in the confirmation.
- Inferred: where UndoableIntent's undo appears in Siri and Shortcuts on iOS 27. The interface only exposes undoManager.

#### Spotlight: sites and saved values as indexed entities

Typing "netflix" in Spotlight shows "Netflix, you use tarun@gmail.com", which answers "which email did I sign up with?". Typing "work email" shows the value and the sites it is used on. Tapping either opens Prefill on that site's page.

Why: Typing "netflix" in Spotlight to see your email is lovely, but it copies PII into the Spotlight index, goes stale until the app runs, and duplicates the card that's already indexed via Contacts. GetValueIntent answers the same question with authentication in v1.

Build notes: The v1 SiteEntity should be shaped so it can adopt IndexedEntity later (stable registrable-domain id, a title, no value in the title). Later: IndexedEntityQuery (iOS 27), indexAppEntities after each AppState write, a "Show in Spotlight" setting defaulting off, and a masked subtitle.

Evidence:
- AI:2609 IndexedEntity (attributeSet, hideInSpotlight iOS 18.4)
- AI:365-367 CSSearchableIndex.indexAppEntities / deleteAppEntities
- AI:4251 iOS 27 IndexedEntityQuery: reindexEntities(for:indexDescription:), reindexAllEntities(indexDescription:)
- AI:387-405 iOS 27 CSSearchableItem / CSSearchableItemAttributeSet.relatedAppEntityIdentifier
- AI:10880 OpenIntent, AI:3684 TargetContentProvidingIntent (iOS 26)
- VERIFIED: ValueEntity: IndexedEntity, a query conforming to EntityStringQuery & IndexedEntityQuery, and indexAppEntities typecheck against iOS 27 (Probe.swift)

Risks:
- Copies emails, phones and addresses into the Spotlight index, which widens exposure on an unlocked phone. Inferred: whether Lock Screen Spotlight shows them. Default subtitle could mask the local part.
- Staleness: new sites seen by the extension reach Spotlight only when the app or an intent runs. Unverified whether the Safari handler can index directly (CoreSpotlight is not marked extension-unavailable).
- The person's own card already appears in Spotlight through Contacts, so value results may look duplicated. The per-site results are the new information.

#### Control Center, Lock Screen and Action button control: Site matching

A Site matching toggle sits in Control Center, on the Lock Screen or on the Action button. Turning it off puts the card back in the person's own order and stops per-site reordering (useful before lending the phone, or when the Mac's card order matters), and the control's status reads Paused.

Why: It needs a widget extension, which takes the last free-team profile slot and an untested Contacts grant. The behavior it toggles already lives in the Settings switch, and most people will rarely flip it.

Build notes: Later, as a PrefillWidgets target with ControlWidgetToggle and SetSiteMatchingIntent (.main, .background). Revisit once a paid team removes the 3-app limit.

Evidence:
- SDK WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-ios.swiftinterface:1182 ControlWidgetToggle(isOn:action:label:valueLabel:) requires SetValueIntent where ValueType == Bool
- WidgetKit.swiftinterface:1127 StaticControlConfiguration, :1119 ControlValueProvider, :522 controlWidgetStatus, :537 controlWidgetActionHint, :195-199 ControlCenter.shared.reloadControls(ofKind:)
- AI:3658 SetValueIntent, AI:59 ControlConfigurationIntent
- VERIFIED: MatchingControl: ControlWidget + SetMatching: SetValueIntent with allowedExecutionTargets = .main typechecks (Probe.swift)
- Packages/PrefillKit/Sources/PrefillKit/Model/Documents.swift Settings.matchEachSite already exists; Store/KeychainStore.swift:74 uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, which is readable from the Lock Screen after first unlock

Risks:
- Free team (inferred from community reports, not verified here): free provisioning counts each extension's profile against the 3-app-per-device limit, so app + Safari extension + widget extension uses all three slots and leaves nothing for a share extension. Each new bundle ID also counts toward the 10-App-IDs-per-week cap.
- Inferred: whether a Lock Screen tap actually launches the app in the background to run a .main-targeted intent while locked. If it runs in the widget process instead, it must not write app-state; add a third control-state document in that case.
- Unverified: whether the widget extension inherits the app's Contacts grant. The Safari handler was observed to inherit it, and the widget extension was not tested. The .main target avoids the question.
- The Safari handler must read Settings fresh on every pageContext, or pausing will lag.

#### Visual Intelligence: add a new address from the camera or a screenshot

After a move, the person points the camera or a screenshot at a lease, a utility letter or a business card. Visual Intelligence offers "Add to Prefill" with the address, email or phone it found, and one confirmation saves it to the card.

Why: It's device-only (can't run in the Simulator), its build-time metadata rules are unverified, and it's about addresses after a move, which is not the core email problem.

Build notes: Later: CapturedValueQuery as an IntentValueQuery over SemanticContentDescriptor, then Vision OCR, then NSDataDetector, then the add sheet with confirmation. Never save silently.

Evidence:
- VisualIntelligence.framework/Modules/VisualIntelligence.swiftmodule/arm64e-apple-ios.swiftinterface:36 SemanticContentDescriptor (labels, pixelBuffer), :12 conforms to _SystemIntentValue (iOS 26), :33 IntentValueConvertible (iOS 27)
- AI:4402 IntentValueQuery (Input, values(for:), iOS 27 allowedExecutionTargets)
- VERIFIED: IntentValueQuery with values(for: SemanticContentDescriptor) returning [ValueEntity] typechecks (Probe.swift)

Risks:
- Visual Intelligence needs an Apple Intelligence iPhone and cannot be exercised in the Simulator, so this is device-only testing.
- Typecheck passed, but the App Intents metadata processor at build time may impose extra rules on IntentValueQuery result types. A real build is needed.
- OCR of addresses is noisy. Always show the parsed fields before saving.
- Inferred: no entitlement is needed. No entitlement key was found, but this was not built and signed with the free team.

### Skip

#### App icon direction B, Shortlist: the contact card's values reordered, with the winner pulled to the top

Three rows like the values on a contact card. The top row is persimmon glass, tilted a few degrees as if it had just been pulled into first place, and the two rows below are quiet milk glass. It shows what Prefill actually does under the hood: it rewrites the order of your card so the right value comes first. The warm paper background makes it the friendliest of the three on a home screen.

Why: It reads as a generic to-do or Reminders list. At home-screen size the lower rows vanish, leaving one orange bar. The persimmon fill also clashes with the app's rule that a hot accent is a mark, not paint.

Build notes: Keep the tilted "just reordered" idea for motion: use it as the slot-swap animation in the replica, not in the icon.

Evidence:
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-b-shortlist-light.png
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-b-shortlist-dark.png
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-contact-sheet.png
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/b-shortlist.icon/icon.json
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/directions.py (PALETTES['b-shortlist'], DIRECTIONS['b-shortlist'])
- research/REPORT.md Spike results: slot 1 is the value with stored identifier 0, and a fresh rewrite renumbers 0..n (the mechanism this icon depicts)

Risks:
- Closest of the three to a generic list or reminders icon; the tilt and the single accent carry the meaning
- Persimmon is a hot accent used as a fill here, which is acceptable for an icon but breaks the in-app rule that hot accents are 'light, not paint'; the app UI should not copy it onto buttons
- The lower rows fade to near-invisible at 60 px, leaving one orange bar
- Tinted and Clear renditions were not checked

#### App icon direction C, Caret: a monogram P built from a text caret and a suggestion chip

A capital P made of two pieces. The stem is a tall fern-green text caret, and the bowl is a spring-green glass suggestion chip sitting beside it, with a label line and a value line inside. The chip is squared on the side facing the caret and round on the outside, so it reads both as a chip and as the curve of the letter. It is the boldest at small sizes and works as a brand mark beyond the icon.

Why: At every size in the contact sheet it reads as a flag on a pole before it reads as a P or as a caret with a chip, and it says the least about what the app does. Its strengths (boldness at 60 px and a non-blue palette) are better taken into A.

Build notes: No further work. Its lesson for A is that fewer, larger shapes survive at 60 px.

Evidence:
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-c-caret-light.png
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-c-caret-dark.png
- /Users/tarunyadgirkar/TarunsCode/prefill/assets/generated/icon-contact-sheet.png
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/c-caret.icon/icon.json
- /Users/tarunyadgirkar/TarunsCode/prefill/design/icon/directions.py (PALETTES['c-caret'], BOWL path, DIRECTIONS['c-caret'])

Risks:
- Shows the subject least literally; someone who doesn't know the app sees 'P' before they see 'suggestion beside a caret'
- In dark the stem and bowl are close in hue; a little more value contrast between Fern and Spring may help
- The flat-left, round-right bowl is close to a speech-bubble or flag silhouette at some sizes; check it on a real home screen
- Tinted and Clear renditions were not checked
