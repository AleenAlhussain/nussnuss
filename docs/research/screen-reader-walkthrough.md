# VoiceOver and TalkBack walkthrough

Phase 0 of the UI/UX plan. The automated tests check labels, contrast and touch targets on every push; this walkthrough checks what only a person using a screen reader notices: the order things are read in, whether a control says what it does, and whether every gesture has another way.

Run it on a real iPhone with VoiceOver and a real Android phone with TalkBack, in English and in Arabic, at the default and the largest text size. Write the result in the last column and turn every "No" into a finding.

## Settings to test with

- iPhone: VoiceOver on; then Larger Text at the largest accessibility size; Reduce Motion; Reduce Transparency; Increase Contrast.
- Android: TalkBack on; Font size and Display size at the largest; Remove animations; High contrast text.
- Both languages: English, then Arabic (the reading order must follow right to left).

## Checklist

| Screen | Check | Yes / No |
|---|---|---|
| Welcome | The three cards, the name field and Get started are read in order; the field says it is for your name | |
| Home | The overall balance is read as one phrase ("Overall, you get back, AED 230") before anything else | |
| Home | The Next step card reads the sentence, then its two buttons by name | |
| Home | People: each person reads name and amount ("Omar, plus AED 55") and opens the person view | |
| Home | Settled groups: the "Show settled groups" button says it expands, and says how many | |
| Tab bar | Each tab says its name and that it is selected; Activity says how many are new | |
| Tab bar | At the largest text size the bar keeps its size and a long press shows the large label | |
| Group | The balance, the who-paid line and the total are read before the list | |
| Group | Each expense row reads title, who paid, for whom and the amount, in that order | |
| Group | The row actions (Duplicate, Delete) are reachable without swiping: the rotor or actions menu on iPhone, the actions menu on Android | |
| Group | The category tile says "Category for Lunch: Food" and opens the category list | |
| Add expense | The keypad keys read as numbers; the sum line is announced | |
| Add expense | Equally and Unequally read as a two-choice control; the share buttons say "One more share for Sara" | |
| Add expense | Drag to split has the plus and minus buttons as the alternative | |
| Settle up | Each transfer reads "Omar pays you" then the amount, then Mark as paid and Remind | |
| Settle up | Mark as paid works without swiping | |
| Person | "Settle everything" says what it does; the confirm sheet lists each group and amount | |
| Activity | Each row reads who, what, the group, when and your share; new items say "New" | |
| Invite | The QR code has a label with the link; Copy and Share link are buttons with names | |
| Join | Each name choice reads the name and whether it is taken; "I'm someone else" is last | |
| You | The profile row says "Photo, name and colour"; the colour swatches read their names | |
| Sheets | Focus moves into a sheet when it opens and back to the button when it closes; Escape or the two-finger scrub closes it | |
| Toasts | "Marked as paid" and Undo are announced; Undo can be reached before it disappears | |
| Everywhere | No control is read as "button" alone; no decorative image is read | |
| Everywhere | Arabic: amounts read as numbers with the currency, not digit by digit | |

## Afterwards

Add every "No" to the inspection document with the screen, what was read, what should have been read, and the platform. Fixes get a test where the tests can check it (labels, order, roles).
