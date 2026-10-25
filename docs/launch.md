# What needs the owner's accounts

Everything below is built and tested but stays switched off until the owner adds their own accounts and keys. Nothing here should be done by anyone else on the owner's behalf: each step involves an agreement, a payment or a signing key.

| To switch on | You create | Then set | Where |
| --- | --- | --- | --- |
| A live server | A Docker host with Postgres (any provider), a domain with HTTPS | `.env` from `.env.example` (`DATABASE_URL`, `WEB_ORIGIN`, `PUBLIC_API_URL`), then `docker compose up -d` | Server |
| Phone apps pointed at it | – | Repository variables `API_URL`, `WEB_URL` | GitHub › Settings › Variables |
| Google Play | A Play developer account, an upload key | Upload the AAB from CI; `ANDROID_PACKAGE_NAME` | Play Console |
| App Store | An Apple Developer account, a signing certificate | Bundle id, team id; build from the `ios` job with signing | App Store Connect |
| Plus, Trip Pass, Looks | The products `nussnuss.plus.monthly`, `nussnuss.plus.yearly` (subscriptions), `nussnuss.trip_pass`, `nussnuss.look.night`, `nussnuss.look.saffron` (one-off) in both stores, with prices per country | `APPLE_ROOT_CA`, `APPLE_BUNDLE_ID`, `GOOGLE_PLAY_SERVICE_ACCOUNT` | Server `.env` |
| Sign in with Apple and Google | Service ids in Apple Developer and a Google Cloud OAuth client | `APPLE_CLIENT_IDS`, `GOOGLE_CLIENT_IDS` (API); `NEXT_PUBLIC_APPLE_CLIENT_ID`, `NEXT_PUBLIC_GOOGLE_CLIENT_ID` (web build); `APPLE_SIGN_IN=true`, `GOOGLE_SERVER_CLIENT_ID` (Flutter dart-defines) | Server, CI |
| Passkeys | – | `WEBAUTHN_RP_ID` (your domain), `WEBAUTHN_ORIGIN` | Server `.env` |
| Invite links open the app | – | `APPLE_APP_ID` (team id.bundle id), `ANDROID_CERT_SHA256` (Play app signing certificate), `APP_LINK_HOST` (domain, for the Android and iOS builds) | Server `.env`, CI env |
| Push for reminders | A Firebase project (Android) and an APNs key (iPhone) | `FCM_SERVICE_ACCOUNT`, `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | Server `.env` (the apps still need Firebase Messaging added; until then reminders arrive in the in-app inbox) |
| Crash reports | – | `CRASH_REPORTS=log` | Server `.env` |
| Payment partner | A licensed partner and an agreement | See `docs/payments-partner.md` | – |

Never set `ALLOW_DEV_PURCHASES=true` or build with `NEXT_PUBLIC_DEV_PURCHASES=true` / `DEV_PURCHASES=true` for anything real people use: they unlock Plus without paying.

Before submitting: have a lawyer read `apps/web/lib/legal.ts` (privacy and terms), have a native editor read the Arabic copy, fill in the privacy answers from `docs/store-listing.md`, and add a support email to both store listings (the privacy page points people there).
