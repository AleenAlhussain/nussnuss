# Architecture — NussNuss

## Stack

| layer | choice | why |
|---|---|---|
| app (iOS, Android, web) | **Expo SDK 58 + React Native 0.88 + TypeScript** | one codebase for both stores and the browser |
| navigation | small in-app stack (state machine) | 10 screens; the web build is one page that works from any path, so share links work on any static host (chosen over Expo Router for that reason) |
| storage | `@react-native-async-storage/async-storage` (localStorage on web) | local-first, offline, no server bill at zero users |
| share links | `lz-string` → URL fragment (`#g=`) | the group travels inside the link; no server, nothing stored by us |
| purchases | `react-native-purchases` (RevenueCat) | one API for App Store + Google Play one-time purchases; payouts go to the owner's bank account set in each store |
| icons | `@expo/vector-icons` (Feather, MIT) | open icon set |
| tests | Jest (logic) + Playwright (web e2e) | |
| hosting (web/share links) | any static host (Vercel / Netlify / Cloudflare Pages) | `npm run build:site` → `site/`: landing at `/`, app at `/app/` |
| sync (v2) | Supabase Postgres + Auth | when users ask for live multi-device groups |

One app, no microservices, no server in v1.

## Data (v1, on device)

TypeScript types in `src/types.ts`. Money is **integer minor units** (fils, cents) with the
currency's own decimals (0, 2 or 3). Times are ISO strings in UTC, shown in local time.

## Schema (v2, Supabase) — `schema.sql`

Kept ready so sync can be added without changing screen code: the data layer
(`src/store.ts`) exposes the same functions whether it is backed by AsyncStorage or Supabase.

## API (v1)

No network API. Functions in the data layer, by flow:

| function | flow | notes |
|---|---|---|
| `createGroup`, `updateGroup`, `deleteGroup` | F02 | |
| `addExpense`, `updateExpense`, `deleteExpense` | F03 | validates the split server-side style (pure function) |
| `computeBalances`, `simplifyDebts` | F04, F05 | pure, unit-tested |
| `addPayment`, `deletePayment` | F05 | |
| `encodeGroup`, `decodeGroup` | F06, F07 | versioned payload `v:1` |
| `importGroup` | F07 | new ids if the group already exists |

## Parts that bite

- **Rounding**: equal split of 100.00 between 3 → 33.34 / 33.33 / 33.33, remainder to the first
  members in a stable order. Totals always add up exactly.
- **3-decimal currencies** (KWD, BHD, OMR, JOD, TND, LYD, IQD shown with 3): from a table, not Intl.
- **RTL at runtime**: Android/iOS `I18nManager.forceRTL` needs a restart, so layout direction is
  applied by our own primitives (row direction, text alignment) and switches instantly.
- **Link length**: a 30-member, 300-expense group compresses to a few KB; links over ~8 KB fall
  back to sharing text only, with a note.
- **Purchases**: unavailable on web and in Expo Go; the app shows that plainly. Restore button
  for new phones (Apple requirement).
- **Privacy**: nothing leaves the phone unless the user shares a link. App Store privacy label:
  Data Not Collected (if RevenueCat is configured without extra data collection — check at submit).

## Build order

1. Vertical slice: S01 → S02 → S03 → S04 → S05 → balances.
2. Must-haves: split modes, settle up (S06), share (S07/S08), Arabic RTL, currencies.
3. Should-haves: drafts, dates, categories, settings (S09).
4. Plus (S10): themes, CSV export, currency conversion.
