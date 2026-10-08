# Watching people apply with Prefill

The held-out score (`docs/ACCURACY.md`) says how often Fill form is right on forms nobody tuned for. It can't say whether Prefill saves a real person time once they review and fix its answers, or whether they trust it. This guide is for watching 5 to 10 people do that.

## Who

People who apply to many things: students applying to internships, fellowships and accelerators, and people signing up for events. Five sessions find most problems; stop at ten. Mix iPhone and Mac users, and include at least two who have never seen Prefill.

## Before the session

- Pick three real, open forms the person would plausibly fill: two job applications on different systems (say Greenhouse and Lever) and one non-job form (Luma, Tally or Airtable). Avoid forms in the held-out set, and never submit on the person's behalf: they decide whether to submit, or stop at the last page.
- Have them use their own device and their own details. Don't record their values; record only what happened to each field.
- Prepare a stopwatch and the results table below. A screen recording helps if the person agrees to it.

## Tasks

1. **Setup without help.** Hand over the device with Prefill installed but not set up. Say "Set up Prefill so it can fill your applications" and nothing else. Note every point where they stall for more than 10 seconds, and whether they finish. Help only after 3 minutes, and mark the session as helped.
2. **First application.** "Apply to this job the way you normally would. Prefill is there if you want it." Don't point at the pill. Time from the first click in the form to the moment they say they're ready to submit, including reading and fixing what Prefill filled.
3. **Second application.** A different job on another system. This is the one that shows reuse: the answers they typed or fixed in the first should now be offered. Time it the same way.
4. **Device switch.** Start the third form on the other device (Mac if they used the iPhone, or the reverse). Note whether answers saved on the first device show up, and how long they take to.
5. **Undo.** On any form, ask them to fill with Prefill and then take it all back. Note whether they find Undo without help, and whether every field went back.

## What to record

- **Time per form**, from first click to "ready to submit", including review and correction. Also time one form filled by hand, without Prefill, as the baseline.
- **Per field Prefill filled:** right (kept as is), wrong (the person changed it), or wrong and not noticed (you saw it was wrong and they didn't; tell them after the session, never during).
- **Per field Prefill left empty:** missing (the person typed something Prefill had saved, or should have had), or rightly left (an essay, a consent box, a question they had never answered).
- **Second-application reuse:** of the answers they typed in the first form, how many were offered or filled in the second.
- **Trust:** did they read every filled field, skim, or not look? One line on what they said about it.
- **Stalls and quotes:** anything they said out loud, word for word, especially "where", "why did it" and "I didn't expect".

Wrong and not noticed is the most important number. It is the cost of a confident mistake.

## Results

Copy this table once per session.

| Session | Device | Setup unaided? | Form | Time with Prefill | Time by hand | Right | Wrong (fixed) | Wrong (not noticed) | Missing | Rightly left | Reused from form 1 | Undo found? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P1 | iPhone | Yes / Helped at step | Greenhouse | m:ss | m:ss | | | | | | n of m | Yes / No |
| P1 | iPhone | | Lever | m:ss | | | | | | | | |
| P1 | Mac | | Luma | m:ss | | | | | | | | |

Then one summary row across sessions:

| Sessions | Median time saved per form | Wrong per form | Wrong not noticed, total | Missing per form | Reuse rate | Set up unaided | Found Undo |
|---|---|---|---|---|---|---|---|
| | | | | | | n of N | n of N |

## After the sessions

- Every wrong answer becomes a test: save the form's markup (see `docs/ACCURACY.md`, "Add a form") into `web/src/fixtures/` before fixing it.
- Setup stalls go to the onboarding screens; Undo misses go to the Fill form pill.
- Put the summary row and the date in `AGENTS.md` (Ongoing), next to the held-out score.
