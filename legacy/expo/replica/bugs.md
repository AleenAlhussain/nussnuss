# Bugs — found by replica-test (Playwright + axe + screenshot review), 2026-10-23

Severity: S1 data loss / security / core flow blocked · S2 broken, no workaround ·
S3 broken with a workaround or visibly wrong · S4 cosmetic.

| ID | sev | where | steps | expected | actual | evidence | status |
|---|---|---|---|---|---|---|---|
| B01 | S3 | all segmented controls (S01, S04, S05, S06) | run axe on any screen with tabs | tabs inside a tablist | `aria-required-parent`: role=tab without a tablist parent (screen readers can't announce "tab 1 of 2") | axe serious, 2–4 nodes | fixed: container is `role=tablist` |
| B02 | S3 | S04 expense rows, S02 group cards | axe scan on S04 | accessible name includes the visible text | `label-content-name-mismatch`: name was only the title; voice-control users saying the visible text could not hit it | axe serious, 3 nodes | fixed: name comes from the content |
| B03 | S4 | S05 currency button | open Add expense | currency fits on one line | "AED · UAE dirham" wrapped to 3 lines in a 130px box | screenshot S05 (before) | fixed: compact code-only button, same height as the amount |
| B04 | S3 | S04 summary card | open the demo trip (OMR, 3 decimals) | balance chip inside the card | chip overflowed the card's edge | screenshot S04-demo (before) | fixed: chip moved under the total |
| B05 | S4 | S03 group editor | save empty, then type a name | the error disappears | "Give the group a name" stayed after typing | screenshot S03 (before) | fixed + covered by e2e |
| B06 | S4 | S04 expense rows | any expense in the group currency | one amount per row | the same amount shown twice (subtitle and right column) | screenshot S04 | fixed: subtitle shows the original amount only for foreign currencies |
| B07 | S4 | S05 | add a taxi without picking a category | neutral icon | defaulted to "Food" (coffee icon) | screenshot S04 | fixed: default category "Other" |

Open S1: **0**. Open S2: **0**.

## To check (not reproduced here, needs a phone)

- Keyboard covering the Save button on small Android phones (KeyboardAvoidingView is iOS-only by design; Android resizes the window).
- WhatsApp deep link on iOS when WhatsApp is not installed (falls back to copying the summary).
- Real in-app purchase and restore (needs the store products, see deploy.md).
