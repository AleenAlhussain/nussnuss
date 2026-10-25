# Deploy — NussNuss

## Preflight (run 2026-10-23)

| check | command | result |
|---|---|---|
| logic tests | `npx jest` | **18/18 pass** |
| end-to-end + accessibility | `npm run build:site && npx playwright test` | **7/7 pass** (app + landing page), 0 console errors, 0 serious/critical axe issues |
| typecheck | `npx tsc --noEmit` | **0 errors** |
| parity | `python3 replica/tools/parity.py replica/features.csv` | **98%**, must-haves 10/10, verdict: better than the original |
| rebrand sweep | `python3 replica/tools/sweep.py . --config replica/brand.json` | **clean** |
| store listing | `python3 replica/tools/listing.py replica/launch/listing.json` | **OK** (all fields within limits) |
| contrast | `python3 replica/tools/contrast.py src/design/tokens.json` | **0 AA failures** (8 palettes) |
| native config | `npx expo prebuild` (scratch copy) | iOS + Android projects generate; deep links, RTL off, locales en/ar |
| web build | `npm run build:site` | `site/`: landing `/`, app `/app/`, `privacy.html`, `social.png` |
| open S1/S2 bugs | `replica/bugs.md` | **0 / 0** |
| privacy policy | `replica/launch/privacy.md` | written — needs hosting at `/privacy` + a support email |
| not checked here | — | a real build on a phone (needs the owner's EAS account), real purchase in sandbox |

Not done by Claude, by rule: buying anything, creating accounts, typing passwords or bank details,
accepting agreements, pressing "publish". Everything below marked **YOU** is for the owner.

## 1. Accounts (YOU, once)

| what | cost | where | notes |
|---|---|---|---|
| Apple Developer Program | $99 / year | developer.apple.com/programs | individual or company; company needs a D-U-N-S number |
| Google Play Console | $25 once | play.google.com/console | identity verification; **new personal accounts must run a closed test with 12 testers for 14 days** before production |
| Expo (EAS) | free tier is enough to start | expo.dev | builds in the cloud — no Mac needed |
| RevenueCat | free under $2,500/month revenue, then 1% | revenuecat.com | handles the Plus purchase on both stores |
| Domain `nussnuss.app` | ~$15/year | any registrar | was available on 2026-10-23 |

**Getting paid:** App Store Connect → Business → Agreements (sign the Paid Apps agreement), Tax,
and **Banking** (your bank account + IBAN). Play Console → Settings → **Payments profile** (bank
account). Apple and Google pay your bank directly every month. Join Apple's **App Store Small
Business Program** (15% instead of 30%).

## 2. Configure the project (5 minutes)

```bash
npm install
npx eas-cli@latest login            # your Expo account
npx eas-cli@latest init             # writes the projectId into app.json
```
- `app.json` → `ios.bundleIdentifier` / `android.package` are `app.nussnuss` — change if you want
  (cannot change after the first upload).
- `app.json` → `extra.revenuecat.ios` / `.android` → the **public** SDK keys from RevenueCat.
- `app.json` → `extra.shareBaseUrl` → where the web build is hosted (default `https://nussnuss.app/`).
- `src/nav.tsx` → `STORE_LINKS` → the store URLs, once the app is live.

## 3. Purchases (YOU + 10 minutes)

1. App Store Connect → your app → In-App Purchases → **Non-Consumable** `nussnuss_plus_lifetime`, $4.99.
2. Play Console → Monetize → In-app products → `nussnuss_plus_lifetime`, $4.99.
3. RevenueCat → project → add both apps → entitlement **`plus`** → products → offering "default".
4. Test with a Sandbox tester (Apple) / license tester (Google). Buy, delete app, reinstall, Restore.

## 4. Web build (hosts the share links)

```bash
npm run build:site                   # → site/  (landing page at /, the app at /app/, privacy.html)
```
Upload `site/` to Vercel, Netlify or Cloudflare Pages (all free for this size), connect the domain:

| record | name | value |
|---|---|---|
| A | @ | your host's IP (shown in its domain settings) |
| CNAME | www | your host's target |

`privacy.html` is generated from `replica/launch/privacy.md`; add your support email there first, and point the store's support URL at a page or email you answer. For links to open the
app directly on phones (optional, later): host `/.well-known/apple-app-site-association` and
`/.well-known/assetlinks.json` with your Team ID and signing fingerprint.

## 5. Build and submit

```bash
npx eas-cli@latest build -p all --profile production
npx eas-cli@latest submit -p ios --latest        # → TestFlight
npx eas-cli@latest submit -p android --latest    # → Play internal testing (then closed test, 12 testers × 14 days)
```
Then in each store: paste the listing from `replica/launch/listing.json` (English + Arabic),
upload screenshots from `replica/launch/screenshots/` (`ios-6.9/` = 1290×2796, `android/` =
1080×1920), feature graphic `replica/launch/feature-graphic.png`, privacy answers ("Data Not
Collected"), age rating 4+, review notes (in `listing.json`), then **Submit for review**.

## 6. First week

- Crash reports: App Store Connect → TestFlight/Analytics, Play Console → Android vitals.
- Read every review, reply to every one.
- Ship fixes with `eas build` + `eas submit`, or JS-only fixes with `eas update`.
