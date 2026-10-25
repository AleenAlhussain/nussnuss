# Fixes and angle — NussNuss (نص نص)

Reference app studied: Splitwise (bill splitting, 10M+ Google Play installs, 4.0★ on both stores,
"tens of millions" of registered users, raised a $20M Series A in 2021).
Sample: **39 linked review rows from 5 sources** (Trustpilot ×2 locales, App Store, Google Play,
press, a competitor's switch page), collected 2026-10-23. Trustpilot overall: 2.0 from 72 reviews.
Raw rows: `reviews.csv`. Ranking: `feedback.md`. Quotes are verbatim; rows marked
"paraphrase" are not quotes and are never presented as quotes.

This is a sample of what was readable through public pages, not a census. Themes marked THIN
have too little evidence on their own to call a trend.

## 1. What they hate

| # | problem | reviews | sources | evidence |
|---|---|---|---|---|
| H1 | Daily cap of 3–5 expenses for free users, plus a 10-second wait screen between entries | 17 | 5 | "limit to 3 expenses per day which renders the app useless" ([Trustpilot](https://ca.trustpilot.com/review/splitwise.com?page=3)); "there are daily limits and wait screens to input your expenses" ([Google Play, Aug 2026](https://play.google.com/store/apps/details?id=com.Splitwise.SplitwiseMobile&hl=en_US)) |
| H2 | Subscription price feels too high for casual use; one-time purchase requested | 8 | 3 | "The monthly fee they are asking is way to high for normal casual users." ([App Store](https://apps.apple.com/us/app/splitwise/id458023433?see-all=reviews)) |
| H3 | Timed ads and upsell prompts while adding expenses | 6 | 2 | "each time I wanted to add an expense I had to wait for ad to play" ([App Store](https://apps.apple.com/us/app/splitwise/id458023433?see-all=reviews)) |
| H4 | Changes shipped with no warning (THIN as its own theme, but present in several H1 reviews) | 2 | 1 | "Zero communication about new daily limit" ([Trustpilot](https://ie.trustpilot.com/review/splitwise.com?page=2)) |

## 2. What is missing

| # | request | reviews | sources | evidence |
|---|---|---|---|---|
| M1 | Split without everyone signing up / sharing phone numbers | 2 (THIN) | 2 | "not interested in joining Splitwise just to do math" ([App Store](https://apps.apple.com/us/app/splitwise/id458023433?see-all=reviews)) |
| M2 | Custom percentages / flexible split | 4 | 2 | "items could be split by a custom % instead of only 50/50 or 100/0." ([App Store](https://apps.apple.com/us/app/splitwise/id458023433?see-all=reviews)) |
| M3 | Currency conversion without paying a subscription | 1 (THIN) | 1 | App Store reviewer says requests can't be converted without Pro (paraphrase) |
| M4 | Save drafts | 1 (THIN) | 1 | "there’s no way to save a draft, your progress, nothing." ([App Store](https://apps.apple.com/us/app/splitwise/id458023433?see-all=reviews)) |

## 3. What is unsolved

| # | group or job | evidence |
|---|---|---|
| U1 | **Arabic speakers.** The App Store listing names 12 languages; Arabic is not one of them. Gulf currencies with 3 decimals (KWD, BHD, OMR) need correct handling. | [App Store listing](https://apps.apple.com/app/id458023433), read 2026-10-23 |
| U2 | **Settling up and agreeing on the numbers.** Reviews say settling is the weak part and that different people saw different balances. | "Not Good for "Settling" Amounts Owed" ([Trustpilot](https://ca.trustpilot.com/review/splitwise.com?page=3)); dispute review (paraphrase) |
| U3 | **Occasional users** (one trip, one dinner) — the people the daily cap hurts most, and who will never pay monthly. | H1 + H2 |

## 4. Fix plan

| fix | what we build | size | skill | evidence |
|---|---|---|---|---|
| F1 | **No limits, no ads, no wait screens.** Unlimited expenses and groups free forever. Stated in the listing and onboarding. | S | build | H1, H3 |
| F2 | **One-time "Plus" unlock** instead of a subscription. Core stays free. | S | backend, launch | H2 |
| F3 | **No sign-up for anyone.** Data lives on the phone. Friends are just names. Share a group with a link; friends open it in the browser without installing anything. | M | build | M1 |
| F4 | **Arabic and English with full right-to-left layout**, switchable inside the app; 3-decimal Gulf currencies. | M | build, design | U1 |
| F5 | **Settle-up plan everyone can see**: fewest transfers, one tap to mark paid, a shareable summary for the WhatsApp group so nobody argues about the numbers. | M | build | U2 |
| F6 | **Every split type free**: equally, exact amounts, percentages, shares. | S | build | M2 |
| F7 | **Works offline** — nothing needs a network. | S (by design) | architect | U3 |
| F8 | **Drafts kept** — the add-expense form remembers what you typed. | S | build | M4 |

## 5. The angle

Option A (recommended):
> For friends, roommates and travellers who were blocked by daily limits, wait screens and
> subscriptions, **NussNuss** splits any bill with no limits, no ads and no sign-up — in Arabic
> and English, even offline. Evidence: daily limit/cooldown, 17 reviews across 5 sources.

Option B:
> For groups who argue about who owes what, NussNuss shows one settle-up plan everyone can open
> from a link. Evidence: U2 (thin on its own; strong as a secondary message).

Option C:
> For Arabic speakers, the first bill splitter that speaks your language and your currency.
> Evidence: U1 (a gap, not a complaint — strong for the Gulf launch, too narrow globally).

**Pick A as the headline, C as the regional launch message (Gulf / MENA), B as the feature story.**
The reference app's name stays out of our app name, listing, keywords and ads.
