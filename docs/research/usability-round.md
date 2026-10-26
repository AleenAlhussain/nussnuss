# Usability round: script and measures

Phase 0 of the UI/UX plan ("listen first"). Run it before a release that changes structure, then again at every phase gate. Five people per round find most of the problems in a flow; mix English and Arabic speakers, iPhone and Android, on their own phones.

The numbers this round collects are the baseline for the targets in the plan. They are proposals until the first round sets them.

## Before the session

- Recruit five people who split costs at least once a month (a trip, a flat, family dinners). Not colleagues on the project.
- Ask for consent to take notes and, if they agree, to record the screen (not their face). Say they can stop at any time and that we are testing the app, not them.
- Prepare a test server with a fresh database and turn on task timings: start the API with `TIMINGS=log`. Each timing is one line in the server log; `node scripts/timings-report.mjs < api.log` prints the medians.
- Install the preview build (Android APK from the `v2-preview` release; iPhone through TestFlight once the owner has set it up) or use the web app on their phone.
- Seed one shared group the participant will join by link: "Salalah trip", AED, with Sara and Omar and three expenses.

## The five jobs

Read each task aloud, then stay quiet. If they are stuck for two minutes, note it as a fail and move on. Don't explain the interface.

| # | Task (say this) | Success when | Timing event |
|---|---|---|---|
| 1 | "You just paid 45 dirhams for lunch for the three of you. Add it." | The expense is saved, split three ways | `add_expense` (+ to Save) |
| 2 | "Omar only had a coffee, so split the 60 dirham dinner so he pays less." | Saved with Shares, Amounts or Percent, Omar's share is smaller | `uneven_split` (Unequally to Save) |
| 3 | "Sara paid you back what she owed. Record it." | A payment from Sara is recorded in the group or with Settle everything | `settle` (Settle up or the person open to Mark as paid) |
| 4 | "Invite a friend to this group." | The link or QR code is shared or copied | `invite` (invite sheet open to share or copy) |
| 5 | "Close the app and open it again. How much do you get back overall?" | They say the overall balance aloud | `find_balance` (app start to Home with the balance) |

After each task, ask: "How easy was that, from 1 (very hard) to 5 (very easy)?" and "Was anything surprising?"

## What to write down

For every task: success or fail, seconds (from the timing log, or a stopwatch on the web), the path they took, every hesitation over a word, and quotes. Use the same sheet for every person.

| Person | Lang / phone | Task | Pass | Seconds | Ease 1–5 | Where they hesitated | Quote |
|---|---|---|---|---|---|---|---|
| P1 | | 1 | | | | | |

## After the round

- A problem two or more people hit is a finding: add it to the inspection document with the screen, the standard it breaks and a fix.
- Compare with the targets: add an expense in 8 seconds or less (median), 90% unaided success on the five jobs, and saying the overall balance in under 5 seconds for 5 of 5 people.
- Keep the raw sheets out of the repository; they may name real people.

## Questions in Arabic

١. "دفعت ٤٥ درهم غداء لكم الثلاثة. سجّلها."
٢. "عمر أخذ قهوة بس، قسّم العشاء ٦٠ درهم بحيث يدفع أقل."
٣. "سارة رجّعت لك اللي عليها. سجّل الدفعة."
٤. "ادعُ صاحبك للمجموعة."
٥. "سكّر التطبيق وافتحه من جديد. كم لك بالمجمل؟"
