# Design system

**Purpose: one place that decides how the app looks, so five screens do not each decide separately.**

Nothing in `lib/` may use a raw `Color(0x…)`, a raw radius, or a raw pixel gap. If a value is not
here, it does not go in a widget — it goes here first (CLAUDE.md rule 5).

## Tokens

| File | Holds |
|---|---|
| `core/theme/app_colors.dart` | every colour |
| `core/theme/app_spacing.dart` | `AppSpacing` gaps · `AppRadius` corner radii |
| `core/theme/app_text_styles.dart` | the type scale |

### Colour

```
accent        #12A67F   brand, works on light and dark
accentBright  #1FD9A4   dark surfaces ONLY — the big number on a tile, an active state
```

`accentBright` exists because `accent` is 6.0:1 on the dark background and a headline figure wants
more separation; `accentBright` is 10.2:1. It **fails contrast on light surfaces**, so `StatTile`
picks between them by `theme.brightness` rather than letting a caller choose.

**There is deliberately no colour for "over target" or "missed".** docs/05 §6 forbids marking a
past day as failure, and a red macro bar is exactly that. A number is stated, never scored.

### Contrast, measured not assumed

CLAUDE.md rule 12 requires 4.5:1. Current dark-mode pairs:

| Pair | Ratio |
|---|---|
| `onSurface` on `background` | 15.6:1 |
| `muted` on `background` | 7.7:1 |
| `muted` on `surfaceAlt` | 6.0:1 |
| `accent` on `surface` | 5.4:1 |
| `accentBright` on `surface` | 9.2:1 |

⚠️ A progress ring's **track is a dimmed fill colour, not a surface colour**. Using
`surfaceContainerHighest` put the track at 1.00:1 against the emphasised card it sat on — the ring
was invisible on screen while every test still passed.

⚠️ `darkOutline` is **1.4:1** — decoration only. A border that carries meaning (selected chip,
focused field) must use `darkOutlineStrong`, which clears WCAG 1.4.11's 3:1 for UI boundaries.

## Components

| Widget | Use for | Do not |
|---|---|---|
| `AppCard` | any grouped block | build a `Container` with your own radius |
| `AppCard(accent: true)` | the ONE headline block per screen | mark three cards accent — nothing is emphasised then |
| `StatTile` | a number with label, optional target and bar | pass a colour; it has none by design |
| `SectionHeader` | a titled section, optional action | roll a `Row` with a `TextButton` |
| `ProgressRing` | any circular progress | pass a colour; it has none, same reason as `StatTile` |
| `MacroBar` | a macro with its bar | hide it when there is no target — draw it unfilled and say why (D-51) |
| `GaugeSideStat` | a figure beside the gauge | pass 0 for missing data; pass null and it renders an em dash |
| `CalorieGauge` | the day's calories, one per screen | use it for anything but the headline number |
| `LoadingView` `EmptyView` `FailedView` | the four states (rule 6) | invent a fifth state |

`StatTile.target` is nullable and null means **no target**, not zero. Rendering "0 g" from absent
data is a fabricated fact — the same rule as D-38 (null trend) and D-43 (null plan).

## Layout rhythm

- Screen padding: `AppSpacing.xl` horizontal.
- Between cards: `AppSpacing.lg`. Inside a card: `AppSpacing.lg`.
- Card radius: `AppRadius.cardLarge` (20). Tile radius: `AppRadius.tile` (16).
- Rows of tiles scroll **horizontally** rather than shrinking, so 200 % font scale does not crush
  them.

## Adoption status

| Screen | On the system |
|---|---|
| Home | ✅ gauge, macro rings, entry cards |
| Progress | ✅ headline card, chart card |
| You | ✅ section headers, detail cards |
| Onboarding | ❌ still ad-hoc — it predates the system |
| Login / gate screens | ❌ still ad-hoc |

## What we did NOT take from the reference design

The design that prompted this system is a fitness app. Four of its patterns are refused here, and
each refusal is a rule this project already made:

| Pattern | Why not |
|---|---|
| Streak flame, "2 Weeks of Energy" challenge | docs/05 §6 — no streaks, no leaderboards |
| 5th tab (Workout) | CLAUDE.md rule 1 — the shell is `Home · Plan · [+] · Progress · You`; a tab needs an ADR |
| Cooking community: follow, likes, comments | not in docs/02; a social graph in a health app is a docs/13 question, not a UI one |
| "230 burned" / "825 burned" calories | needs activity tracking (E4); showing it before it exists is a made-up number |
| Activity section (bicycling, bowling) | workout tracking is out of scope per docs/02 |

⚠️ **`ref_pro/` is GPL-3.0.** OpenNutriTracker's layout may be looked at for direction; its code
must not be copied into this repo, which would place the whole app under GPL. Nothing here is
derived from its source.

The visual language — dark surfaces, cards, big numbers, generous radii — is adopted in full. The
information architecture is not.
