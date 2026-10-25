# Backend — v1 has no server (on purpose)

The reference app's daily limit exists because every expense costs it server time. NussNuss v1
keeps everything on the phone, so there is no server bill, no account system to secure, and no
reason to ever limit anyone.

| part | v1 | notes |
|---|---|---|
| auth | none | no accounts; nothing to delete except the app's own data |
| database | AsyncStorage on the device (localStorage on web) | keys `nn:settings:v1`, `nn:groups:v1`, `nn:draft:v1:<group>` |
| sharing | group compressed into the link fragment (`#g=`) | fragments are not sent to the web server, so the host never sees group data |
| payments | RevenueCat → App Store / Google Play, one-time product | Apple and Google pay out to the owner's bank account |
| email / jobs | none | |
| sync between phones | v2: Supabase (`schema.sql` is ready, with row level security) | add when users ask for it; keep the free tier unlimited |

## Security checklist

- [x] no secrets in the app (RevenueCat public SDK keys are meant to be public)
- [x] every shared link is validated on decode (types, sizes, member ids, positive amounts) — unit-tested
- [x] no user data in URLs sent to a server (the payload is in the `#` fragment)
- [x] no logging of user data
- [x] `npm audit --omit=dev` (2026-10-23): 16 high, all inside Expo's build tooling (`braces` via the bundler's file matching, `node-forge` via the dev server's certificates). None of it ships in the app bundle; `npm audit fix --force` would downgrade Expo, so wait for the next Expo patch and re-run.
- [x] privacy: nothing collected → App Store "Data Not Collected", Play "No data collected"
      (re-check at submission: RevenueCat processes purchase data; declare "Purchases" if asked)
- [ ] privacy policy page live at nussnuss.app/privacy (text in `replica/launch/privacy.md`)
