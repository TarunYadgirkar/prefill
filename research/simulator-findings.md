# What iOS 27.0 Safari AutoFill actually does

First raw observation log. REPORT.md is the reference and corrects two conclusions that were here.

Observed 2026-09-30 on an iPhone 17 Pro simulator (iOS 27.0, build 24A434) with a test card that has three emails (home, work, unlabeled), two phones (mobile, work) and two addresses, set as My Info in Settings > Apps > Safari > AutoFill. Test page: `testbed/form.html`.

| Situation | What the QuickType bar or sheet showed |
| --- | --- |
| Focus an `autocomplete="email"` field | Two suggestions side by side: the home email and the work email, each with its label above it. The unlabeled third email did not appear. |
| Type `alex.s` in that field | The bar narrowed to the one matching email, the unlabeled school address, labeled "email". |
| Tap "AutoFill Contact" in the bar above the keyboard | A sheet listed all three emails (labels appended), then Customize..., Other Contact..., Cancel. Picking one filled only the email field and moved focus to Phone. |
| Focus the phone field | Two suggestions: mobile and work. |
| Focus an untagged field labeled "Your e-mail" (`name="usr_contact"`, no autocomplete) | Safari still recognized it as an email field and offered the same two emails. |

Conclusions for the build:

- Safari already offers several values per field from My Card and finds the rest when you type a prefix.
- This first run could not tell why home and work won, because the missing school email was also the only unlabeled one and the only one without `pref`. Later runs with controlled cards (REPORT.md, "Which values the bar offers") showed position on the card is the rule: an empty field shows slots 1 and 2 whatever their labels.
- Whether Safari ever offers to save a typed value was not tested here, because `form.html` had no submit button. Apple's documentation describes no save path for contact info, so it is likely but unobserved.
- "Other Contact..." fills from any contact, so separate identities (work, family member) can be separate cards.
- Therefore the native way to make the bar better is to manage the card: put the right values on it, label them, and keep the most useful one first.
