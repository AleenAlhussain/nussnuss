# NussNuss for iOS and Android (Flutter)

The same app as the web, built natively with Flutter. It talks to the NestJS API in `apps/api`.

## Run

```sh
flutter create --platforms=android,ios --org app.nussnuss --project-name nussnuss .   # first time only
flutter run --dart-define=API_URL=http://10.0.2.2:4000 --dart-define=WEB_URL=http://localhost:3000
```

`flutter create` only adds the files that are missing. The committed manifests, the Arabic app name (نص نص) and the app icons are kept.

`API_URL` defaults to the API on your computer (`10.0.2.2` from the Android emulator, `127.0.0.1` from the iOS simulator). `WEB_URL` is where invite links open, so friends can join from the browser.

## How it is put together

| Folder | What |
| --- | --- |
| `lib/core` | The money rules, ported line for line from `packages/core`. Pure Dart. |
| `lib/design` | Tokens (generated), theme, glass, the coin, shared widgets, the large-title page |
| `lib/data` | API client on `dart:io`, models, the session (token, language, theme, glass) |
| `lib/screens` | Welcome, groups, a group, the expense sheet and keypad, new group, share, settings |
| `lib/l10n` | English and Arabic copy, generated from the web's `lib/i18n.ts` so both apps say the same thing |
| `tool` | `generate.mjs` regenerates the shared Dart files; `parity.mjs` writes the TypeScript results the parity test replays |

Dependencies are deliberately few: `shared_preferences` and the Flutter SDK's own localization packages.

## Tests

```sh
node tool/parity.mjs 300 > test/parity.json   # from the repo root after `npm run build:packages`
flutter test
```

- `core_test.dart` mirrors `packages/core/test/core.test.ts` case for case.
- `parity_test.dart` replays 300 random groups through the Dart rules and expects exactly the TypeScript results.
- `widget_test.dart` walks through first run, a new group, an expense on the keypad, settling up with undo, Arabic right-to-left, and the glass fallbacks. It checks Flutter's tap-target, label and text-contrast guidelines on each main screen.

## Accessibility

- Every control has a spoken label; toggles say whether they are on.
- Touch targets are at least 44pt on iOS and 48dp on Android.
- Text follows the system text size.
- With Increase Contrast (iOS), glass turns solid and secondary text gets darker. Frosted in Settings does the same on any phone.
- With Reduce Motion, nothing scales or slides.
- Arabic mirrors the whole layout. Amounts and the keypad stay left to right, like a calculator.
