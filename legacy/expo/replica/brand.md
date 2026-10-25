# Brand — NussNuss (نص نص)

## Name

"نص نص" (nuss-nuss) is how people across the Arab world say "fifty-fifty, let's split it".
It is short, says what the app does, is easy to pronounce in English, and has a ready-made
catchphrase for social video: **"خليها نص نص"** — "let's go nuss-nuss".

Candidates considered (20, cut to 5): Qatta, Hisabna, Mizan, Lammah, NussNuss, Shilla, Evenly,
Halvo, Fairo, Divvy, Tallyo, Settlr, Qisma, Sahm, Kaffa, Nusso, Evenup, Spliq, Chip, Sawa.

| name | why cut / kept | App Store / web search | domain | trademark |
|---|---|---|---|---|
| Qatta (قطّة) | **cut**: a bill-splitting app already uses this name at qatta.app; "Yalla Qata" exists for savings circles | found, 2026-10-23 | qatta.app taken | n/a |
| Hisabna | cut: crowded "Hisab" finance apps → confusingly similar | several "Hisab" apps found, 2026-10-23 | hisabna.app available (GoDaddy, 2026-10-23) | to run |
| Mizan | cut: common word, many existing brands | — | mizanapp.com taken | to run |
| Sawa | cut: an existing telecom brand in Saudi Arabia | — | — | conflict likely |
| **NussNuss** | **kept** | no bill-splitting app with this name found in a web search, 2026-10-23 | **nussnuss.app available**, nussnuss.co available, getnussnuss.com available; nussnuss.com taken (GoDaddy, 2026-10-23) | **to run** (USPTO class 9 & 42, EUIPO, WIPO, UAE Ministry of Economy) |

Still to run before spending money on the name: App Store and Google Play exact-name search
from a phone, handles (X, Instagram, TikTok: @nussnuss / @nussnussapp), and trademark searches.
These are screening checks, not legal clearance; a trademark lawyer should confirm.

Store names (≤30 chars): `NussNuss: Split Bills` (EN) · `نص نص: تقسيم الحساب` (AR).

## Palette

Primary **violet #4F3BD6** with **saffron #F4B400** highlights — a different hue family from the
reference app's green/teal. Semantic green/orange-red for "owed / owe". Light and dark themes.
Contrast check: **0 AA failures** (34 pairs, `tools/contrast.py`).

## Logo brief

- Idea: a coin cut into two halves, slightly offset — "one bill, two fair halves".
- Mark type: symbol + wordmark ("NussNuss" in Latin, "نص نص" in Arabic, same weight).
- Must read at 16px (favicon) and 1024px (app icon, no transparency for iOS).
- Deliverables: SVG, 1024×1024 icon, Android adaptive foreground, favicon, 1200×630 social image.
- Must not resemble the reference app's mark: no green, no stacked "S" shapes.
A first version of the icon is in `assets/` (generated from `assets/brand/icon.svg`); a designer
can refine it.

## Voice

Three words: **friendly, clear, fair**.
- friendly, not childish · clear, not technical · fair, not preachy

| do | don't |
|---|---|
| "Ahmed owes Sara 45 AED" | "Debt obligation detected" |
| "All settled. Nice." | "Balance status: 0.00" |
| "No limits. Add as many as you like." | "Upgrade to unlock more expenses" |
| "Your data stays on your phone." | long privacy jargon |
| "خليها نص نص" in Arabic UI where it fits | forced slang in every string |

Most-seen strings (written fresh in `src/i18n.ts`, both languages): welcome title, your name,
new group, add expense, paid by, split equally, who owes whom, mark as paid, all settled,
share with the group.
