---
paths:
  - "lib/presentation/**/*.dart"
  - "lib/core/widgets/**/*.dart"
---

# UI standards

## Design system

- Colors, text styles, spacing and radii come from `core/theme/`. Zero hardcoded values in widgets.
- Spacing on the 4 pt scale via `AppSpacing`. Radii: 12 cards, 24 sheets, 999 pills.
- **No emoji as iconography.** The previous build used 🌞 for lunch and 🥜 for snacks; they render
  differently per OS, don't scale, and read as unfinished. Use the icon set.
- Animations 200–400 ms, implicit (`AnimatedContainer`, `AnimatedOpacity`) unless there's a reason.

## Required states

Every screen that loads data renders all four `ViewState` cases. Empty states need a heading, one
sentence, and a single action button — not just text. Skeleton loaders over spinners.

## Copy

- Every string is an l10n key (en + hi). No string concatenation — use placeholders.
- Enums are mapped through l10n. Never render `lose_weight`.
- Numbers: Indian digit grouping for currency (₹1,24,560). Weight one decimal. kcal integer.
- Safety and medical copy comes from the API's `user_message`. Do not write it locally.

## Accessibility

Touch targets >= 48 dp. Contrast >= 4.5:1. Semantic labels on every icon-only button. Test at 200 %
font scale — if it clips, the layout is wrong, not the font scale.
