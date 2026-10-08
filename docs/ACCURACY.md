# Measuring accuracy

Prefill's fixtures in `web/src/fixtures/` are the pages its rules were written against, so passing them says little about the next form. The held-out set in `web/src/fixtures/heldout/` is the opposite: real forms saved from the web that no rule was ever tuned on. Scoring Fill form on them tells you how often Prefill puts the right answer in a field it hasn't seen before.

## Run it

```bash
pnpm --dir web run score
```

The scorer (`web/src/heldout.test.ts`) loads each saved form, runs Fill form on the whole page with a stand-in app that answers as the test person, and compares every field with what a careful person would have put there. It prints one row per form and then each wrong or missing field:

```
form                       right   wrong missing    left
greenhouse-figma              13       0       2       4
...
wrong    lever-palantir: cards[...][field2] (want needYou, got "Alex Rivera")
```

It runs with `pnpm --dir web test` too. A low score never fails the build, since it's a measurement. Filling a sensitive field (a password, a captcha, anything the expectations mark `"sensitive": true`, or any field `classify` calls sensitive) fails it. So does a demographic question (one the expectations mark `decline`, or a list or button group whose question is demographic) that gets anything but a declining option or "No".

## What the four numbers mean

| Outcome | Meaning |
|---|---|
| right | The field holds an answer the person would accept, or a demographic question was declined. |
| wrong | The field holds something the person would have to fix: the wrong value, a value in a field that should have stayed empty, or a value in a field no expectation lists. |
| missing | The person has an answer for the field, and Fill form left it empty. |
| left | The field should stay empty, and it did: no saved answer ("need you"), a consent or legal box, a sign-in field. |

Wrong is the number that matters most. A missing answer costs the person one tap; a wrong one costs them noticing it, and many won't.

## The test person

`web/src/fixtures/heldout/alex.json` is Alex Rivera, the same made-up person as `testbed/alex-rivera.vcf` and PrefillKit's `Fixtures.swift`: three emails, two phones, two addresses, plus the links and job answers a student who has applied before would have saved (school, degree, major, graduation date, work authorization, sponsorship, pronouns, preferred name, current company). There is no "How did you hear about us" answer on purpose: the right answer changes with every site.

The stand-in app (`web/src/heldoutHost.ts`) answers the way the message routers do: every email, phone and address in the card's order, every link, and custom answers chosen by the same word rule as `CustomFieldMatcher`. It leaves out answer scopes, model guesses, pins and per-site usage, so the score is for a first visit to a site.

## Expectations

Each form is two files with the same name: the saved page (`greenhouse-figma.html`) and its expectations (`greenhouse-figma.json`):

```json
{
  "source": "https://job-boards.greenhouse.io/figma/jobs/6178851004",
  "fields": [
    { "field": { "id": "first_name" }, "want": "fill", "accept": ["Alex"] },
    { "field": { "id": "gender" }, "want": "decline", "options": ["Male", "Female", "Decline To Self Identify"] },
    { "field": { "name": "consent[marketing]" }, "want": "leave", "note": "marketing consent" },
    { "field": { "label": "Why do you want to join" }, "want": "needYou" }
  ]
}
```

- `field` finds the field by `id`, by `name` (a radio or checkbox group shares one), by the start of its question (`label`), or, for radio buttons without a name, by the buttons' own labels in order (`radios`).
- `want` is `fill` (one of `accept` belongs there), `decline` (a demographic question, answered with the option that declines, or "No"), `leave` (Prefill must not touch it) or `needYou` (the person has no saved answer, so it should stay empty for them).
- `accept` lists every answer the person would be happy with. A link may be compared without its `https://`; a phone matches on its digits.
- `options` gives a searchable dropdown's choices. Greenhouse and Ashby load them only when the box opens, so the saved page has none; the scorer opens a stand-in list with these options (`web/src/heldoutCombobox.ts`).
- `sensitive: true` marks a field that must never be filled.
- List every visible field. Anything Prefill fills that isn't listed counts as wrong.

Write the expectations from the person's side, before you run the scorer on the new form, and don't change them afterwards to match what Prefill did.

## Add a form

1. Pick a real, public form that is different from every fixture: another company on the same applicant tracking system counts, the same posting saved twice doesn't. Good sources: job applications Tarun meets (Greenhouse, Lever, Ashby, Workable, Meta), event sign-ups (Luma, Partiful's web form), fellowship and accelerator forms (Tally, Typeform, Airtable, Jotform, Google Forms), and booking pages.
2. Open it in a browser and let it render. Paste this in the console to copy the form without scripts, styles or classes, with hidden parts marked:

   ```js
   const root = document.querySelector("form") ?? document.body;
   for (const el of root.querySelectorAll("*")) if (getComputedStyle(el).display === "none") el.dataset.hid = "1";
   const clone = root.cloneNode(true);
   clone.querySelectorAll("script,style,svg,img,noscript,iframe,link,meta").forEach((n) => n.remove());
   const keep = /^(id|name|type|for|role|autocomplete|value|placeholder|required|multiple|maxlength|aria-.*|data-qa|selected|checked|disabled|readonly|hidden|contenteditable|tabindex|inputmode|data-hid)$/;
   for (const el of [clone, ...clone.querySelectorAll("*")]) {
     for (const a of [...el.attributes]) if (!keep.test(a.name)) el.removeAttribute(a.name);
     if (el.dataset.hid) { el.removeAttribute("data-hid"); el.setAttribute("style", "display: none"); }
   }
   copy(clone.outerHTML);
   ```

3. Save it as `web/src/fixtures/heldout/<system>-<organization>.html` with a header comment: the source URL, the posting or event name, the date, and anything you cut. Cut long paragraphs and very long option lists, and keep the options Alex would pick.
4. Check it holds no one's personal data: no filled values, no names or emails other than the organization's own placeholders. Replace any other email address with `[email removed]`.
5. Write `<name>.json` as above.
6. Run `pnpm --dir web run score`, and put the new totals in `AGENTS.md` (Ongoing) and the PLAN note for 13.6.

## Rules

- **Never tune rules against the held-out set.** Don't read its failures and then adjust a regex until they pass. The set only stays honest while no rule has seen it.
- **When a held-out form shows a bug:** copy the form to `web/src/fixtures/` (as a regular fixture, with its case in `atsFixtures.test.ts` or a test of its own) before fixing anything, fix the bug against that copy, then remove the form from `heldout/` and add a new one in its place. The held-out set keeps its size, and every form in it stays unseen.
- Keep 8 to 12 forms, spread across applicant tracking systems and form builders, so one system's markup doesn't decide the score.
- The numbers go in `AGENTS.md` with the date, so a change in accuracy can be traced to a commit.

## What the score doesn't cover

- It scores Fill form, not the list under a clicked field. A person who clicks and picks sees the same values, but chooses for themselves.
- The test DOM (happy-dom) does no layout, so every field counts as on screen unless the page hid it. Like browsers, it doesn't enforce `maxlength` on a value set by script.
- Searchable dropdowns run against the stand-in list, not the page's own script. A box that calls itself a combobox but has no `options` in the expectations (a phone box with a country picker) is read by its typed value.
- A list that starts on a real option (no placeholder) counts as empty until Prefill changes it.
- The stand-in app has no answer scopes, so a question about another country's work rules still gets the saved answer here.
- Not in the set yet: a Google Form (the two public ones found needed sign-in or had closed) and a Google Calendar booking page (its form appears only after picking a time slot).
