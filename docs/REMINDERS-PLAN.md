# Reminders — plan (on the phone, no backend)

Status: **built** (D-222) — water, meal logging and end of day · 2026-09-17 · governing docs: `docs/14` §6 (a "reminders" screen
under You), `docs/15` (the old build's reminder defects), `docs/05` §6 (tone).

## Why on the phone

A reminder that the server sends needs a scheduler that wakes up for every user, every hour, plus
FCM. A reminder the phone schedules costs nothing per user and still fires with the app closed, in
airplane mode, and after a restart. For "drink water every two hours" the server adds nothing.

What is already here:

- `flutter_local_notifications` 18.0.1 and `timezone` 0.10.1 are in `pubspec.yaml`, unused.
- Android core-library desugaring, which the plugin needs, is already on.
- `firebase_messaging` is declared but never initialised, and there are no Firebase config files,
  so nothing competes for the notification delegate.
- The profile already has `wake_time` and `sleep_time`, which give the default quiet hours.
- `hive_ce` is a dependency, but `core/storage/hive_boxes.dart` (rule 11) does not exist yet.

## 1. Water reminders — how they work

### Settings, kept on the phone

| Setting | Default | Choices |
|---|---|---|
| On/off | **off** until the person turns it on | — |
| From / until | profile `wake_time` / `sleep_time`, else 08:00 / 22:00 | any time, 15-minute steps (docs/15 disliked hourly-only presets) |
| Every | 2 h | 1 h · 1½ h · 2 h · 3 h |
| Stop once today's target is met | on | on / off |

These live in a Hive box `reminders`, declared in the new `core/storage/hive_boxes.dart`. They are
per phone: a new phone starts with reminders off. If reminders should follow the account later,
that is one small `PATCH /profile` field.

### Scheduling: one-time notifications for the next 7 days, planned again on every open

- A pure planner, `domain/usecases/plan_water_reminders.dart`, takes the settings, the time now,
  and today's water (logged and target). It returns the list of times. No Flutter and no plugin in
  it, so every rule gets a plain unit test.
- The planner is re-run, cancelling the old reminders and scheduling the new list, when:
  - the app opens or comes back to the foreground;
  - water is logged, whether from Home, the `+` sheet, the Android widget's background glass, or
    the notification's own button;
  - the settings change.
- **7 days × at most 8 a day stays under iOS's limit of 64 pending notifications.** The planner
  caps the list at 60 and drops the furthest-away days first.
- **When today's target is met, the rest of today's reminders are cancelled.** A daily repeating
  notification can't do this; one-time notifications can.
- **After a week without opening the app, the reminders stop.** That is deliberate: nagging someone
  who stopped using the app is how the app gets uninstalled. The settings screen says so.

### Android

- Use `AndroidScheduleMode.inexactAllowWhileIdle`. A water reminder a few minutes late is fine.
- **Do not use exact alarms.** `SCHEDULE_EXACT_ALARM` needs the user to grant it on Android 12+, and
  Play only allows `USE_EXACT_ALARM` for alarm and calendar apps.
- Add to the manifest:
  - `POST_NOTIFICATIONS`, asked for at runtime on Android 13+.
  - `RECEIVE_BOOT_COMPLETED`.
  - The plugin's `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` and
    `ActionBroadcastReceiver`. The boot receiver restores the schedule after a restart.
- Use one channel, "Water reminders", at default importance: a sound, but no heads-up banner. The
  person can silence it from system settings.

### iOS

- In `AppDelegate`, set `UNUserNotificationCenter.current().delegate` so a reminder still shows
  while the app is open.
- Ask for permission (alert and sound; no badge) when the person turns reminders on, **never at
  launch** — the same rule the health prompt follows (D-218).

### Time zone

`timezone` needs the phone's IANA zone name, for example `Asia/Kolkata`. Use `flutter_timezone`
(one small, widely used package) so a reminder follows the phone's clock when someone travels.
The alternative is to hard-code `Asia/Kolkata`: no new package, but wrong outside India.
**Recommended: `flutter_timezone`.** It is the only new dependency in this plan.

### The notification

- Title: "Time for some water". Body: "A glass now keeps the day on track."
- No numbers in the text. A reminder scheduled days in advance can't know today's total, and a
  stale "0 ml so far" reads as a failure. Also no "you haven't…" and no "you forgot…" (docs/05 §6).
  English and Hindi strings come from the arb files, read when the reminders are scheduled.
- Button: **"Log a glass"**. It adds one glass without opening the app, through a top-level
  `@pragma('vm:entry-point')` handler, the same shape as the widget's background glass. After
  that it re-plans, so a target met from the button also cancels the rest of the day.
- Tapping the notification itself opens Home on today.

### Screen

"Reminders" row in **You**, which docs/14 already lists; no new tab. The screen shows:

- the switch;
- from and until times;
- the interval;
- the "stop once the target is met" option;
- a preview line: "8 reminders a day, 08:00 – 22:00".

Its four states:

| State | When | What it shows |
|---|---|---|
| Loading | reading the settings | loading placeholder |
| Ready | settings read | the controls above |
| Failed | notifications refused in the system | explanation and an **Open settings** button |
| Empty | the phone can't schedule reminders | explanation |

The switch must never read "on" while nothing is scheduled; that mismatch is the docs/15 defect.
A shortcut on Home's water card ("Remind me") opens the same screen.

### Log out

Log out cancels every reminder and clears the box. Reminders for the previous account must not
fire for the next person who signs in.

### Tests

- Planner:
  - times fall only inside the window;
  - interval maths is correct, including a window that crosses midnight;
  - times already past today are skipped;
  - the 60 cap drops the furthest-away days first;
  - the rest of today is dropped once the target is met;
  - no reminders at all when off.
- Repository: a fake plugin records exactly what is scheduled and cancelled.
- Screen: all four states, at 200 % text; the switch can't show "on" while nothing is scheduled.
- Log out cancels everything.
- Tested by hand on a real device: a reminder fires with the app killed and after a restart, the
  button logs a glass without opening the app, and it works on Android 13+ and iOS.

### Size

About a day and a half:

- planner and tests: ½ day;
- plugin wrapper and native setup: ½ day;
- screen, l10n (en + hi) and log-out handling: ½ day.

A `D-nn` entry records the one-time-notifications choice and the week-long stop.

## 2. Other reminders the same machinery can carry

Each is a new entry for the same planner: different times, same scheduling code. All are off
by default and all are local.

| Reminder | When | Notes |
|---|---|---|
| **Meal logging** — built | 30 min after breakfast, lunch and dinner, at the profile's `breakfast_time` / `lunch_time` / `dinner_time` (all three exist, and are edited under Your day) | "Had lunch? Log it when you're ready." Dropped for a meal already logged today (re-planned on every log). |
| **End of day** — built | 1 h before `sleep_time` | "Anything else to add for today?" Once a day, and skipped when the app was open in the 2 hours before it — the diary does not say when an entry was logged, so "just used the app" stands in for "just logged". |
| **Weekly weigh-in** | One morning a week, the person picks the day | **Never daily.** Weight is where docs/05 is strictest: no streaks, no pressure. Needs a clinical/product yes before shipping (api/CLAUDE.md "ask before deciding"). |
| **Walk after meals** | 15 min after lunch or dinner | "A 10-minute walk?" Doesn't depend on the step count, which iOS can't read in the background. |
| **Wind-down** | 30 min before `sleep_time` | Pairs with the sleep hours already collected in onboarding. |
| **Coach check-in day** | The morning of the weekly check-in | Only with a coach assigned. The day comes from the server once, then the phone schedules it. |

### What should stay on the server

| Reminder | Why it can't be local |
|---|---|
| Trial ending, renewal, expiry (FR-6.5, T-7/T-3/T-0) | A cancellation or payment on the web must stop them; the phone would not know. |
| Coach messages | Another person caused them; only a push can say so. |
| Safety follow-ups (docs/05 §5) | Clinical, server-decided, and must reach the coach too. |

**Medicine or supplement reminders:** technically easy, but the wording is copy about a medical
condition, which needs sign-off first (api/CLAUDE.md). Not in this plan.

## Decisions — settled 2026-09-17

1. **Time zone:** `flutter_timezone`, the phone's own zone, which the phone sets from where it is.
   If the name is unknown, `Asia/Kolkata` is used.
2. **A week without opening the app:** the reminders stop.
3. **First release:** water, meal logging and end of day. The rest of section 2 is not built.

## As built — where it differs from the plan above

- **Settings live in the secure store** (`SecureStore`, key `reminders.state`), not a new Hive box.
  - Hive is not initialised anywhere in the app yet, and the health flags already live in the secure
    store (D-215).
  - Sign-out's `deleteAll` clears the settings with everything else.
  - The background isolates (the widget's glass, the reminder's button) can read the store.
- **No from/until pickers on the Reminders screen.**
  - The water window is the profile's wake and sleep times, and meal times come from the profile too.
  - One place holds the person's routine, and it is already editable under Your day.
- **No "Open settings" button.** Nothing in the app can open system settings without a new package.
  - Instead, the screen says where to turn notifications on.
  - It checks again when the app comes back to the foreground.
- **Hourly water uses up the 60-reminder cap sooner.** With meals and end of day on as well, the cap
  covers about 3 days instead of 7, and every open plans the week again.
- **Checked on an Android 16 emulator:**
  - The permission dialog appeared after the switch was turned on.
  - Water and meal reminders fired on time, each with its own icon.
  - "Log a glass" added 200 ml on the server while the launcher stayed in front.
  - All 19 pending reminders came back after a reboot.
- **iOS:** builds, but has not been run on a device.

