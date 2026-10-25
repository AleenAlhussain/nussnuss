# NussNuss (نص نص) 2.0

Split bills with friends, fairly. One group per trip, flat or dinner; add what each person paid; NussNuss works out who owes whom with the fewest transfers. Friends join from a link, with no app and no sign-up. Arabic and English, right-to-left done properly, 41 currencies with the right decimals (KWD has three, JPY none).

Free with no limits and no ads. An expense takes three taps (amount, suggested title, save); settling up opens the payment link or IBAN the friend shared; a reminder goes out on WhatsApp; a "who owes who" card can be posted to the group. It works offline and updates live. Optional NussNuss Plus adds recurring bills, weekly reminders, live rates, receipts by item, spending charts, CSV and print, and the Night and Saffron looks; a Trip Pass opens Plus for one group for 30 days. Money circles (جمعية) track turns and payments without NussNuss holding any money.

| Part | What | Where |
| --- | --- | --- |
| Web app | Next.js 16, React 19, Tailwind 4, Motion | `apps/web` |
| Mobile app | Flutter (iOS and Android) | `apps/mobile` |
| API | NestJS 12, Drizzle ORM, Postgres 16 | `apps/api` |
| Money rules | Splits, rounding, balances, fewest transfers (TypeScript, ported to Dart) | `packages/core`, `apps/mobile/lib/core` |
| Design tokens | One JSON file that generates the web CSS and the Flutter Dart | `packages/tokens` |
| Version 1 | The original Expo app, kept for reference | `legacy/expo` |

## Run it

With Docker, everything in one command:

```sh
cp .env.example .env        # change the passwords before you put this on a server
docker compose up --build
```

The web app is on http://localhost:3000 and the API on http://localhost:4000.

Without Docker you need Node 22 and a Postgres 16 with a `nussnuss` database (user and password `nussnuss`):

```sh
npm ci
npm run build:packages
npm run dev:api     # http://localhost:4000, runs the database migrations on start
npm run dev:web     # http://localhost:3000
```

The Flutter app (Flutter stable):

```sh
cd apps/mobile
flutter run --dart-define=API_URL=http://10.0.2.2:4000    # Android emulator talking to the API on your machine
```

## Tests

| Command | Checks |
| --- | --- |
| `npm test` | Money rules, suggestions, receipts and pay links (18 cases) and that every token color pair meets WCAG contrast in every look |
| `npm run test:api` | The API against a real Postgres (`nussnuss_test` database): accounts, purchases with test certificate chains, recurring bills, circles, rates, export, reminders, live updates (36 cases) |
| `npm run test:web` | The web app in Chromium with Playwright, on a phone and a desktop size, with axe accessibility checks: three-tap add, repeat, remind, pay with, share card, recovery and device codes, offline replay, live updates, Plus, circles |
| `flutter test` (in `apps/mobile`) | The Dart money rules, Dart and TypeScript agreeing on 300 random groups, and the app flow with tap-target, label and contrast guidelines |

GitHub Actions runs all of these on every push, builds both Docker images and starts them together, and builds the Android APK and an unsigned iOS build. The APK is attached to each run as a download.

## Design

NussNuss follows Apple's 2025 design language without becoming an iOS copy:

- **Liquid Glass only on the navigation layer.** The tab bar, the add button, the bar buttons and the sheets are glass; content cards are solid. Glass never sits on glass.
- **The rim of light.** Glass panes have a 1px highlight along the top edge and a shadow painted only outside the shape, so the pane itself stays clean.
- **Frosted, by choice or by need.** Settings has a Frosted option that makes every glass surface solid. It turns on by itself with Reduce Transparency or Increase Contrast in the browser, and with Increase Contrast on iPhone.
- **Springs, not curves.** Motion uses the same three springs everywhere (standard, bouncy, gentle), defined once in the tokens. Reduce Motion swaps them for short fades.
- **The coin.** The brand mark is one coin in two fair halves. When a group is settled, the halves snap together.
- **Platform manners.** 44pt touch targets on iOS and 48dp on Android, the native back gesture on each, system fonts, and Arabic that mirrors the layout while numbers stay readable.

Change a color, size or spring in `packages/tokens/tokens.json`, then run `npm run tokens` to regenerate both platforms.

## Docs

- [`docs/launch.md`](docs/launch.md): what needs the owner's accounts and which settings switch each feature on.
- [`docs/store-listing.md`](docs/store-listing.md): store copy in English and Arabic, privacy answers, screenshot plan.
- [`docs/seasonal-campaigns.md`](docs/seasonal-campaigns.md): Ramadan, Eid, summer and university-year campaigns.
- [`docs/payments-partner.md`](docs/payments-partner.md): how a licensed payment partner plugs into Pay with and money circles.

## Before the stores

These need the owner's own accounts, so they are not automated here (details in `docs/launch.md`):

1. Host the API and database (any Docker host with Postgres), then set the repository variables `API_URL` and `WEB_URL` so CI builds the apps against it.
2. A Google Play developer account and an upload key for signing the Android App Bundle.
3. An Apple Developer account for signing and TestFlight.
4. The in-app products in both stores, and the store keys on the server.
5. A lawyer's read of the privacy policy and terms (`/privacy`, `/terms`), and the store privacy forms.
