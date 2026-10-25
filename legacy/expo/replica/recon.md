# Recon map — bill splitting (reference: Splitwise core loop)

Built from public sources only: the App Store listing and its reviews, the Google Play listing,
Trustpilot, press coverage. No account was used, no code or network calls of the reference app
were inspected. Scope = the **core loop**: put people in a group, log who paid, see who owes whom,
settle up. Our app is a new product for occasional users and Arabic speakers, not a copy.

## Sources

| source | url | gave us |
|---|---|---|
| App Store listing | https://apps.apple.com/app/splitwise-bill-splitter/id458023433 | free vs Pro feature list, languages (12, no Arabic), IAP prices |
| App Store reviews | https://apps.apple.com/us/app/splitwise/id458023433?see-all=reviews | complaints, missing features |
| Google Play | https://play.google.com/store/apps/details?id=com.Splitwise.SplitwiseMobile&hl=en_US | 10M+ installs, 4.0★, ~195K reviews, recent complaints (2026) |
| Trustpilot | https://ca.trustpilot.com/review/splitwise.com?page=3 | 2.0 TrustScore / 72 reviews |
| TechCrunch | https://techcrunch.com/2021/04/28/splitwise-raises-20m-series-a-to-help-everyone-in-the-world-divvy-expenses | $20M Series A, Pro was $3/mo then |
| IT Voice | https://www.itvoice.in/splitwise-has-introduced-restrictions-on-the-number-of-free-expenses-users-can-add | the daily cap and 10s wait, Pro $5/mo or $40/yr (US) |

## Screen inventory (our app)

| ID | screen | how you get there | purpose | key components | states |
|---|---|---|---|---|---|
| S01 | Welcome | first launch | pick language, enter your name | language toggle, text input, primary button | empty name, filled |
| S02 | Groups (home) | after S01, app open | list of groups with your balance in each | group card, FAB, header | empty, filled, long names |
| S03 | New / edit group | + on S02, edit on S04 | name, emoji, currency, members | inputs, emoji picker, currency picker, member chips | validation error, 2–50 members |
| S04 | Group | tap a group | expenses list + balances + settle tabs | segmented tabs, expense row, balance row | no expenses, many expenses |
| S05 | Add / edit expense | + on S04 | amount, what, who paid, split how, date | amount input, payer picker, split editor | invalid split, draft restored |
| S06 | Settle up | Settle tab on S04 | fewest transfers; mark paid | transfer card, mark-paid button | all settled |
| S07 | Share | Share on S04 | send summary text or a view link | share sheet | — |
| S08 | Shared view (web) | open a share link | read-only group anyone can open, "import" in app | banner, lists | bad/expired link |
| S09 | Settings | gear on S02 | language, your name, theme, export, Plus, privacy | rows, toggles | Plus locked/unlocked |
| S10 | Plus | from S09 or a locked feature | one-time unlock | price card, restore | purchased, unavailable on web |

## Flows

```
F01 First run         S01 -> S02                                   happy path: 2 taps + typing
F02 Create group      S02 -> S03 -> S04                            edge: duplicate member names, 1 member
F03 Add expense       S04 -> S05 -> S04                            edge: 0 amount, split not summing, 3-decimal currency
F04 See who owes      S04 (Balances)                               edge: all zero, rounding cents
F05 Settle up         S04 -> S06 -> mark paid -> S04               edge: partial payment
F06 Share             S04 -> S07 -> WhatsApp / link                edge: very large group (link length)
F07 Open shared link  link -> S08 (web or app) -> import           edge: corrupted link, already imported
F08 Change language   S09 -> RTL/LTR switch                         edge: mixed Arabic/Latin names
F09 Buy Plus          S09 -> S10 -> store sheet -> unlocked         edge: cancelled, restore on new phone
```

Core loop to beat: the reference app needs an account for every member before splitting
(reviews). Ours: open app, type your name, create group, add expense — **no account at all**.

## Components

Button (primary, secondary, ghost, danger), TextField, AmountField, Chip (member),
SegmentedTabs, Card, ListRow, Avatar (initials), Sheet/Modal, EmptyState, Toast, Header,
FAB, Toggle, Badge (Plus).

## Inferred data model (reference) → our model

```
Group     id, name, emoji, currency, members[], expenses[], payments[], createdAt, updatedAt
Member    id, name
Expense   id, title, amount (minor units), currency, rate (to group currency), paidBy memberId,
          split { mode: equal|exact|percent|shares, items: {memberId, value}[] }, category, date
Payment   id, from memberId, to memberId, amount, date
```
evidence: listing's feature list (split equally/unequally/percent/shares, record cash payments,
simplify debts, currencies). confidence: high.

## Out of scope / skip

| item | reason |
|---|---|
| Bank / wallet payments inside the app | regulated (payments licence), and region-specific |
| Receipt OCR | needs cloud ML or large on-device models; later |
| Cloud sync between phones | v2 (Supabase). v1 shares by link. |
| The reference app's users, data and brand | not ours |

## Size

10 screens, 9 flows, 4 entities. Hard parts: RTL at runtime, rounding with 0/2/3-decimal
currencies, link sharing without a server, in-app purchase on two stores. Size: **M**.
