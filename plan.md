# Gym section — plan and tracker

A box is ticked only after the check written against it has actually passed.
Governing decisions: ADR-013 (`docs/07-adr-log.md`), D-241 … D-245 (`docs/DECISIONS.md`).

## What we are building

A Gym section inside Eatzify, modeled on the behaviour of openGym (`../openGym-main`). openGym is
AGPL-3.0, so none of its code is copied (ADR-012). It is used as a behavioural spec, and every line
here is our own.

| Decision | Choice |
|---|---|
| Placement | A Gym hub screen, reached from a "Today's workout" card on Home and a Gym tile on You. The bottom bar is unchanged (CLAUDE.md rule 1) |
| Calories | A **Workout kcal** estimate, computed on the server as `(MET − 1) × kg × hours`. Kept as its own field end to end; Home adds it to the device's burned figure for display and names the workout share beneath (D-246, amending D-242). It never changes "kcal left" |
| Exercise media | No GIFs ship: they are © Gym visual and need a licence. Each exercise shows an icon, a muscle map, tags and how-to steps. `GYM_MEDIA_BASE_URL` switches media on — the library row, the exercise sheet and the workout screen all render it when it is set (added 2026-09-20 for a licence evaluation; the licence itself is still open) |
| Scope | Core, plus progression and 1RM, supersets/timed/per-side/cardio, heatmap and muscle map, effort (RIR/RPE), and a workout-day reminder |
| Tier | Free for everyone |
| Data | Exercise metadata comes from `hasaneyldrm/exercises-dataset` (MIT, attribution kept). Body-map outlines come from `melihcolpan/MuscleMap` (MIT) |

## Study summary — openGym, feature by feature

**Library.** 1,324 exercises, covering 10 body parts, 28 equipment types and 19 target muscles.
- Search matches the name, target muscle and equipment.
- The body-part chip resets the equipment chip. Equipment chips come from whatever the current filter leaves.
- Results page in 40s.
- A "★ Chosen" chip lists exercises already used.
- Custom exercises need a name and a body part; the description is optional.

**Plan.**
- A weekly schedule assigns each day, Mon–Sun, a routine or rest.
- Any single date can be overridden with a routine, rest, or "back to weekly".
- A routine has a name, an icon, a progression rule and a list of exercises.
- Each exercise in a routine has a mode (reps, time or cardio), sets, reps, kg, seconds, minutes, km/h, bodyweight, per-side, a rule override, a step, a rep range and a superset link.
- A starter plan is included: Push on Mon, Pull on Wed, Legs on Fri.

**Guided workout.**
1. Start today's routine, another routine, or a freestyle session.
2. A weigh-in step: save and start, skip, or choose a different routine.
3. Sets are prefilled from the last session, then the progression rule applies with its "why".
4. Checking a set beeps, vibrates, and starts rest only between sets. The rest bar has −15 s, +15 s and Skip.
5. Timed sets use their own work timer.
6. The user confirms the working weight.
7. Finish, with a confirmation if the session ended early or is empty.
8. Summary: duration, volume, sets, PRs, 1RM records, what was trained, and **workout kcal**.

**Training logic.**

*Progression rules:*
- Linear.
- Greyskull LP: AMRAP last set, and double the step when reps reach 2× the target.
- Double progression through the rep range.
- Add time.
- Deload ×0.9 after 3 stalls (1 stall for Greyskull).
- Bodyweight: +1 rep per hit. At the rep ceiling, add a set, up to 6 sets.

*Numbers:*
- Epley 1RM, used only when reps ≤ 12.
- A PR is a done set heavier than every earlier best.
- Volume = Σ w × r.
- Streak = consecutive ISO weeks with at least one workout.

**Stats.**
- Tiles.
- A 12-month heatmap, shaded by minutes trained.
- Muscle balance: front and back body map, week/30d/90d/all, primary 1.0 and secondary 0.4, a "hard sets" filter, and muscles not trained.
- Effort: RIR or RPE average, % hard, weekly line, histogram.
- Per-exercise chart: top set, e1RM or effort.
- History and a calendar.

**Not ported:**
- passkeys, self-hosting and the openGym admin;
- 12 languages (we do en + hi);
- accent themes;
- importers from other apps;
- plan sharing and PDF.

## Tracker

### Phase 0 — Decisions and docs
- [x] `plan.md` (this file)
- [x] ADR-013 in `docs/07-adr-log.md`: workout tracking in-house, reversing docs/02 "out of v1" and docs/17:61
- [x] DECISIONS D-241 … D-245: placement, workout kcal (partial reversal of D-80), no GIF media, clean room plus dataset licences, free tier

### Phase 1 — API foundation *(check: migration runs, 1,324 library rows, jest green)*
- [x] `api/scripts/build-exercise-library.ts` → `api/config/exercises/library-v1.json` + `NOTICE.md`
- [x] Migration `AddGym`: `energy_reference`, `exercise`, `gym_profile`, `gym_routine`, `gym_workout`, with the seeds
- [x] Entities and `GymModule` registered in `app.module.ts`
- [x] `GET /gym/exercises`, plus custom exercise create, edit and delete
- [x] Tests

### Phase 2 — API plan *(check: jest + curl)*
- [x] Routines CRUD, starter plan
- [x] Weekly schedule, day overrides, settings
- [x] `GET /gym` overview with today and the current week resolved on the server
- [x] Tests

### Phase 3 — API training *(check: table-driven jest)*
- [x] `progression.ts` (linear, greyskull, double, time, bodyweight, deload)
- [x] `workout-records.ts` (volume, PRs, e1RM, working weights, streak)
- [x] `workout-energy.ts` (MET, weight source, set cap)
- [x] `POST /gym/workouts` (idempotent), list, detail, delete; session plans in the overview
- [x] Tests

### Phase 4 — API stats and integration *(check: full `npx jest` green)*
- [x] `GET /gym/stats`, `GET /gym/calendar`, `GET /gym/exercises/:id/progress`
- [x] `GET /logs/day` → `activity.workout_kcal`
- [x] Privacy erase and export cover the gym tables
- [x] AdminJS: exercise + energy reference editable
- [x] Tests

> **API verified 2026-09-19:** `npx jest` 699/699 green (59 suites, 61 new gym tests). The migration
> ran on the dev database: 1,324 library rows, 33 energy rows. A live smoke run on a test instance
> (`:3005`, synthetic phone) passed the starter plan, an idempotent save (261 kcal = hand-computed),
> progression 40 → 42.5 kg, overrides, stats, calendar and `/logs/day` `workout_kcal`. Not done:
> Testcontainers constraint tests (Testcontainers is not installed in this repo).

### Phase 5 — App data layer *(check: domain + datasource tests)*
- [x] Entities (`domain/entities/gym/`)
- [x] `GymRepository`, remote datasource, Hive local datasource (`core/storage/hive_boxes.dart`)
- [x] `WorkoutSession` state machine, `estimateOneRm`
- [x] Fakes and tests

### Phase 6 — App hub and library *(check: widget tests, four states)*
- [x] `GymPage` with the Today · Routines · Exercises · Stats tabs
- [x] Today tab
- [x] Exercises tab, detail sheet, custom exercise sheet
- [x] Home "Today's workout" card, You-tab Gym tile

### Phase 7 — App plan editing
- [x] Routines tab: schedule, routine list, starter plan
- [x] Routine editor, exercise config sheet, supersets, reorder
- [x] Day override sheet

### Phase 8 — App guided workout
- [x] Weigh-in sheet (writes a weight measurement)
- [x] Workout screen: set rows, steppers, prev/next, add exercise
- [x] Rest timer, work timer, notification while backgrounded, wakelock, sound and haptics
- [x] Working-weight sheet, finish dialogs, summary with kcal
- [x] Offline: active workout survives a restart; an unsent workout retries

### Phase 9 — App stats
- [x] Stats tab: tiles, heatmap, muscle map, effort, exercise progress
- [x] History, workout detail, calendar
- [x] Gym settings page

### Phase 10 — Calories and reminders
- [x] Home calorie card: workouts counted in the burned figure, with "Includes workouts · ~N kcal" beneath (D-246)
- [x] Progress: workout kcal week bars
- [x] Workout-day reminder

> **Three bugs the on-device run found, each now covered by a test that fails without its fix:**
> 1. Opening the Gym while its plan had failed to load wrote an observable inside `initState`,
>    marking Home's card dirty mid-build ("setState() called during build"). `GymController.load`
>    now yields before its first write.
> 2. The weekly-schedule and settings rows sat on a decorated card with no `Material` of their own,
>    so Flutter refused to paint their ink.
> 3. The muscle map drew nothing: a `CustomPaint` with no child is laid out at zero height. It now
>    asks for `Size.infinite`.
>
> **Fourth, from the product owner's own run (2026-09-20):** a day with nothing planned offered only
> "Freestyle workout", so reaching a routine took a weigh-in and two more taps. Both the Today card
> and Home now put "Start a workout" first, and it opens the routine chooser (freestyle included)
> before the weigh-in.
>
> **App verified 2026-09-19:** `flutter test` 882/882 green (29 data and domain tests plus 28 Gym
> widget, domain, body-map and reminder tests added). `flutter analyze lib test` shows no new notes: the 14
> infos are all in files that predate this work. The four states are tested on Today and Stats; the
> workout screen and Today tab are tested at 200 % text and in dark mode.

### Phase 11 — Polish and verify
- [x] Hindi strings (379 gym keys, en + hi, generated together so they cannot drift)
- [x] 200 % font and dark mode tests
- [x] `flutter analyze lib test` clean (no new notes) · `flutter test` 882 green · `npx jest` 699 green
- [x] Simulator run against the local API, full workout, 16 screenshots (`integration_test/gym_flow_test.dart`)
- [x] `docs/PROJECT-STATE.md`, `docs/09-api-spec.md` §5a, `docs/13` §6 updated

## Not done locally

Release builds talk to the production API. That API only has the gym endpoints once the backend is
deployed, and CI deploys on a push to `main`. Nothing is committed or pushed without the product
owner's go-ahead.
