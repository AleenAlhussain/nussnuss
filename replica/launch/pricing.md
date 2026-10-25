# Pricing — NussNuss

## What others charge (read 2026-10-23)

| app | model | price | source |
|---|---|---|---|
| Splitwise | free with a 3–5 expenses/day cap + wait screen; Pro subscription | Pro $5/month or $40/year (US, Dec 2023); App Store lists Pro IAPs from $2.99 to $39.99 | [IT Voice](https://www.itvoice.in/splitwise-has-introduced-restrictions-on-the-number-of-free-expenses-users-can-add), [App Store](https://apps.apple.com/app/id458023433) |
| Splitser | free, no caps | free | [splitser.com](https://splitser.com/splitwise-switch-service) |

What reviewers said about price (from `feedback.md`): 8 reviews across 3 sources call the
subscription too expensive for casual use; one asks for a one-time purchase instead.

## Our model

| tier | price | who it's for | what |
|---|---|---|---|
| **Free** | 0 | everyone | unlimited groups and expenses, all 4 split modes, settle up, WhatsApp share, link view, Arabic/English, offline. **No ads, ever.** |
| **Plus** | **one-time $4.99** (App Store/Play price tier; ≈ AED 18.99 / SAR 18.99) | people who travel abroad or keep records | mixed currencies with rates, CSV export, colour themes, all future Plus features |

No subscription. Nothing the reviews complained about is behind the paywall.

Products to create (the owner does this in each store, then links them in RevenueCat):
- App Store Connect → In-App Purchases → **Non-Consumable**, product id `nussnuss_plus_lifetime`
- Google Play Console → Monetize → **In-app products** (one-time), product id `nussnuss_plus_lifetime`
- RevenueCat → entitlement `plus` → attach both products → current offering with one package

## What a sale is worth (honest maths)

| | per $4.99 sale |
|---|---|
| Apple, Small Business Program (under $1M proceeds a year) | keeps 15% → ≈ $4.24 |
| Google Play | 15% in most countries; in the US, UK and EEA the 2026 fee table is 20–25% + 5% billing for one-time purchases ([Google](https://support.google.com/googleplay/android-developer/answer/112622?hl=en)) |
| RevenueCat | free under $2,500 monthly tracked revenue, then 1% |
| VAT / sales tax | included in store prices in many countries, so proceeds are lower there |

Rough net: **$3.50–$4.20 per Plus sale.** $1,000,000 of net revenue would take roughly
**240,000–285,000 Plus sales**; at a 3–5% purchase rate that is about **5–9 million installs**.
That is what "a million-dollar app" means in practice. It is possible for a viral, useful app, and
nobody can promise it. The plan is built so costs stay near zero while it grows (no servers).

## Later, if growth needs it

- Plus price test: $3.99 vs $6.99 in different storefronts.
- "Plus for the whole group" pack (one buyer unlocks 4 friends) — viral by design.
- Never: daily caps, ads, or paywalling the core split.
