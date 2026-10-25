# Components — NussNuss (all in `src/ui.tsx` and `src/components.tsx`)

Tokens: `src/design/tokens.json` (light, dark, 3 Plus accents; 0 AA failures across 8 palettes).
Icons: Feather (MIT). Fonts: system (SF / Roboto / browser), which render Arabic well.
Every component reads direction from `useUI().rtl` and mirrors itself; directional icons flip.

```
Button      variants primary, secondary, ghost, danger · 48px (36 small) · loading keeps the label
            a11y: role button, label, disabled + busy state
IconButton  44px tap target, label required
Field       label, hint, error (danger border + message), focus = 2px accent border, big variant (amount)
            a11y: label from `label` or placeholder; RTL text alignment
Chip        selectable (role button + selected), optional remove "x" with its own label
Segmented   role tablist > tab (selected) — fixed in B01
Card        pressable or static; name from content — fixed in B02
Avatar      initials, 8 tones, hidden from screen readers (name is next to it)
Empty       icon, title, body, actions
Sheet       modal with backdrop (tap to close) and close button; Confirm builds on it
Toast       polite live region, optional action (Undo)
PlusBadge   saffron pill
Logo        the mark drawn with views (no image needed)
CurrencyPicker / CurrencyButton (compact variant), CategoryIcon, SettlePlan
```
