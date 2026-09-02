# 21 — Progress dashboard: what the backend still owes it

**Status: needs backend work.** The Flutter side of the Progress dashboard (D-143) is built
against today's API and fills every gap it honestly can. This doc is the complete list of what
the server must add for the screen to match the reference mock fully and cheaply. Endpoint shapes
here are sketches — final contracts land in `docs/09-api-spec.md` when built.

The governing constraints, restated because every item below bends around them:

- **Rule 2** — the server decides; the app renders. The app may do display arithmetic (a mean of
  server sums), never invent a target, threshold or judgement.
- **Rule 8** — diary dates are the server's. The app anchors every window on the diary date the
  server returns for "today" and only steps backwards from it.
- **docs/05 §6** — no failure framing. No streaks or badges on weight, no red on a past day.

## 1. Weekly summary endpoint — replaces a 14-request fan-out (highest value)

The calorie card, macro balance card and the This-week/Last-week pill are fed today by the app
calling `GET /diary?date=…` **fourteen times** (today + 13 days) on every Progress open, then
averaging client-side in `ProgressController`. It works, it is honest, and it is the wrong place
for both the traffic and the arithmetic.

Wanted:

```
GET /progress/summary?days=14            (or ?from=YYYY-MM-DD&to=YYYY-MM-DD)
```

```jsonc
{
  "anchor_date": "2026-09-01",           // the server's "today" (rule 8)
  "days": [                               // one row per diary day, oldest first
    {
      "diary_date": "2026-08-19",
      "logged": true,                     // anything at all recorded that day (see §2)
      "kcal": 1420, "protein_g": 61, "carb_g": 148, "fat_g": 39,
      "target_kcal": 1500                 // null when no plan governed that day
    }
  ],
  "avg": { "kcal": 1237, "protein_g": 68, "carb_g": 160, "fat_g": 38 },   // fed days only
  "prev_avg": { "kcal": 1156, ... },      // the window before — null when nothing to average
  "targets": { "kcal": 1500, "protein_g": 99, "carb_g": 183, "fat_g": 42 }
}
```

Decisions the server must own (currently made client-side and documented in the controller):

- **A day with no diary is absent/unlogged, never zeroes** — averaging in an empty plate
  fabricates one.
- **Averages divide by fed days**, not by seven.
- `prev_avg` null ≠ 0% change. The app hides "vs last week" when it is null.

Until this ships the app keeps the fan-out; when it ships, `ProgressController.loadWeeks()` and
its aggregate getters collapse to one request and a pass-through.

## 2. Logged-dates endpoint (already named by D-138)

The consistency card and Home's streak count "days with anything logged". The app reconstructs
this from measurement histories (water/steps/burned each carry `diary_date`) **plus** today's
diary — but a past day where the user only logged FOOD is invisible to it, so such a day shows
as a neutral hollow circle it did not earn.

Wanted:

```
GET /diary/logged-dates?days=90
→ { "dates": ["2026-08-30", "2026-08-29", …] }     // any logging: food, water, steps, weight
```

The `logged` flag in §1 covers the 14-day window; this endpoint covers the 90-day streak depth.

## 3. Windowed weight change — ✅ SHIPPED (D-158)

`GET /measurements/*` now returns `change_30d` beside `change`: `windowedTrendChange` applies the
same moving-average discipline to only the last 30 diary days, and the app's weight sentences
prefer it, falling back to since-start when the window has no trend. Implemented as:

```jsonc
{ "kind": "weight", "points": [...], "change": -4.2, "change_30d": -1.8 }
```

Same moving-average discipline as `change` (never raw min/max); null when the window has too
little data, and the app then falls back to the since-start sentence.

## 4. Achievements — blocked on product + clinical sign-off, then an endpoint

The mock shows an Achievements card (hexagon badges: "7 Day Streak", "Weight Down −2 kg",
"Calorie Goal 5x"). **Not built**, deliberately:

- "Weight Down −2 kg" is a badge on weight loss. docs/05 §6 bans streaks/leaderboards on weight
  and any framing where regaining reads as failure — a weight badge is that, one step removed.
  Needs an explicit clinical-safety decision before it exists anywhere.
- The other two ("7-day logging streak", "calorie goal met N times") are logging/adherence
  achievements, consistent with the tone rules — but the server must award them (rule 2): the
  app must never compute "goal met 5x" from data it happens to hold.

Wanted, once product decides the set:

```
GET /achievements
→ { "achievements": [ { "kind": "logging_streak_7", "earned_at": "2026-08-28", "params": {"days": 7} } ] }
```

`kind` is a closed enum (rule 4: wire value, l10n on screen). Until then the dashboard simply has
no Achievements card, and the consistency card carries that corner of the layout.

## 5. Longer periods for the picker

The period pill offers This week / Last week — the two windows the fan-out can afford. The mock's
pill implies more (This month, custom ranges). That follows free once §1 takes `from`/`to`;
client work is only menu items.

## 6. Adjacent, from Home (D-142): per-entry food images

Home's meal cards reserve the mock's photo slot but `LogEntry` carries no image on the wire.
Add `image_url` + `image_attribution` per diary entry (the foods table already has both;
`FoodImage` on the client already renders and credits them).

## Priority order

| # | Item | Unblocks | Effort signal |
|---|---|---|---|
| 1 | §1 weekly summary | calorie + macro cards without 14 GETs; real prev-week delta | one query + one mapper |
| 2 | §2 logged-dates | truthful streak + consistency for food-only days | trivial query |
| 3 | §3 `change_30d` | mock's exact weight sentence | small |
| 4 | §6 entry images | Home meal-card photos | column pass-through |
| 5 | §4 achievements | Achievements card | product + clinical first |
| 6 | §5 longer periods | month view | free after §1 |

## 7. Profile screen (D-144) — the mock's remaining tiles

The Profile mock asks for figures the API does not yet serve:

- **Member since** — the account's creation date is not in `GET /profile`. Add `created_at`.
- **BMI** — the client may not compute it (rule 2). If product wants it, the server sends
  `bmi` (and any band label goes through the docs/05 clinical-tone review first: "Normal/Obese"
  chips are §6's own banned example).
- **Body fat % / muscle mass** — no measurement kinds, no source device integration. Needs a
  product decision on where these numbers would even come from before an endpoint means anything.
- **Reminders** — the mock's quick action implies a reminders feature; nothing exists server-side.

Until then the Profile screen shows the weight card only, and no judgement chips anywhere.
