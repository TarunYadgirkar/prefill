# Prefill research report

Last updated 2026-09-30. This report covers what iPhone Safari's contact AutoFill does today, why it fails people who have more than one email, phone or address, and which parts of it a third-party app can actually change on iOS 26 and 27. It replaces `simulator-findings.md` as the reference for the build. That file is kept as the first raw observation log, and two of its conclusions are corrected below.

Confidence tags used throughout:

| Tag | Meaning |
| --- | --- |
| Observed | Seen in the iOS Simulator, with a screenshot in `assets/generated/` |
| SDK | Read in the iOS 27.0 SDK headers or Swift interfaces under `/Applications/Xcode.app/.../iPhoneOS.sdk` |
| Doc | Stated on developer.apple.com, support.apple.com or a WWDC session |
| Binary | Read from a disassembly of the iOS 27.0 Simulator runtime (build 24A434). This describes private implementation and can change in any update. |
| Unverified | Inferred and not yet tested |

## Short answer

No public API lets a third-party app put its own suggestions into the QuickType bar that Safari shows above the keyboard for contact fields. That bar is filled by Apple's AutoFill UI from one contact card, the one set as My Info. (SDK: the AutoFill credential request types are only Password, PasskeyAssertion, PasskeyRegistration and OneTimeCode, `ASCredentialRequest.h:20-25`. Binary: AutoFillUI reads bar values through `_meContactInfosForTextContentType:meContact:`.)

An app can still change what that bar shows, because the bar reads ordinary Contacts data that apps can write. The plan that follows from the evidence has two halves:

1. **Steer the native bar through the card.** For an empty field the bar shows the card's primary value (stored identifier 0) and then the first other value in array order. Any card freshly written in one save gets identifiers 0..n in array order, so for a card the app rewrites, slot 1 and slot 2 are simply the first two values it wrote (Observed, iOS 27.0 and 26.5, see [Spike results](#spike-results)). An app with Contacts write access, even limited access to just this card, can rewrite the card, and Safari shows the change the next time a field is focused.
2. **Capture what the user types, because Safari never will.** A Safari Web Extension can read form values on submit and pass them to the app, which adds them to the card after the user confirms.

A third route may exist: a Safari Web Extension that injects a `<datalist>` into the focused field, which WebKit's source routes into the same bar. It is untested and is the first spike to run (see [Injected datalist](#injected-datalist-untested-highest-priority-spike)). Everything else (a custom keyboard, a credential provider's text-insert sheet, a ContactProvider extension) sits next to the bar rather than in it, and each has a hard limit described under [Surfaces](#surfaces-a-third-party-app-can-use).

## Spike results

Four hands-on spikes ran on cloned iOS 27.0 Simulators on 2026-10-01. Each spike's claims were checked against its own screenshots and logs by a separate reviewer. Code is in `spikes/`, evidence in `assets/generated/spike-*`.

| Spike | Verdict | What it showed |
| --- | --- | --- |
| Contacts writes (`spikes/contacts`) | Pass | Rewriting the card through `CNSaveRequest.updateContact` changes Safari's bar. Slot 1 is the value whose stored identifier is 0, slot 2 the first other value in array order. Moving existing `CNLabeledValue` objects keeps their identifiers, so a plain move does not change slot 1. Writing every value as a fresh `CNLabeledValue(label:value:)` in ranked order, in one save, renumbers identifiers 0..n and the bar follows exactly. This works under iOS 18 limited access with only the person's card shared (the system picker even tags that card "me"). Safari shows the new order the next time the field is focused, with no relaunch. A contact picked through `CNContactPickerViewController` but not shared cannot be saved (CNError 200). |
| Save offer (`spikes/contacts`) | Confirmed absent | Real GET and POST forms with a submit button, a new email and a new phone: Safari showed no save prompt, did not change the card, and did not offer the values later. |
| Capture (`spikes/capture`) | Pass | An MV3 extension (content.js, background.js, `sendNativeMessage`, `SafariWebExtensionHandler`, App Group JSONL) captured button submits, Return submits and, through an input cache flushed on `pagehide` or `visibilitychange`, fetch-driven forms. Password and one-time-code fields were skipped. The handler inherits the containing app's Contacts grant and saved a reordered card itself. Calling `requestAccess` from the handler must never happen: its prompt names the app, Don't Allow denies the app permanently, and Continue dead-ends. Cold handler latency about 1.3 s, warm about 10 ms. Under the default "All Websites: Ask" the content script does not run and Safari shows no prompt, so onboarding must send the person to grant access. |
| Datalist (`spikes/datalist`) | Pass, with costs | An injected `<datalist>` reaches the real QuickType bar (3 options, values only, labels ignored, long emails wrap after a hyphen). It wins only where Safari has no contact suggestion: with Use Contact Info off, on fields Safari does not classify, or after a typed prefix matches nothing on the card. Changing `autocomplete`, `name` or `id` does not help. Any `list=` also opens WebKit's in-page dropdown of all options on focus, which could not be suppressed, and sometimes an iOS 27 "Suggested" strip under the field. A tap fires one trusted `input` and one `change` event. |
| My Info vs My Card (`UITests/MyInfoSpikeTests.swift`, 2026-10-02) | One setting | Settings > Apps > Safari > AutoFill > My Info and Settings > Apps > Contacts > My Info are two screens for one pointer. Both settings bundles call the same private `CNContactStore setMeContact:error:` and `_ios_meContactWithKeysToFetch:error:` (Binary), and on a clone of the iOS 27.0 test device, picking Casey under Contacts made Safari's row read Casey, and picking Drew under Safari made Contacts read Drew (`spike-myinfo-*.png`, Observed). Safari's contact AutoFill therefore always reads the card NameDrop, Share My Card and the Contact Poster use. |
| Text insert (`spikes/textinsert`) | Partial | A provider declaring only `ProvidesTextToInsert` is listed (the containing app also needs the credential-provider entitlement) and appears under the field's edit menu: caret, AutoFill, Passwords, provider, value, 5 to 6 taps. The inserted text never landed in the Simulator, in Safari or in a native field (RTI "requires a valid sessionID"). `ASSettingsHelper.requestToTurnOnCredentialProviderExtension` never prompted. Needs a device run before any work depends on it. |

### Keeping the shared card short

Because the bar reads the same card people share, Prefill keeps emails, phone numbers and addresses on that card, since Safari needs them there, and keeps links and custom fields on a contact of its own: an organization card named "Prefill · <the person's name>", recognized by its department field ("Links and custom fields for Prefill"), saved in the same account as the person's card so iCloud syncs it. `CNContactStoreGateway` reads the two as one record and writes each part to its contact. Until the person has a Prefill contact, links and custom fields stay on their card exactly as before, so Prefill never makes a contact without being asked. They stay there until the person reviews the exact list under Settings > Sharing your card (iPhone) or the Sharing your card section (Mac) and confirms; the move copies them to Prefill's contact and removes them from the card in one save request. From then on new links and custom fields go to Prefill's contact. A look-alike contact in another account is ignored: only copies in the card's own account count, and two copies made on two devices before iCloud syncs are read as one and both kept up to date, never deleted.

What each way of sharing sends (Doc, support.apple.com/guide/personal-safety/ips97e16d3b1): NameDrop sends only the name, the one phone number or email the person picks (remembered for next time) and the Contact Poster, never addresses, links or related names. Share Contact sends the whole card unless the person taps Filter Fields at the top of the share sheet and turns fields off, and that choice is not remembered. Under limited Contacts access, an app always sees the contacts it creates; a Prefill contact made on another device has to be shared with the app, which the Sharing screen offers through `ContactAccessButton`.

## What Safari's contact AutoFill does on iOS 27

Test setup: iPhone 17 Pro Simulator, iOS 27.0 (24A434), repeated on iOS 26.5 (23F77). The test page is `testbed/form.html`, which has one form with `autocomplete` attributes and one without. Cards are in `testbed/alex-rivera.vcf` and `testbed/ordering-variants.vcf`. The recipe for switching My Info without the Settings app is in [Appendix A](#appendix-a-simulator-recipe).

### Which values the bar offers

| Card used as My Info | Value order on the card | Bar for an empty email field | Screenshot |
| --- | --- | --- | --- |
| Casey | work, other, home, custom "Gym", unlabeled | work, other | `ios27-order-casey-email.png` |
| Casey (phones) | work, other, home, mobile, "Gym" | work, other | `ios27-order-casey-phone.png` |
| Casey (addresses) | work, other, home, "Gym" | 301 Work St, 302 Other St | `ios27-order-casey-address.png` |
| Avery | unlabeled, home, work | "email" (the unlabeled one), home | `ios27-order-avery-unlabeled-first.png` |
| Drew | custom "Personal", home, work | "Personal", home | `ios27-order-drew-custom-label-first.png` |
| Blake (vCard had `OTHER;pref` last) | other, home, work after import | other, home | `ios27-order-blake-pref-import.png` |

The rule these rows support is that **an empty field shows the first two values in card order, whatever their labels are.** These cards were all imported from vCards, which number values 0..n in order. The contacts spike refined the rule for edited cards: slot 1 is the value with stored identifier 0, then slot 2 is the first other value in array order. See [Spike results](#spike-results). A home or mobile label does not lift a value above position, an unlabeled value in slot 1 still shows (captioned with the generic word "email" or "phone"), and a custom label shows exactly as typed while system labels show in lowercase. The same rule holds for emails, phones and addresses, and iOS 26.5 behaves identically (`ios26_5-order-casey-email.png`, `ios26_5-order-avery-unlabeled-first.png`).

This corrects the first test. On the Alex card the missing school address was third, unlabeled and the only value without `pref`, so the original run could not tell those explanations apart. The variant cards separate them, and position is the only one that predicts every row.

### What `pref` does

iOS stores no "preferred" flag. When a vCard is imported, a value marked `TYPE=pref` is moved to slot 1 and the marker is dropped. In the Simulator's contacts database, the Blake card's `OTHER;pref` email landed at identifier 0 and the database row has no column for a preferred flag (Observed, private schema). The public API agrees: `CNLabeledValue` has only `identifier`, `label` and `value` (SDK, `CNLabeledValue.h:21-24`). So "mark as preferred" cannot be a feature. Reordering is the only lever.

### Values past the second

All values remain reachable by typing. With Casey as My Info, typing `c-4` narrowed the bar to the fourth value ("Gym") and typing `c-5` to the fifth, unlabeled one (`ios27-prefix-casey-4th-value.png`, `ios27-prefix-casey-5th-value.png`). No cap on stored values was seen. Tapping "AutoFill Contact" opens a sheet that lists every email on the card, then Customize..., Other Contact... and Cancel. Picking one fills only the focused field.

### Fields without `autocomplete`

Safari recognized an untagged input labeled "Your e-mail" (`name="usr_contact"`) as an email field and offered the same two values (`ios27-untagged-email-quicktype.jpg`). Safari's own field detection is therefore not the weak point for simple cases like this one.

### Saving new values

Safari's own UI never offers to save a contact value typed into a form. The first runs could not show this because the testbed forms had no submit button; the contacts spike then submitted real GET and POST forms and saw no prompt, no card change and no later suggestion of the typed values (Observed). The claim is consistent with Apple's iOS 27 iPhone User Guide, which describes My Info as the only source of contact AutoFill and describes a save path for credit cards only (Doc, support.apple.com/guide/iphone/iphccfb450b7). That is evidence by absence. The test still to run is in [Open tests](#open-tests).

### When Safari notices card changes

Switching My Info only showed up in Safari after Safari was relaunched and `contactsd` was killed (Observed, Simulator). A value edit made through the Contacts framework is different: Safari showed it the next time the field was focused, with no relaunch (Observed, contacts spike).

## Common problems with contact AutoFill

These come from the user's complaint, the Simulator runs above, and the field-detection and fill code in Chromium, Firefox and Bitwarden (sources saved in the session scratchpad: Chromium `form_field_parser.cc` and `form_autofill_util.cc`, Firefox `FormAutofillUtils.mjs` and `FormAutofillHeuristics.mjs`, Bitwarden `insert-autofill-content.service.ts` and `dom-query.service.ts`).

| Problem | Where it comes from | Applies to iOS Safari? |
| --- | --- | --- |
| New values are never saved. A person who types a new email has to open Contacts and add it by hand. | Safari has no save offer for contact info (Doc, by absence) | Yes, and this is the user's main complaint |
| Only two values show before typing, and the two are fixed by card order, so a person with five emails sees the same two everywhere. | Observed rule above | Yes |
| The card has no notion of which value suits which site, so the work email is offered on a shopping site and the personal one on a work portal. | The bar has one global order per card | Yes |
| One card holds everything, so a second identity (a work persona, a family member) needs a separate card reached through "Other Contact..." and a picker. | AutoFill sheet layout (Observed) | Yes |
| Preferred markers from imported vCards are lost. | `pref` is applied once at import (Observed) | Yes |
| Edits made on another device can be overwritten. Two saves that touch the same contact keep only the last one. | `CNContactStore.h:205` and `CNSaveRequest.h:18`, "the last saved change wins" (SDK) | Yes, for any app that edits the card |
| Linked cards (for example an iCloud card linked to a Gmail card) show as one merged contact, and where an edit lands is undocumented. | Contacts docs and `CNSaveRequest.h:38-43` | Yes, see [Data model](#data-model) |
| Short forms are skipped. Firefox treats a group of fields as fillable only when one field has an `autocomplete` value or there are at least 3 distinct field types (`AUTOFILL_FIELDS_THRESHOLD` returns 3, `FormAutofillUtils.mjs:137`). Chromium has a similar minimum (`kMinRequiredFieldsForHeuristics`, `form_field_parser.cc:307`) with an allow-list for single fields. A newsletter box with one email field falls under these thresholds. | Browser source | Not seen in Safari, which filled a two-field untagged form. Single-field forms are untested. |
| Filled values do not register with JavaScript frameworks. Bitwarden sets the value and then dispatches `keydown`, `keyup`, `input` and `change` events so that React-style forms notice the change (`insert-autofill-content.service.ts:362-377`). | Browser extension source | Relevant to any in-page fill the extension does |
| Fields inside shadow DOM are missed. Chromium looks only 2 shadow levels up for labels (`kMaxShadowLevelsUp = 2`, `form_autofill_util.cc:106`), and Bitwarden keeps its own set of discovered shadow roots. | Browser source | Relevant to the extension's field detection |

## Platform facts that shape the design

### The app cannot find the My Info card

`unifiedMeContactWithKeysToFetch:` is marked `NS_AVAILABLE(10_11, NA)`, which means macOS only (SDK, `CNContactStore.h:118-126`). A search of every iOS 27.0 framework header and Swift interface found no other way to read or set My Info, and `CNContactsUserDefaults` holds only sort order and country code (`CNContactsUserDefaults.h:23-25`). The device name stopped including the owner's name in iOS 16, so the app cannot guess either.

Onboarding therefore has to ask the person to pick their own card. `CNContactPickerViewController` needs no Contacts permission and shows the whole contact list, but it returns a read-only snapshot (SDK, `CNContactPickerViewController.h:16-21`; Doc, WWDC24 session 10121). Writing to the picked card still needs store access. The app should store the picked `identifier` and, if the person creates a new card instead, tell them to set it under Settings > Apps > Safari > AutoFill > My Info, since the app cannot do that for them.

In the Simulator's private database, My Info is a pointer stored per contacts account (`ABStore.MeIdentifier`) plus a global `MeSourceID`. On a phone with iCloud and Gmail accounts, each account may hold its own pointer. This is an inference from a private schema, it is unreachable from a sandboxed app, and it is only useful for understanding device behavior.

### Limited Contacts access is enough

iOS 18 added `CNAuthorizationStatusLimited` (SDK, `CNContactStore.h:46-47`), where the person shares only chosen contacts. The headers say nothing about writes under limited access. Apple's WWDC24 session 10121 says "Just like Full access, your app can modify or create contacts" (Doc). The contacts spike confirmed it: reorder, add and full rewrite all saved under limited access with only the person's card shared. The least-permission onboarding is: request access, the person taps "Select contacts" and shares only their own card, and the app saves to it. `ContactAccessButton` and `contactAccessPicker` (SwiftUI, iOS 18) let the app add more cards to the shared set later. A card picked through `CNContactPickerViewController` probably does not join the limited set by itself (Unverified). The probe that settles this is in [Open tests](#open-tests).

### Edits go through ordered arrays

`emailAddresses`, `phoneNumbers` and `postalAddresses` on `CNMutableContact` are ordered arrays of `CNLabeledValue` (SDK, `CNMutableContact.h:46-48`). The app can insert, relabel and reorder, then save with `CNSaveRequest.updateContact`. Every observed card got its order at vCard import. Whether reordering an existing card through `CNSaveRequest` changes the bar the same way is likely, since position is the rule, but it is not yet tested.

### Linked cards

A unified contact is "an in-memory, temporary view of the set of linked contacts" with its own identifier (Doc, Contacts overview). Fetches return unified contacts by default (`CNContactFetchRequest.h:57-61`), and nothing documents which underlying card receives an edit to the unified view. iOS has no public link or unlink API. To control where a write lands, the app should fetch with `unifyResults = NO`, find the members with `isUnifiedWithContactWithIdentifier:` (`CNContact.h:129`), and update one member on purpose, preferably the one in the iCloud container. That needs full access, or limited access that includes every member (Unverified). The fallback is to open Apple's own editor, `CNContactViewController` with `shouldShowLinkedContacts = YES` (`CNContactViewController.h:122-124`), and let it do the write.

Saves to read-only containers fail with `CNErrorCodeRecordNotWritable` (206), `CNErrorCodeParentContainerNotWritable` (207) or `CNErrorCodePolicyViolation` (500) (SDK, `CNError.h:30-39`). A 2016 forum report (thread 39086) saw error 500 when updating a card linked to a Facebook record. These containers do not exist in the Simulator.

## Surfaces a third-party app can use

| Surface | Reaches the QuickType bar? | Where it appears | Hard limits | Min iOS |
| --- | --- | --- | --- | --- |
| Editing the My Info card (Contacts framework) | Yes, indirectly. It controls which two values Safari shows. | Safari's own bar | Person must pick their card and grant access. One global order per card. Linked-card writes need care. | 9, limited access 18 |
| Safari Web Extension | No | In the web page itself. Can capture on submit and can draw its own in-page suggestion list. | Needs per-site or all-sites permission granted in Safari. Content scripts cannot message the app directly. | 15 for native messaging |
| Credential provider "text to insert" | No | A sheet opened from the field's long-press menu, likely under AutoFill > Passwords > provider (Binary, Unverified at runtime) | Must be enabled under AutoFill & Passwords. Fills one field per invocation. | 18 |
| Custom keyboard | Draws its own row in place of the bar | Replaces the entire keyboard | Blocked on secure, phone-pad and password fields. Gets no field type on untagged fields. Hides Apple's own contact suggestions (Unverified). | 8 |
| ContactProvider extension | No | Likely in "Other Contact..." (Unverified) | Contacts are read-only and probably cannot be My Info | 18 |
| Safari Web Extension with an injected `<datalist>` | Probably, if Use Contact Info is off (untested) | Safari's own bar, with Prefill's values | At most 3 options. Safari's own suggestions take precedence. | 15 |
| `WKFormInfo` in an in-app browser | No | Only inside the app's own `WKWebView` | Cannot see Safari | 27 |

### Safari Web Extension for capture

Apple's messaging doc says only background scripts and extension pages can send native messages, and "Content scripts that are injected into web content cannot send messages to the native app extension" (Doc). The capture path is therefore:

1. `content.js` listens for `submit` in the capture phase, with a fallback on submit-button clicks and `pagehide` for script-driven forms that never fire `submit`. It classifies fields by `autocomplete` token, then `type`, then name and label patterns, and skips passwords, one-time codes and card numbers.
2. It calls `browser.runtime.sendMessage` with the fields.
3. `background.js` forwards the payload with `browser.runtime.sendNativeMessage`. The manifest needs the `nativeMessaging` permission. The Xcode 27 template already ships this content-to-background pattern with an MV3 manifest.
4. The native handler, `SafariWebExtensionHandler.beginRequest(with:)`, reads the payload from `userInfo[SFExtensionMessageKey]` and the Safari profile UUID from `SFExtensionProfileKey` (SDK, `SFSafariApplication.h:8-10`, profile key iOS 17). The profile UUID lets values typed in a "Work" Safari profile go to a work identity.

The iOS app cannot push messages to the extension, and the app and extension do not share containers, so an App Group is the shared channel (Doc). The handler runs fresh for each message and can only answer requests the JavaScript starts.

The Contacts framework is not marked unavailable to app extensions (SDK: no `NS_EXTENSION_UNAVAILABLE` in Contacts or ContactsUI), so the handler can link it. **Whether the handler process can use the app's Contacts grant, or prompt for its own, is unknown.** The Simulator's `tccd` contains strings for attributing extensions to a responsible process, which hints that it inherits, but that is circumstantial. The design below does not depend on the answer: the handler always queues first and saves directly only when it finds access already granted.

Permission friction: the person grants the extension access per site, or for all sites, from the extension's entry in Safari's menu, and can change it later under Settings > Safari > Extensions (Doc). Since Safari 17 a site grant covers all profiles and Private Browsing. Relying on `activeTab` would mean tapping the extension before every form, which defeats passive capture, so onboarding should ask for "Always allow on every website" and explain why. From iOS 26.2 the app can check whether the extension is turned on with `SFSafariExtensionManager getStateOfExtensionWithIdentifier:` and open its settings with `SFSafariSettings openExtensionsSettingsForIdentifiers:` (SDK, `SFSafariExtensionManager.h:24`, `SFSafariSettings.h:41`). Neither reports per-site grants. Apple documents running and enabling web extensions in the iOS Simulator without a paid developer account.

### Custom keyboard

The iOS 27.0 keyboard gate, `-[UIKeyboardExtensionInputMode isDesiredForTraits:]`, rejects a custom keyboard on secure fields, on keyboard types 5 (`PhonePad`) and 6 (`NamePhonePad`), and on fields that need non-contact AutoFill such as logins (Binary; enum values from `UITextInputTraits.h:128-134`). Contact-AutoFill fields stay eligible. WebKit gives `type=tel` and `inputmode=tel` keyboard type 5 (Binary, `_updateTextInputTraits:`), so **a custom keyboard never appears on a properly tagged phone field.**

WebKit sets `textContentType` for keyboards only from the field's `autocomplete` value, through `contentTypeFromFieldName:` (Binary). A keyboard therefore sees `nil` on untagged fields like the testbed's "Your e-mail", even though Safari's own detection recognizes them. The keyboard also replaces Apple's whole keyboard, typing included, and Apple's contact suggestions probably disappear while it is active (Unverified). This surface is the only way to draw a custom suggestion row, but it loses on the phone field and on untagged fields.

### Credential provider "text to insert"

`prepareInterfaceForUserChoosingTextToInsert` and `completeRequestWithTextToInsert:completionHandler:` exist on iOS 18 and later, iOS only, and need the Info.plist capability `ProvidesTextToInsert` (SDK, `ASCredentialProviderViewController.h:67-81`, `ASCredentialProviderExtensionContext.h:71`). `ASSettingsHelper requestToTurnOnCredentialProviderExtensionWithCompletionHandler:` asks the person to enable the provider (`ASSettingsHelper.h:21`). The iOS 27.0 AutoFill context menu builds exactly three items, Contact, Passwords and Credit Card, and the text-insert hook lives inside the Passwords pane (Binary). The likely path is long-press the field, AutoFill, Passwords, choose the provider, then choose a value. That is four taps for one field, so this works as a backup for a value the bar does not show, not as the main experience.

### Injected `<datalist>` (untested, highest priority spike)

This is the only route found that could put Prefill's own values into Safari's real QuickType bar. WebKit's iOS code passes a focused field's `<datalist>` options to the keyboard as suggestion candidates, and tapping one inserts that option (read from WebKit source, not yet tried on shipping Safari). A Safari Web Extension's content script can add `list="..."` to the focused field and insert a `<datalist>` holding the values Prefill ranks best for that site and field.

Limits read from the WebKit source:

| Limit | Effect |
| --- | --- |
| At most 3 options are shown | Prefill picks the three best values for this site and field |
| "Text suggestions vended from clients take precedence" | Safari's own AutoFill suggestions win when it has any, so this mode probably needs Settings > Apps > Safari > AutoFill > Use Contact Info turned off. Prefill then replaces Apple's contact suggestions instead of competing with them. |
| The field gains a dropdown indicator | A small visual change on the page |

If the spike passes, this gives what the bar lacks today: per-site ranking, every stored value reachable, and no Hide My Email entry crowding the bar. The content script can follow a tap with a fill of the rest of the form.

### ContactProvider

The ContactProvider framework (iOS 18) lets an extension add read-only contacts to the system store, which people can turn off in Settings (SDK, `ContactProvider.swiftinterface:24,91-136`; Doc). Safari's "Other Contact..." screen is a standard `CNContactPickerViewController` (Binary), so provider contacts probably appear there (Unverified). They probably cannot be My Info, so they do not reach the bar (Unverified). This could hold extra identities without cluttering the person's own contacts, but it is optional.

## Recommended build

Run the spikes in [Open tests](#open-tests) first, starting with the datalist one, because its result decides whether Prefill's main UI is Safari's own bar or an in-page list.

Order of work:

1. **Card manager app (SwiftUI).** The person picks their card, grants limited access to it, and sees each field's values as a ranked list. Dragging a value into the top two slots is the main action, because those two are what Safari shows. A per-field preview shows the bar as it will look.
2. **Safari Web Extension for capture.** It captures on submit, queues new values in the App Group and shows a small in-page note ("Saved to your card" or "Open Prefill to add this"). The app drains the queue on launch and asks the person to confirm each value and choose a label. That confirmation also stops one-off values and other people's addresses from being saved.
3. **Context-aware ranking in the extension.** Because the bar has one global order, per-site preferences ("use the work email on this domain") can only be served in the page. The extension can show its own suggestion list under a focused field, using the person's history for that site. This is an in-page UI, not the native bar.
4. **Credential provider text insert** as a backup way to reach any value from the AutoFill menu.
5. Skip the custom keyboard for now, for the reasons above.

## Data model

The app keeps its own store as the source of truth and treats the contact card as an output it writes to.

- **Identity**: name, the linked `CNContact.identifier` of the card it writes to, the container type of that card, and an optional Safari profile UUID.
- **Value**: kind (email, phone or address), the normalized value (case-folded email, E.164 phone, structured address), the display value, a label, its rank within the identity, the `CNLabeledValue.identifier` once written, and use statistics (last used, use count, the sites it was used on).
- **Capture** (in App Group SQLite, written by the extension handler): site host, Safari profile UUID, field kind, raw value, capture time, and a status of queued, saved, dismissed or duplicate.

Rules that follow from the platform facts:

- Write order is the ranked list, so the top two ranks become slots 1 and 2 on the card.
- Before every save, refetch the card and merge, because the last save wins. Listen for `CNContactStoreDidChangeNotification` (`CNContactStore.h:240`), tag saves with `CNSaveRequest.transactionAuthor` (`CNSaveRequest.h:122`, iOS 15) and skip the app's own changes with `CNChangeHistoryFetchRequest.excludedTransactionAuthors` (`CNChangeHistoryFetchRequest.h:75`). This race can be reproduced in the Simulator by editing the card in the Contacts app between the app's fetch and save.
- Remove duplicates by normalized value before adding.
- If the target card is linked, write to one underlying member on purpose, or hand the edit to `CNContactViewController`.

## Open tests

| Test | Settles | Where |
| --- | --- | --- |
| Safari Web Extension stub that injects a `<datalist>` of three emails into the focused field, with Use Contact Info on and then off, on tagged, untagged and phone fields | Whether Prefill can put its own values in Safari's real bar | Simulator, iOS 27.0 |
| Add a submit button and `action` to `testbed/form.html`, type a new email, submit, and watch for any save offer | Whether Safari really never saves contact values | Simulator, iOS 27.0 |
| Probe app: pick the card, grant limited access to it only, append a fourth email, move the third to slot 1, save, log any `CNError` code, then reopen the form with and without relaunching Safari | Limited-access writes, reordering through the API, and how fast Safari notices | Simulator, then device |
| Same probe with full access | Baseline | Simulator |
| Extension stub: log submitted values, send them to the handler, read `CNContactStore.authorizationStatus` in the handler and try a save, then repeat on a fresh install where the app never asked | Whether the handler shares the app's Contacts grant | Simulator |
| Keyboard stub: log `textContentType` and `keyboardType` on each testbed field | Confirms the binary reading on tagged, untagged and phone fields | Simulator |
| Credential provider stub with `ProvidesTextToInsert`, invoked from the field menu on the email field | The exact tap path | Simulator |
| ContactProvider stub, then open "Other Contact..." | Whether provider contacts show there | Simulator |
| Link two local cards in the Simulator's Contacts app and repeat the probe | Partial check of linked-card writes. The local database supports links (`ABPersonLink` table), but this has not been tried. | Simulator |
| Repeat the probe on a physical iPhone signed into iCloud with Gmail contacts on, with a linked My Info card | Which member receives the write, whether order survives sync, and whether the bar matches | Device only |

## What the Simulator can and cannot show

The Simulator has one local contacts store, with no iCloud, CardDAV or Exchange accounts and no linked cards. It is enough for the bar's ordering rule, the extension permission flow (which Apple documents as working there) and the local half of the edit race. It cannot show sync, merging across iCloud and Gmail, read-only container errors, or how Safari resolves My Info when several accounts each hold a pointer. Apple has not said whether the Simulator can sync iCloud Contacts, so assume it cannot. Those questions need one run on a physical iPhone before the card-editing design is final.

## Competitors

| Product | iOS surfaces for contact data | Multiple emails or identities | Whole-form fill on iPhone | Notes and status |
|---|---|---|---|---|
| Apple Safari AutoFill | QuickType bar, AutoFill Contact button, long-press AutoFill > Contact (iOS 17+) | Card can hold several. One is the default, the rest sit behind Customize. Other Contact fills from any card. | Yes | Hide My Email is the only alias mechanism. Apple Passwords stores no identities. Verified with corrections. |
| 1Password | Credential provider (QuickType for logins), text to insert for every item type, Safari Web Extension with an inline picker for identities and cards | Several identity items, listed and searchable. Each identity suggests only its default email, so users create one identity per email (staff, December 2025). | Yes, through the Safari extension | Since 8.12.8 (March 2026) the inline menu is hidden on login forms when 1Password is itself the system AutoFill provider. Users report 4 to 5 taps where there used to be 1. Verified with corrections. |
| Bitwarden | Credential provider (logins, passkeys), long-press text insertion | Disputed. One verifier found text insertion since v2025.1.0 for identity fields (name, email, phone, no address) one at a time; another found it undocumented for cards and identities. | No | Help pages say card and identity autofill exist on browser extensions and Android only. Disputed. |
| Dashlane | Text insertion for logins, emails, phones, addresses, IDs (iOS 18+) | Yes, from the vault | No | No iOS Safari extension. One field per invocation. Verified. |
| Proton Pass | Text insertion; Identity item type | Yes, plus email aliases | No | Safari extension is Mac only. Verified. |
| NordPass | Credential provider; release notes say long-press fill covers password items | Personal Info stored | No | In practice copy and paste for addresses (inferred). Verified. |
| RoboForm | Credential provider; iOS 18 text-field AutoFill since 9.6.6 (item types undocumented) | Rich multi-Identity model | Only in RoboForm's own browser (can be the default browser since 9.9.9) | Its Safari share-sheet extension was discontinued in 2020. Disputed. |
| Keeper | Credential provider (QuickType for logins); long-tap text insertion since 16.11.0 (September 2024) | Not documented for address or card records | No | An earlier "login only" claim was killed in verification. |
| Keyboard fillers (KeyFill, Quick Fill Pro, Auto fill Keyboard) | Custom keyboard panels | Yes (profiles) | No | Single-digit ratings; one last updated in 2019. Verified. |

**The gap.** 1Password already ships the two surfaces Prefill needs (an inline Safari picker and text to insert), so the gap is narrower than "nobody does this". What nobody ships is a contact-first product:

- Many labelled emails, phones and addresses per person, not one per identity item.
- Ranking per site and per field, with memory of which email was used where.
- Visible sources and a Remove action that sticks.
- Capture of new values typed into forms.
- Import and dedupe from the Contacts card and from other managers.
- A QuickType-bar presence in Safari, if the datalist spike works. No competitor does this.

Password managers treat identities as a side feature and optimise for logins. Prefill does not store passwords at all, so it never fights the user's password manager for the provider slot on login forms.


## Field detection and fill techniques

These techniques come from reading Chromium, Firefox, WebKit and Bitwarden source and the WHATWG spec. They were collected in this pass but not individually re-verified, so treat specific constants as "check the source before copying".

### Classification pipeline

| Step | Technique | Source |
|---|---|---|
| 1 | Read the parsed `el.autocomplete` IDL value. If it is a valid field name, confidence is 1.0 and classification stops. Compare with `el.getAttribute('autocomplete')` to tell "absent" from "present but invalid". | WHATWG autofill detail tokens; WebKit `Source/WebCore/html/Autofill.cpp` |
| 2 | Parse the token right to left: field name last, then an optional contact token (home, work, mobile, fax, pager, allowed only before tel, email and impp), then shipping or billing, then `section-*`. Use the contact token to choose which saved email or phone to rank first (`autocomplete="work email"` asks for the work email). | WHATWG |
| 3 | `type=email` means email (confidence 0.95). Never trust `type=tel` alone: Firefox notes HomeDepot and BestBuy use it for ZIP. | Firefox `FormAutofillHeuristics.sys.mjs` |
| 4 | Run ignore patterns first, so "username" never matches name and "address nickname" never matches address. Exclude search, hidden, password, file and checkbox inputs, plus fields matching captcha, search or forgot. | Chromium `*_IGNORED` types in `legacy_regex_patterns.json`; Bitwarden `autofill-constants.ts` |
| 5 | Collect label text in this order: `el.labels` (covers `for=` and wrapping labels, and works inside shadow roots), `aria-labelledby` resolved through `el.getRootNode()`, `aria-label`, placeholder, an overlaying floating-label span, previous-sibling text, then table, `dl`, `li` and fieldset ancestors. Skip script, style and option text. | Chromium `form_autofill_util.cc`; Firefox `LabelUtils.sys.mjs`; Bitwarden `collect-autofill-content.service.ts` |
| 6 | Tokenize `name` and `id` by splitting camelCase and on `_ - [ ]`. Drop tokens shared by most fields in the form (`ctl00`, `billing_`). | Firefox `splitMixedCase`, `_stripSharedTokens` |
| 7 | Match against Chromium's per-type, per-locale regex database. It has 83 types and per-language variants (German `plz`, French `ville`, Japanese and Chinese terms), each with a score, which attributes it applies to, and which control types it applies to. The data is BSD-licensed and can be vendored with attribution. Safari supports lookbehind since 16.4, so the patterns run as-is. | Chromium `components/autofill/core/browser/form_parsing/resources/legacy_regex_patterns.json` |
| 8 | Score = best pattern score times a source weight (name or id 1.0, label 1.0, aria 0.9, placeholder 0.8, nearby text 0.7), minus negative-pattern hits, plus agreement bonuses (maxlength 5 for ZIP, last two select options are country names). Assign the type only when the score is at least 1.0 and the runner-up is below 0.8 times the winner. Otherwise mark the field suggest-only. | Synthesis of Chromium, Firefox and Bitwarden |
| 9 | Resolve conflicts with Chromium's parser priority (Email beats Phone beats Address beats Name). Whole-form fill is allowed only when the form has at least 3 distinct fillable types or the types come from autocomplete attributes. A single confidently classified field still gets suggestions. | Chromium `form_field_parser.cc`, `field_candidates.cc`, `autofill_constants.h` (`kMinRequiredFieldsForHeuristics = 3`) |
| 10 | Apply form-context passes: phone grammars over consecutive fields, address-line ordering (a lone "address" becomes street-address), first-then-last name grouping, and select sniffing (month and year ranges, country lists). | Firefox `FieldScanner.sys.mjs`; Chromium `phone_field_parser.cc` |
| 11 | Split the form into sections: a repeated type starts a new section, except for a confirm-email twin, an adjacent hidden duplicate, phonetic name groups, or a form with only one duplicate. Billing and shipping blocks become separate sections that can take different saved addresses. | Firefox `FormAutofillSection.sys.mjs`; Chromium `form_structure_sectioning_util.cc` |
| 12 | Learn per site. When the user corrects a field, store the correction keyed by site, form signature and field name or id, and let it override heuristics next time. A high "filled then edited" rate for a field type on a site flags a misclassification. | Synthesis; web.dev "Measure autofill" (EMPTY, AUTOFILLED, AUTOFILLED_THEN_MODIFIED, ONLY_MANUAL) |

### Filling values so the page accepts them

| Problem | Technique | Source |
|---|---|---|
| React ignores `el.value = x` | Call the native prototype setter (`Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, v)`; the textarea and select prototypes for those elements), then dispatch bubbling `input` and `change`. Safari content scripts run in an isolated world, where the page's override may already be invisible; use the prototype setter anyway because it works in both cases. | React `inputValueTracking.js` |
| Vue, Angular, validation on blur | Full sequence per field: focus and focusin, setter, input, change, blur and focusout. Never fill during IME composition. | Vue `vModel.ts`; Angular `default_value_accessor.ts` |
| Input masks reject bulk values | Pick the rawest value that fits (national digits for a `(___) ___-____` placeholder). After a frame, read the value back and compare digits. On mismatch, clear and type per character with `beforeinput` and `input` events carrying `inputType: 'insertText'`, or use `document.execCommand('insertText')` on the focused element. | react-input-mask docs; Bitwarden `insert-autofill-content.service.ts` |
| Values longer than the field | Adapt to maxlength: state name becomes its abbreviation, phone keeps the last N digits, ZIP becomes 5 digits, a `street-address` textarea gets lines joined with a newline and a single input gets them joined with ", ". | Chromium `field_filling_util.cc`; Firefox `FormAutofillHandler.sys.mjs` |
| Select options for state and country | Match in tiers: exact value, exact text, collator match with `Intl.Collator` (base sensitivity, ignore punctuation), whole-token match ("NC - North Carolina"), alias tables, then shortest substring. Never take a raw first substring hit ("WV - West Virginia" once matched "virginia"). Build localized country names with `Intl.DisplayNames` and month names with `Intl.DateTimeFormat`. | Chromium `field_filling_util.cc`, codereview 11415221; Firefox `FormAutofillUtils.sys.mjs` |
| Dependent fields | Fill country first. Wait for the state list to change (MutationObserver on the select's options), then fill state and postal code. Refill a field the site cleared shortly after the fill. | Firefox `FormAutofillHandler.sys.mjs` (`select-options-changed`, `refillOnSiteClearingFields`) |
| Split phone, birthday, code boxes | Detect runs of adjacent fields with maxlength 1 to 4 that share a label or name prefix. Fill US phones 3-3-4. Put the country code into a select by matching "+1", "US (+1)" and similar options. | Chromium `phone_field_parser.cc`; WHATWG `tel-*` and `bday-*` tokens; web.dev |
| Phone parsing | Use libphonenumber-js to derive E.164, national and formatted forms. | Firefox ships its own port (`PhoneNumber.sys.mjs`) |

### Finding fields on modern pages

| Problem | Technique | Source |
|---|---|---|
| Shadow DOM | Recursive query per shadow root. On Safari 26 and later, `browser.dom.openOrClosedShadowRoot(el)` reaches closed roots. Enrol each discovered root in its own MutationObserver, because observers do not cross shadow boundaries. Take the real focused input from `event.composedPath()[0]` on a capture-phase `focusin`. | Safari 26 release notes; Bitwarden `dom-query.service.ts` |
| Iframes | Set `all_frames: true`. Each frame classifies its own fields; route fills by `frameId`. Safari does not inject into `about:blank` or `srcdoc` frames (WebKit 263817, still NEW), so the parent reads `iframe.contentDocument` directly. Never push data picked in the top frame into a cross-origin frame unless the user focused that frame or it shares the site (eTLD+1). | Apple Developer Forums 653307; WebKit 263817 |
| SPAs and multi-step flows | Classify lazily on `focusin` and cache per element in a WeakMap. Invalidate on mutations inside the form container (debounced). Detect SPA navigation by comparing `location.href` in the mutation callback. Treat "fetch completed and the tracked fields disappeared" as a submission. | Firefox `FormAutofillHandler`; Bitwarden form-submission-detection docs; Chromium iOS mirror |
| Hidden-field exfiltration | Bulk-fill only fields that pass `el.checkVisibility({checkOpacity: true, checkVisibilityCSS: true})` (Safari 17.4+), are not `aria-hidden`, are not off-screen or covered (check `elementFromPoint` at the centre), are enabled and not read-only, and are in the same section as the focused field. Never fill cards as a side effect of a contact fill. Lin, Ilia and Polakis (CCS 2020) found deceptive hidden fields in at least 5.8% of autofilled forms. | Firefox `FormAutofillUtils.isFieldVisible`; Bitwarden `dom-element-visibility.service.ts`; Polakis et al. |
| Preview and undo | On first tap of a suggestion, tint the fields that will change and show a count. After filling, keep the previous values and offer Undo for a few seconds, restoring exactly what was there. | Chromium `autofill_strings.grdp` (Undo autofill, Clear form); Firefox bugs 1819575 and 1819618 |

Limits we accept: synthetic events have `isTrusted = false`, and a few sites reject them; an extension cannot fix this. Closed custom elements that expose no inner input cannot be filled. Card fields inside payment-provider iframes (Stripe, Braintree, Adyen) are out of scope.


## Appendix A: Simulator recipe

On a fresh Simulator, contact AutoFill stays off until both of these are done with the Simulator shut down:

1. `xcrun simctl spawn <udid> defaults write com.apple.WebUI AutoFillFromAddressBook -bool true`
2. In `data/Library/AddressBook/AddressBook.sqlitedb`, run `update ABStore set MeIdentifier=<ABPerson ROWID> where ROWID=0` and `insert or replace into _SqliteDatabaseProperties(key,value) values('MeSourceID','0')`. Setting `MeIdentifier` without `MeSourceID` did not bring up the AutoFill Contact bar.

After that, My Info can be switched live by updating `MeIdentifier`, then running `xcrun simctl terminate <udid> com.apple.mobilesafari` and `xcrun simctl spawn <udid> launchctl kill SIGKILL system/com.apple.contactsd`, and reopening the page. Import cards with `xcrun simctl addmedia <udid> file.vcf`. This edits a private database and is for testing only.

Test devices used: iOS 27.0 `9E7AF087-87AF-4609-8805-1E114A09B59D` and iOS 26.5 `946DF46C-B43F-4CB5-82E7-B7F2C8D0A084`, both left shut down with all five cards loaded. The first observations used iOS 27.0 `67D26F69-0444-498D-ADEE-F687E565B7CB`.

## Appendix B: Claims killed or corrected in verification

### Killed

| Claim | Correction |
|---|---|
| Keeper on iOS documents autofill for passwords, TOTP and passkeys only. | Keeper 16.11.0 (September 2024) added long-tap fill from any Keeper record on iOS 18. Whether address and card fields are covered is not stated. QuickType support remains logins only. |

### Disputed or corrected

| Original claim | Correction |
|---|---|
| Bitwarden has no card or identity autofill on iOS. | Disputed. One verifier found iOS text insertion since v2025.1.0 for card and identity fields (no address), one at a time; another found it undocumented. Bitwarden has no whole-form card or identity fill and no QuickType presence for those items. |
| RoboForm form fill never happened in Safari on iOS. | v4.2.0 (2016) filled identities through a legacy Safari extension, discontinued in 2020. RoboForm added iOS 18 text-field AutoFill in 9.6.6 (item types undocumented). Whole-form identity fill is in its own browser. |
| All `ASCredentialProviderExtensionCapabilities` keys are iOS 17.0+. | ProvidesPasswords, ProvidesPasskeys and ShowsConfigurationUI are 17.0. ProvidesOneTimeCodes, ProvidesTextToInsert and SupportsConditionalPasskeyRegistration are 18.0. SupportsSavePasswordCredentials and SupportsGeneratePasswordCredentials are 26.2. |
| Apple docs list ProvidesTextToInsert as 17.0, contradicting the headers. | No contradiction. The key page says 18.0; 17.0 belongs to the parent dictionary. |
| Text to insert is the only sanctioned third-party route into Safari forms. | A Safari Web Extension (1Password) and a custom keyboard are also sanctioned. Text to insert is the only one that uses the system AutoFill menu. |
| A text-to-insert provider can retry automatically after a failed insert. | `completeRequestWithTextToInsert:` reports only `expired`, not success. Retry has to be manual. |
| BrowserEngineKit lets a browser push `BEAutoFillTextSuggestion` objects with contact values; EU only. | `BEAutoFillTextSuggestion` cannot be constructed (init is unavailable, contents read-only). A browser can push plain `BETextSuggestion` strings only. The entitlement covers the EU and, since iOS 26.2, Japan. |
| `UIPhotoSearchSuggestion` is iOS 18.4. | It is iOS 27.0. |
| Safari Web Extensions never run in in-app WKWebViews. | Safari-installed extensions do not. An app can host its own extensions in its own WKWebView through `WKWebExtensionController` (iOS 18.4). |
| WWDC26 introduced `safari-web-extension-packager` and App Store Connect packaging. | Session 216 presents them as existing tools. The Swift name of the state call is `stateOfExtension(withIdentifier:)`. |
| A content-script injection failure was reported on iOS 17.4.1 in forum thread 684128. | That thread covers iOS 15.x only. No source was found for 17.4.1. |
| `autofillScriptingEnabled` (iOS 27) lets scripts trigger the system AutoFill UI. | It exposes autofill-related DOM capabilities to the app's own script (marking fields autofilled, showing the in-field AutoFill button, trusted events). It does not reach the QuickType bar and only applies to the app's own WKWebView. |
| Safari contact AutoFill reads only the My Info card. | Other Contact fills from any card, users report suggestions from other contacts, and stale values suggest a second hidden store. |
| Apple fills only one value from a card with several. | Several are stored and reachable through AutoFill Contact > Customize (iOS 18.4 report); one is the default and the rest are buried. |
| Hide My Email is Apple's only multi-email mechanism. | Overstated. The card can hold several emails; whether QuickType lists them is unverified (spike S2). |
| 1Password hides its inline menu whenever system AutoFill is on, to stop a save-password loop. | Only when 1Password is itself the AutoFill provider (8.12.8), and staff gave conflicting experiences as the reason. |
| Apple Community thread 253850543 shows there is no default email for form AutoFill. | That thread is about Mail recipient autocomplete. It is weak evidence for form AutoFill. |
| Credential Exchange can import addresses and names from Apple Passwords. | Apple Passwords exports only logins, passkeys and codes. Apple's overview lists only password, passkey, TOTP, note and card as currently supported, so address and name imports depend on the other manager. |
| UILexicon contains only contact names and Text Replacement shortcuts. | It also includes a common-words lexicon. |
| `UITextDocumentProxy` inherits `UITextInputTraits` directly. | It gets traits through `UIKeyInput`. |
| All `CreditCard*` content types are iOS 17.0. | `UITextContentTypeCreditCardNumber` is iOS 10.0; the rest and `Birthdate*` are 17.0. |
| The iOS Simulator may skip the extension's website-access prompt. | Unsourced. Apple's Tech Talk shows the simulator prompting "Allow For One Day". |
| WWDC18 721 says simulator QuickType credential suggestions fail when the keychain is empty. | The session says only that provider suggestions need matching identities in `ASCredentialIdentityStore`, on any platform. |
| Associated Domains password AutoFill does not work in the simulator (rowel PR 536). | The PR does not say this. Unsourced. |
| The "AutoFill Unavailable" report is in threads 762705 and 776124. | It is in thread 770824, from a developer, not Apple staff. |
| The `mn.` keyboard bundle-prefix gotcha comes from Daniel Saidi's post. | It comes from Developer Forums thread 121542; the post covers only `se.`. |
| Every simulator has the `AppleKeyboards` preference set. | Only the 26.5 iPhone 17 Pro (FDE2931D) has it. |
| All simulators are shut down. | The iOS 27.0 iPhone 18 Pro is booted. 26.5 also has an iPhone 17 Pro Max and iPads. |
| The 27.1 UIKit header changes are limited to hinge and arrangement files. | 27.1 also adds `UIViewReservedRegion.h` and modifies several view, scene and navigation headers. None relate to AutoFill. |
| HTTPS is needed if iOS 27 warns on plain-HTTP localhost. | In iOS 27 the "Not Secure Connection Warning" is an opt-in toggle, so plain HTTP localhost works by default. |
| Both the app and the extension need the credential-provider entitlement. | Xcode's template puts it on the extension only; adding it to both is common practice, not a documented requirement. |
| Dashlane may have an iOS Safari extension. | It does not; its browser extension is desktop only. |
