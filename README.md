# NussNuss (نص نص) 2.0

Split bills with friends, fairly. One group per trip, flat or dinner; add what each person paid; NussNuss works out who owes whom with the fewest transfers. Friends join from a link, with no app and no sign-up. Arabic and English, right-to-left done properly, 41 currencies with the right decimals (KWD has three, JPY none).

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

The Flutter app (Flutter stable; the Android and iOS project folders are generated on first run):

```sh
cd apps/mobile
flutter create --platforms=android,ios --org app.nussnuss --project-name nussnuss .
flutter run --dart-define=API_URL=http://10.0.2.2:4000    # Android emulator talking to the API on your machine
```

## Tests

| Command | Checks |
| --- | --- |
| `npm test` | Money rules (13 cases) and that every token color pair meets WCAG contrast |
| `npm run test:api` | The API against a real Postgres (`nussnuss_test` database) |
| `npm run test:web` | The web app in Chromium with Playwright, on a phone and a desktop size, with axe accessibility checks |
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

## Before the stores

These need the owner's own accounts, so they are not automated here:

1. Host the API and database (any Docker host with Postgres), then set the repository variables `API_URL` and `WEB_URL` so CI builds the apps against it.
2. A Google Play developer account and an upload key for signing the Android App Bundle.
3. An Apple Developer account for signing and TestFlight.
4. A privacy policy page and the store listings.
