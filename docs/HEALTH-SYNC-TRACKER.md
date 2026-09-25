# Health platform sync — tracker

What this app reads from **Health Connect** (Android) and **HealthKit** (iOS), what it deliberately
does not read, and how far each one has got.

Governing rule: `CLAUDE.md` rule 10 — read-only, behind `HealthRepository`, **never Google Fit** (its
APIs shut down at the end of 2026), manual entry always available as a fallback, and the data-source
label always visible.

Plugin: `health: ^13.3.1`. Where this file says "the plugin does X", it was verified against the
installed source at `~/.pub-cache/hosted/pub.dev/health-13.3.1/`, not against its README — the README
is stale in several places (see §4).

**Status ladder:** `not started` → `built` (code, tests and both platform builds pass) →
`checked` (read from a real Health Connect / HealthKit store, stored by the server, shown in the app
with its source label). Each platform is tracked separately, and the column says what it was checked
on — an emulator runs the real Health Connect service, but it is not a phone.

Last updated **2026-09-17** — decisions D-214 to D-221.

---

## 1. Wired

| Metric | Server kind | Unit | iOS type | Android type | Android permission | iOS | Android | Shown on |
|---|---|---|---|---|---|---|---|---|
| Steps | `steps` | `steps` | `STEPS` | `STEPS` | `health.READ_STEPS` | **checked** — iPhone 15 Pro + Watch S10 | **checked** — Android 16 emulator | Home, Progress, widget, coach |
| Calories burned | `energy_burned_kcal` | `kcal` | `ACTIVE_ENERGY_BURNED` | `ACTIVE_ENERGY_BURNED` | `health.READ_ACTIVE_CALORIES_BURNED` | **checked** — iPhone 15 Pro + Watch S10 | **checked** — Android 16 emulator · ⚠ Samsung Health never supplies it (§3) | Home, Progress, widget, coach |
| Distance walked | `distance_m` | `m` | `DISTANCE_WALKING_RUNNING` | `DISTANCE_DELTA` | `health.READ_DISTANCE` | **checked** — iPhone 15 Pro + Watch S10 | **checked** — Android 16 emulator | Progress (as km), coach |

What each check covered, and the two still open on a real Android phone, are in §6.

Read via `getHealthIntervalDataFromTypes(interval: 86400)` — one bucket per diary day, over the
`[start, end)` window the **server** supplies (rule 8; the 04:00 IST boundary is never computed on the
phone).

### Why these three and not others

`docs/02-prd.md` FR-3.4 sanctions steps only, and its Out-of-v1 list says *"wearable integrations
beyond steps"*. Distance and active calories go past that line deliberately, on the product owner's
call — recorded in `DECISIONS.md`. They are the rest of the same walk, at the same sensitivity as a
step count, and both map onto measurement kinds the server already understands.

---

## 2. Read but not stored

Nothing. Every reading the app takes is written; there is no metric read only to derive another.

---

## 3. Deliberately not read

This section exists so the question *"what else could we take from Health Connect?"* stays answered
instead of being re-derived every few months. Nothing here is blocked — each row says what it would
cost.

> **Before adding any of these:** the coach progress endpoint returns *every* measurement kind under
> the `progress` scope, with no allow-list (D-214). A new kind reaches coach_l2 and coach_l3 the
> moment it exists. For sleep, heart rate, blood pressure or glucose that is a `docs/10` decision
> that has to be made first, not a side effect to discover afterwards.

| Not read | Why | What it would take |
|---|---|---|
| **Exercise / active minutes** | No clean aggregate path in plugin 13.3.1. `EXERCISE_TIME` is iOS-only **and** is not a quantity type on iOS, so the interval API rejects it with `INVALID_TYPE`. Android's aggregate map has no exercise-session entry. | Reading `WORKOUT` samples instead — but the plugin's Android workout path fires three extra `readRecords` calls *per session* and raw-sums them un-deduplicated, so a phone and a watch logging one workout double-count. Needs a hand-written aggregate or a plugin fix. |
| **Active calories on Samsung phones** | **Samsung Health (7.00) never writes them.** Its Health Connect permissions include `WRITE_TOTAL_CALORIES_BURNED` and `WRITE_BASAL_METABOLIC_RATE`, and no `WRITE_ACTIVE_CALORIES_BURNED` at all (checked on a Galaxy A06). A Samsung user's burned calories therefore never arrive from Health Connect; they stay manual. Decided to keep it that way (D-217): showing total as "burned" would put a 1,500+ kcal resting figure on Home. | Active = total − basal, derived on the phone. The plugin has no basal aggregate, so it needs a small native Kotlin call to Health Connect's `BASAL_CALORIES_TOTAL`, then a Samsung device to verify it against Samsung Health's own active figure. |
| **Total / basal calories** | `TOTAL_CALORIES_BURNED` and `BASAL_ENERGY_BURNED` include BMR, and the plan's TDEE already contains BMR. Storing either would count resting metabolism twice and inflate every burn figure by roughly 1,400–1,800 kcal a day. | Nothing — this one is a correctness decision, not a gap. It should stay unread. |
| **Weight** | The kind already exists and the platform can supply it from a smart scale. Left out of this pass to keep the privacy surface identical to steps. Weight is the most emotionally loaded number in the app (`docs/05` §6), so it deserves its own decision rather than arriving as a side effect. | `HealthDataType.WEIGHT`, one permission, one row in the metric enum. `canOverwrite` already protects a hand-typed weight from a device write, so the hard part is done. |
| **Blood pressure** | `bp_sys` / `bp_dia` kinds exist and a paired cuff can supply them, but BP is clinical data — it needs a `docs/10` matrix row of its own, not the steps row. | Two metric rows, `health.READ_BLOOD_PRESSURE`, and a masking decision about which coach level may see it. |
| **Sleep** | The most sensitive reading in the set, and the plugin's sleep types differ per platform (`SLEEP_IN_BED` is iOS-only; `SLEEP_SESSION` / `SLEEP_OUT_OF_BED` are Android-only), so "sleep duration" is not one number across platforms. | A new kind, a per-platform variant mapping, a `docs/10` row, and a consent-scope decision. |
| **Resting / continuous heart rate** | Same sensitivity argument as sleep. Also a live trap: Android aggregates `HEART_RATE` to `MEASUREMENTS_COUNT` — a *sample count*, not a bpm average — so the obvious implementation silently stores the wrong number. | A new kind, `RESTING_HEART_RATE` (which does aggregate correctly), a `docs/10` row. |
| **Blood glucose** | Clinical. `hba1c` exists as a kind but is a lab value, not a platform reading, so there is no mapping. | A new kind plus a clinical-safety review. |
| **Workouts (type, sets, reps)** | No workout log exists anywhere in the schema — no table, no entity, no endpoint. This is a feature, not an integration. | Its own epic. |
| **Floors climbed, VO2 max, body fat, skin temperature** | Nothing in the app consumes them. YAGNI. | A kind each, and a screen that uses them. |

---

## 4. Platform notes worth keeping

Things that cost time to discover and would cost it again.

- **`getHealthAggregateDataFromTypes` is broken in 13.3.1.** iOS has no matching native case
  (`MissingPluginException`); Android's Dart side sends `dataTypeKeys` / `activitySegmentDuration`
  while its Kotlin side reads `dataTypeKey` / `interval` with `!!` (`NullPointerException`). Use
  `getHealthIntervalDataFromTypes`. It is absent from the README and the example app, which is the
  tell.
- **`getTotalStepsInInterval` cannot express absence.** It returns `0` for "no samples" on both
  platforms, so it cannot distinguish *nobody measured* from *they did not move* — the invariant this
  codebase cares most about. The interval API can: no samples produces **no bucket**, while a genuinely
  idle day produces a bucket carrying `0`.
- **Never sum raw samples for a daily total.** Only `getTotalStepsInInterval` and
  `getHealthIntervalDataFromTypes` get platform-level cross-device de-duplication. An iPhone and an
  Apple Watch both record the same walk.
- **`hasPermissions` returns `null` on iOS for reads.** Apple will not disclose a read grant, because
  the answer itself leaks whether the user has the data. Treat `null` as *unknown — attempt the read*.
  Treating it as `false` silently disables sync on iOS entirely.
- **`MainActivity` must extend `FlutterFragmentActivity`.** The plugin needs
  `registerForActivityResult`; with the default `FlutterActivity` the Health Connect permission
  request fails at the cast. Most common breakage in this integration.
- **Per-platform type mapping is mandatory.** `DISTANCE_WALKING_RUNNING` is iOS-only,
  `DISTANCE_DELTA` is Android-only; one shared list throws at runtime.
- **`getTotalStepsInInterval(includeManualEntry: false)` can *increase* the count on Android** — it
  abandons the de-duplicated aggregate for raw summation. Also, manually-added steps do not reliably
  carry `RecordingMethod.manual`, so the filter does not do what it says.
- **Android sends an empty bucket as a 0.** Its interval code writes `value: totalValue ?: 0` for a
  bucket nothing was recorded in. The tell is `sourceName`: a bucket no app contributed to has an
  empty one, and a real reading — even a real zero — never does. iOS simply leaves empty buckets out
  (and names no source on a total, so the check must not run there).
- **`interval: 86400` reaches Kotlin as an `Integer`**, while the plugin reads it as `Long`. Checked by
  compiling the same pattern: Kotlin unboxes through `Number`, so it works. Not a landmine.
- **Confirmed on a real Health Connect (Android 16):** a 30-day interval read returns a bucket for
  **every** day, most of them `0` with an empty source. The empty-bucket filter is what stops 30 days
  × 3 metrics of false zeros reaching the server. A day with a real `0` (seeded active energy) came
  back with its source named, and was kept.
- **Health Connect de-duplicates across apps in its aggregate.** Two apps writing the same 3,000-step
  walk: raw records sum to 6,000, the interval read returns 3,013 (the extra 13 were the emulator's own
  step sensor), matching Health Connect's own "Data totals" screen.
- **Test trap, not an app bug:** an app granted *write* permission with `adb shell pm grant` is not
  counted in aggregates until Health Connect's priority list is materialised (opening
  Data and access → Activity → Data sources and priority does it). Until then every bucket reads 0. A
  real user grants through Health Connect's own sheet, which does this immediately — confirmed by
  revoking Eatzify and connecting again: the first backfill wrote everything.
- **Health Connect launches the privacy link explicitly**, so the intent-filters need no
  `DEFAULT` category — and `adb shell am start -a …RATIONALE` therefore reports "unable to resolve".
  Test with `cmd package query-activities` or an explicit `-n`. On Android 14+ the alias requires
  `START_VIEW_PERMISSION_USAGE`, which only the system holds, so only Health Connect can open it.
- **Health Connect allows 30 days of history from grant** unless `READ_HEALTH_DATA_HISTORY` is
  requested. The backfill is 30 days, so that permission is deliberately not declared.

---

## 5. When the app reads, and what wins

| Trigger | Asks for access? | Days | May replace a typed figure? |
|---|---|---|---|
| Home loads, app resumes | Never | Today | Never (D-97) |
| **Connect** or **Sync** tapped — Home button, the one-time sheet, or the Health data screen | If not already granted | Last 30, today included | **Today only** (D-218) |

Steps typed on the `+` sheet are an **addition**, stored as `steps_added` beside the device's count
(D-221). Neither trigger touches it: the day shows device + addition, so a sync after "add 500"
still has the 500 on top.

The one-time sheet appears the first time a sync finds nothing connected, once per account. After
"Not now" it does not come back; the Connect button under the day's activity stays.

---

## 5a. Not built, and the upgrade path

**Background sync.** There is none: no `workmanager`, no `BGTaskScheduler`, no `UIBackgroundModes`.
Sync runs on app foreground and on resume. On iOS the plugin has no background delivery at all (its
`*HealthDataInBackground*` methods are Android-only stubs that hardcode a return on iOS); on Android
it would need `health.READ_HEALTH_DATA_IN_BACKGROUND` plus a Play Store declaration. Add it when
users report missing days despite opening the app — foreground-on-resume covers the common case.

**A consequence worth knowing:** the home-screen widget's figures are published by the app, so they
are as fresh as the last time the app ran. That is already true today and this work does not change
it.

---

## 6. Implementation log

### Built — 2026-09-17

| Area | What | Where |
|---|---|---|
| iOS | HealthKit entitlement; share-usage text widened; no write string; CMPedometer channel deleted | `ios/Runner/Runner.entitlements`, `Info.plist`, `AppDelegate.swift` |
| Android | `FlutterFragmentActivity`; three read permissions; `<queries>` for Health Connect; the "privacy policy" link on the permission screen opens the policy (API < 34 and ≥ 34) through a translucent activity rather than booting the app | `MainActivity.kt`, `PrivacyPolicyActivity.kt`, `AndroidManifest.xml`, `res/values/config_strings.xml` |
| Adapter | Per-platform type mapping; interval reads; Android empty-bucket filter; three-state permission; per-type Android checks | `lib/data/repositories/health_repository_impl.dart` |
| Sync | Today on load and on app resume; 30-day backfill on connect; manual steps never overwritten; in-memory de-duplication | `lib/domain/usecases/sync_health.dart` |
| Screen | "Health data" on the You tab — what is read and not, connect, install, fill in; Home offers it where steps would be | `lib/presentation/features/account/health_connect_page.dart` |
| Server | `distance_m` kind; `POST /measurements/bulk`; `GET /logs/windows`; unique-index race retried | `api/src/measurements/`, `api/src/logs/`, `api/src/plans/diary-date.ts` |
| Surfacing | Distance on Progress (km) and the coach's charts; coach label for `energy_burned_kcal` fixed; every habit card on Progress names the source of its headline figure (rule 10 — it did not, for any habit) | `progress_page.dart`, `client_progress_section.dart` |

**Verified:** Flutter 638 tests, API 373 tests (23 of them in `api/test/health-sync.spec.ts`),
`flutter analyze` with no errors or warnings, signed `flutter build ios --debug`, and
`flutter build apk --debug`; the merged Android manifest carries exactly the three health permissions.

Contract tests that fail if a platform file drifts: `test/health_metric_contract_test.dart` (server
kinds and units, plugin type lists, manifest permissions, fragment activity, HealthKit entitlement).

### Device checks — 2026-09-17

How they were run: the app with a temporary debug-only log (removed afterwards) that printed, for
today, the de-duplicated total the app sends beside the raw per-source sum, plus the local database.

**iPhone 15 Pro (iOS 26.6.2) paired with an Apple Watch Series 10** — the real user's own data.

- [x] **Not double-counted.** Today: Watch 456 + iPhone 360 = 816 raw; the app sent **456**. Distance:
      283 + 218 = 501 raw; the app sent **283**. HealthKit's statistics query de-duplicates by source
      priority, as intended.
- [x] **Burned is active, not total.** 29 days backfilled: average **175 kcal**, highest 431. A total
      would have been 1,500+.
- [x] **Backfill on connect.** 28 days of steps, 29 of energy, 30 of distance — the gaps are exactly the
      days with a hand-typed figure.
- [x] **Hand-typed figures survive.** 16 Sep (10,000 typed) and 17 Sep (200 typed, Watch says 456) kept
      the typed value; so did 17 Sep's typed 100 kcal.
- [ ] The on-screen label was not photographed on the iPhone (no screen capture over a wireless
      link). The label code is shared with Android and covered by widget tests.

**Android 16 emulator (Pixel 9a image, real Health Connect service)** — seeded by two throwaway apps
writing the same walk, as a phone and a watch would.

- [x] Home offers "Connect Health Connect to fill in your steps"; the link opens Health data; Connect
      shows Health Connect's own sheet with exactly **three** read items.
- [x] **De-duplicated:** 6,000 raw steps → **3,013** sent; 4,200 m → **2,110 m** — equal to Health
      Connect's own totals screen.
- [x] Yesterday's 5,000 steps backfilled; a seeded genuine **0 kcal** kept; a day with nothing sent
      nothing; ~85 empty zero-buckets dropped.
- [x] Home shows **3013 · Health Connect** and **150 burned**; Progress shows **2.1 km** under
      "Distance walked" with its source; the connect link disappears once connected.
- [x] Home's resume sync and the connect backfill ran at the same moment — five rows, no duplicate, no
      500 (the D-216 retry, exercised for real).
- [x] The "privacy policy" link on the sheet opens `ViewPermissionUsageActivity`, which opens the policy
      URL in Chrome.

**Android 13 emulator (Play Store image, Health Connect not installed)**

- [x] Health data offers **"Get Health Connect"** — the `<queries>` entry and SDK-status check work on a
      real Android 13 system — and the button opens the Play Store.
- [x] Home does not offer to connect (sync says "unavailable", not "not permitted").
- [x] Health Connect's rationale intent resolves to `PrivacyPolicyActivity`, which opens the policy URL.
- [ ] Installing Health Connect and coming back — needs a Google account on the emulator, or a real
      Android 9–13 phone. The re-check on return is covered by the controller's resume handler.

**Galaxy A06 (Android 16), the real phone**

- [x] Health Connect had no data (Samsung Health was not connected), and the app stored **nothing** —
      no zeros. The resume sync fired.
- [ ] **A real walk from Samsung Health.** Samsung Health has never been set up on this phone (it sits
      on its first-run terms screen); accepting its terms is the owner's call. After setup, walk a
      little, open Samsung Health once, then open Eatzify — steps and distance should appear with
      "Health Connect". Calories will not (§3).
- [ ] Partial grant (untick one type) and "Don't allow" were not run on a device; both are covered by
      adapter and widget tests.

### Release — not code

- [x] **Apple Developer portal:** a signed build registered HealthKit on App ID `app.eatzify` for team
      W9U8428973; the new profile and the signed app both carry `com.apple.developer.healthkit`.
      ⚠ That team is a **personal (free) team** — its profiles last 7 days. An App Store build needs
      the same capability on the paid program team's App ID.
- [ ] **Privacy policy page.** `https://eatzify.app/privacy` does not resolve today. Health Connect and
      Google review open it from the permission screen, so it must be live, and must describe what is
      read from Health Connect and HealthKit, before release (also `docs/19` Q15). The URL is one
      string in `android/app/src/main/res/values/config_strings.xml`.
- [ ] **Play Console health declaration** — only the account owner can submit it. Drafted answers:

| Question | Answer to give |
|---|---|
| Health Connect data types | Steps, Distance, Active calories burned — **read only**, no write. |
| Why each is needed | Steps and distance show the user's daily activity on their diary and progress screens next to their meal plan. Active calories burned is shown beside calories eaten as its own figure (never subtracted from it). |
| Core functionality? | Yes — daily activity tracking is part of the diet and progress features; manual entry remains available. |
| When is data read | Only while the app is in the foreground; last 30 days on first connect. No background access is requested. |
| Where it goes | Stored on Eatzify's servers to show the user their own history. Visible to a coach **only** when the user grants that coach access (and can revoke it). Not sold, not used for advertising, not used for credit or insurance decisions. |
| Privacy policy | `https://eatzify.app/privacy` — once published, with a Health Connect section. |
| Data safety form | Declare *Health and fitness → Fitness info* as collected, and as shared (user-initiated, with a chosen coach). |
