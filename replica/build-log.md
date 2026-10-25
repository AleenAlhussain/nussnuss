# Build log

| screen | date | status | notes |
|---|---|---|---|
| shell (nav, tokens, primitives, store) | 2026-10-23 | done | in-app stack instead of Expo Router so the web build works from any path (share links, any static host) |
| S01 Welcome | 2026-10-23 | done | language switch, 3 promises, name |
| S02 Groups | 2026-10-23 | done | empty state with demo trip; "you owe / you're owed" per group |
| S03 New / edit group | 2026-10-23 | done | emoji, currency picker (41 currencies), people; people with activity can't be removed |
| S04 Group | 2026-10-23 | done | total, my balance, expenses, tabs |
| S05 Add / edit expense | 2026-10-23 | done | 4 split modes with live preview, Arabic digits, drafts, delete + undo. Date editing: not yet (today's date) |
| S06 Settle up | 2026-10-23 | done | fewest transfers, mark paid + undo |
| S07 Share | 2026-10-23 | done | WhatsApp, copy link, copy summary, system share |
| S08 Shared view | 2026-10-23 | done | read-only, import, works in any browser |
| S09 Settings | 2026-10-23 | done | language, name, theme, colour (Plus), CSV (Plus), privacy |
| S10 Plus | 2026-10-23 | done (code) | RevenueCat one-time purchase + restore; needs store products to go live |

Harder than expected: Arabic layout. Native RTL flipping needs an app restart, so direction is
handled by the app's own components and switches instantly; verified in e2e (back arrow moves
to the right edge).
