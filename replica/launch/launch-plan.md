# Launch plan — NussNuss

## The hook

Arabic: **"خليها نص نص"** (let's go half-half). Everyone in the Arab world says it.
English: **"Split it. No limits."**

Built-in loop: every group someone creates sends a WhatsApp summary + link to 3–10 friends, and
the link page shows the app's name and an "Get the free app" button (once store links are added
to `src/nav.tsx` → `STORE_LINKS`). Each user is an advert to their whole group.

## Timing (Gulf)

- **Now – March: camping season (الكشتة / البر).** Groups of friends split tents, fuel, food — the
  exact use case. Launch here first.
- **Ramadan 2027 (around Feb–Mar): iftar gatherings and group gifts.**
- **Summer: group travel abroad** — push Plus (mixed currencies).
- University semester starts: roommates and shared flats.

## Before launch (week 0)

- [ ] Owner opens developer accounts (see `deploy.md`). Google needs **12 testers for 14 days**
      in a closed test for new personal accounts — recruit them now (family, friends, a WhatsApp
      group). This is also the first word of mouth.
- [ ] Buy `nussnuss.app` (available on 2026-10-23), host the web build there (share links).
- [ ] Handles: @nussnuss / @nussnussapp on TikTok, Instagram, X, Snapchat.
- [ ] Analytics: none in v1 by design (privacy). Track installs and sales from store consoles.

## Launch week

1. **Short videos** (TikTok, Reels, Snapchat Spotlight, YouTube Shorts) — 10 scripts:
   - "The friend who always says 'I'll pay you back later'" → 15s, the app ends the argument.
   - "Camping trip maths in 10 seconds" → add 5 expenses, show who pays whom.
   - "POV: the other app asks you to wait 10 seconds" → ours doesn't. (Do not name the other app.)
   - Arabic voiceover skits around "خليها نص نص".
   - Split the bill live at a restaurant, show the WhatsApp message arriving.
2. **Communities**: Gulf university groups, expat groups (Dubai, Riyadh, Doha), camping groups,
   travel groups. Honest maker posts, not spam.
3. **Reddit / Product Hunt**: post as the maker, lead with the fix ("no daily limit, no sign-up,
   friends open it from a link"). Reply to people asking for alternatives, say you built it.
4. **Talk to the first 10 users by hand** — ask what's missing, ship it within a week.

## Rules

- No fake reviews, ratings or user counts. No reviewer quotes as testimonials.
- No competitor names in the app name, listing, keywords or ads.
- Ask for a rating only after a happy moment (e.g. after "All settled"), max once per 90 days,
  using the system prompt (add `expo-store-review` in v1.1).
