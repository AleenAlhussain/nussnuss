# Parity report — 2026-10-23

`python3 replica/tools/parity.py replica/features.csv`

- **Feature parity: 98%** (41/42 weighted, must ×3, should ×2, could ×1)
- **Must-haves: 10/10 done**
- **Our fixes and additions: 11/11 done** (no limits, no ads, no sign-up, link sharing, Arabic RTL,
  3-decimal currencies, settle-up summary, drafts, one-time Plus, themes, demo trip)
- Skipped on purpose (6): push notifications, cloud sync, comments, recurring bills, receipt OCR,
  in-app bank payments — v2 or regulated
- Missing / partial: editing an expense's date (partial: recorded and shown)
- Open bugs: S1 0, S2 0 (`bugs.md`)
- **Verdict: better than the original** on the jobs the reviews complained about.

## Layout diff

Not run. No screenshots of the reference app were saved (no account was used, and its store
images are its own). The goal is not to look like it — its look is its trade dress — and our
screens were reviewed on their own (`clone-screens/`).

## Behaviour diff

| flow | reference does | NussNuss does | keep / fix |
|---|---|---|---|
| first use | account sign-up for you, and friends need accounts / phone numbers (reviews) | type your name, done; friends need nothing | keep |
| add an expense | free users capped at 3–5 a day, wait screen between entries (reviews, Aug 2026) | unlimited, no waits | keep — the headline |
| split by % | listing says yes; one reviewer wanted custom % | all 4 modes free, live "left" counter | keep |
| who owes whom | simplify debts | fewest-transfers plan + one-tap "mark paid" with undo | keep |
| share with friends | friends must join | WhatsApp summary + link that opens in any browser | keep |
| currency | conversion is Pro (subscription) | conversion is Plus (one-time) | keep |
| language | 12 languages, no Arabic | Arabic + English, instant switch | add more languages later (Urdu, Hindi, French, Turkish) |
| offline | listing says offline entry | fully offline, nothing needs a network | keep |
| multi-device sync | yes | no (v2) | **next**: the biggest gap for roommates who all add expenses |

## Top five to build next

1. Live sync between friends' phones (Supabase, `schema.sql` ready) — keep free and unlimited.
2. Edit the date of an expense.
3. Receipt photo on an expense (Plus).
4. Recurring bills for roommates (rent, internet) (Plus).
5. More languages: Urdu, Hindi, French, Turkish, Indonesian — big Gulf expat groups.
