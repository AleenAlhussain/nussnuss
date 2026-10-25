# NussNuss (نص نص)

Split any bill with friends. No limits, no ads, no sign-up. Arabic and English.
One Expo (React Native) codebase for iPhone, Android and the web.

> دليل النشر والربح بالعربي موجود في المستند المرفق مع المحادثة. الخطوات التقنية بالتفصيل في `replica/deploy.md`.

## Run it

```bash
npm install
npx expo start            # scan the QR code with Expo Go, or press w for the browser
```
In Expo Go the Plus purchase shows "not set up" (it needs a store build); everything else works.

## Check it

```bash
npm run check             # typecheck, 18 unit tests, brand sweep, store-listing lint, parity score
npm run build:site        # web build → site/ (landing page at /, app at /app/, privacy.html)
npx playwright test       # 7 end-to-end tests + accessibility scans against site/
```
If Playwright can't download its browser, set `CHROME_PATH` to any Chromium.

## Android APK for testing

Push this project to a GitHub repo: `.github/workflows/android-apk.yml` builds an installable APK on
GitHub's runners (about 15–20 minutes) and publishes it under the repo's **Releases**. Or, with an Expo
account: `npx eas-cli@latest build -p android --profile preview`.

## Ship it

See `replica/deploy.md`: developer accounts, RevenueCat product `nussnuss_plus_lifetime` (entitlement
`plus`), `eas build`, `eas submit`, hosting `site/`, store listing (`replica/launch/listing.json`) and
screenshots (`replica/launch/screenshots/`).

## Where things are

| path | what |
|---|---|
| `App.tsx` | providers, navigation stack, deep links |
| `src/screens/` | the 8 screens (welcome, home, group editor, group, expense, settings, Plus, shared view) |
| `src/split.ts` | splitting, balances, fewest-transfers plan (pure, unit-tested) |
| `src/money.ts` | 41 currencies, 0/2/3 decimals, Arabic digit parsing |
| `src/share.ts` | share links (group compressed into the `#` fragment), WhatsApp summary, CSV |
| `src/store.tsx` | on-device storage, drafts, demo trip |
| `src/purchases.ts` | one-time Plus purchase through RevenueCat |
| `src/ui.tsx`, `src/components.tsx` | design system primitives (RTL-aware) |
| `src/design/tokens.json` | colours (light, dark, 3 Plus themes), spacing, type |
| `web/landing.src.html` | landing page source |
| `replica/` | research, plan, design, tests, bugs, parity, launch kit, deploy guide, tools |

Navigation is a small in-app stack rather than Expo Router on purpose: the web build is a single page
that works from any path, which keeps share links working on any static host.
