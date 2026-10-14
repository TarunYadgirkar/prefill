# Prefill with a paid Apple Developer account

Oct 14. What the paid team unlocks, what changes, ranked by how much it helps the job hunt. This replaces PLAN Phase 14's two lines.

## What's true today because of the free team

| Today | Why | Cost to the job hunt |
|---|---|---|
| The iPhone build expires every 7 days; a daily launchd job reinstalls it | free-team profiles last 7 days | the phone stops filling until the Mac and phone meet over USB |
| Sent applications reach the Mac only over USB (`sync-applications.sh`) | no iCloud for the free team | the Mac's list and the Google Sheet lag the phone by up to a day |
| Answers and links sync through iCloud Contacts, on a second "Prefill · Name" card | Contacts was the only free cloud | labels are squeezed into contact fields; picks, usage and the inbox don't sync at all |
| The iPhone's shared store is a Keychain item | no App Groups | 4 KB-ish snapshot limits, extra code |
| No long-press AutoFill in other apps | Apple refuses the credential-provider entitlement to free teams | the keyboard is the only fallback outside Safari |
| No Safari extension on the Mac | a Mac Safari extension needs a signed, distributed app | Safari on the Mac gets only the Accessibility panel |

## Plan, ranked

### 1. Sign with the paid team (needs Tarun, then small)
- Personal builds use the paid team ID. Development profiles last a year, so the daily reinstall job and its USB dependency go away (keep `install-device.sh`).
- Turn on the App Group for the iPhone build; `StoreFactory` already prefers it over the Keychain.
- The Mac app gets a provisioning profile, which CloudKit needs.
- Keep `.dev` bundle IDs for the development build so the App Store IDs stay free.

### 2. Sent applications over iCloud (CloudKit), in place of USB — **building now**
- One private-database zone, `Applications`. One record per application (its id), the JSON in an encrypted field.
- Both apps push what lands in their archive and pull what the other sent, with `CKSyncEngine`. The archive's merge by id already combines records.
- Code lives only in the two apps (`AppCloud/`), never in PrefillKit's keyboard path: the keyboard keeps no network code. PrefillKit gets only the record mapping.
- "Delete Prefill data" deletes the zone too, on either device, and the other device drops its copy when it sees the zone go.
- The Google Sheet stays as is; it now gets the phone's applications through the Mac within seconds.
- Off until the paid team signs the build (a build setting), so nothing breaks before step 1.

### 3. Answers, picks, usage and the inbox on CloudKit (PLAN 14.1)
- Custom fields, links and drafts move off the Prefill contact into CloudKit records with real labels, scopes and history.
- The Me card stays the only thing Safari's bar reads; the Prefill contact becomes an import/export.
- Picks and usage sync, so a pick on the Mac reorders the phone's list.
- Bigger and riskier (never-drop rules); goes after 2 proves CloudKit works on both devices.

### 4. Long-press AutoFill on the iPhone (PLAN 14.2)
- Retry the credential-provider text insertion route from `spikes/textinsert` with the paid entitlement. If Apple grants it, saved values appear in AutoFill in every app, with field context, and the keyboard becomes the fallback.

### 5. Safari on the Mac
- Ship the existing web extension as a Mac Safari Web Extension inside the Mac app, so Safari on the Mac gets the same list and Fill form as Chrome.

### 6. Distribution (optional)
- TestFlight for the iPhone and Developer ID notarization for the Mac, only if anyone else will use Prefill. For Tarun alone, year-long development profiles are enough.

## What Tarun needs to do (only these)
1. In Xcode, Settings, Accounts: sign in with the paid account and check the team shows "Apple Developer Program". Send the team ID (10 characters, in developer.apple.com, Membership).
2. Developer portal, Identifiers: when Claude asks, allow Xcode to register the iCloud container `iCloud.com.tarunyadgirkar.prefill` (Automatic signing usually does this itself).
3. Plug in and unlock the iPhone for the first paid-team install.
