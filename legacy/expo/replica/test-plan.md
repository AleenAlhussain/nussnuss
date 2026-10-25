# Test plan — NussNuss

Automated: `npx jest` (18 logic tests) and `npx playwright test` (6 end-to-end specs on the web
build, same code as the phone app; each spec fails on any console error, uncaught exception or
5xx, and runs an axe accessibility scan that fails on serious/critical issues).

| case | what | how | result |
|---|---|---|---|
| F01-H1 | first run, name, home | e2e | pass |
| F01-N1 | Start with no name → hint shown | e2e | pass |
| F02-H1 | create group with 3 people | e2e | pass |
| F02-N1 | save with no name / one person → errors | e2e | pass |
| F02-E1 | duplicate name (different case) rejected | e2e | pass |
| F02-E2 | error clears when you type | e2e | pass |
| F03-H1 | add 300 split equally → total, my balance | e2e | pass |
| F03-N1 | save empty → "Enter an amount" | e2e | pass |
| F03-N2 | exact amounts not adding up → error + "left" counter | e2e | pass |
| F03-E1 | Arabic-Indic digits + Arabic decimal mark (٤٥٫٥) | e2e + unit | pass |
| F03-E2 | 3-decimal currency (OMR, KWD, BHD) | e2e + unit | pass |
| F03-E3 | draft kept after leaving the form, cleared after save | e2e | pass |
| F03-E4 | rounding: 100 / 3 adds up exactly | unit | pass |
| F03-E5 | foreign currency converts and adds up | unit | pass |
| F04-H1 | balances sum to zero (mixed modes + payments) | unit | pass |
| F04-E1 | 10 people × 60 random expenses: ≤ 9 transfers, everyone settled | unit | pass |
| F05-H1 | mark paid → transfer gone, undo → back | e2e | pass |
| F05-H2 | settle all → "All settled" | e2e | pass |
| F03-H2 | delete expense with confirm, undo | e2e | pass |
| F06-H1 | share sheet, copy link | e2e | pass |
| F07-H1 | friend opens link in a fresh browser, sees totals, imports | e2e | pass |
| F07-N1 | broken link → friendly message | e2e + unit | pass |
| F07-N2 | tampered payload (negative amount, unknown payer) rejected | unit | pass |
| F08-H1 | switch to Arabic instantly, RTL layout, Arabic currency format | e2e | pass |
| F09-N1 | Plus on web → clear "buy in the app" message, button disabled | e2e | pass |
| persist | reload keeps data | e2e | pass |
| a11y | axe on S01, S04, S05, S06 (EN+AR), S08, S10 | e2e | pass (after B01, B02) |
| CSV | export escapes quotes/commas, Arabic headers | unit | pass |

Manual on a phone before release (needs the owner's devices): purchase + restore in sandbox,
deep link from WhatsApp opens the app, iOS VoiceOver + Android TalkBack pass, dark mode,
small screen (iPhone SE), large text setting.
