# 14 — Flutter App Specification

Stack: Flutter (stable) · GetX for state/routing/DI · Clean Architecture, feature-first · dartz `Either`
· dio · hive (offline) · flutter_screenutil · intl · cached_network_image.

## 1. The navigation problem — fix this first

Your 20 screenshots contain **four different bottom navigation bars**:

| Screen | Tabs |
|---|---|
| Home / dashboard | Home · Diary · **+** · Reports · More |
| Settings, Notifications | Home · Log · Trends · Profile |
| Log Meal | Home · Log · Trends · **Log Meal** |
| Tracker, Reminders, Progress | Tracker · Diet Plan · Progress |

Plus a hamburger "Menu" bottom sheet with nine tiles that duplicates most of the tabs, plus a
top-left hamburger on some screens and a back arrow + "Menu" pill on others.

A user cannot build a mental model of this app. Every navigation decision costs them attention that
should go to logging their food. This is the highest-leverage fix in the entire product and it is
mostly deletion.

**The one shell (client role):**

```
┌──────────────────────────────────────────────┐
│  Home        Plan     [ + ]    Progress  You │
└──────────────────────────────────────────────┘
```

| Tab | Contains |
|---|---|
| **Home** | Today: rings (kcal/protein/water/steps), next meal card, quick log, coach nudge |
| **Plan** | Today's plan by meal, tick-to-log, alternates, week view, export (PRO) |
| **+** (FAB) | Log sheet: food · water · weight · steps. One sheet, four tabs. Nothing else. |
| **Progress** | Weight trend (MA7), adherence, macro history, milestones |
| **You** | Profile, subscription, reminders, privacy & data, coach, settings, help |

**Deletions:** the hamburger menu (its nine tiles all live in a tab now) · the separate "Diary" and
"Log" tabs (one Plan tab plus the FAB) · the "Reports"/"Trends" split (one Progress tab) · the
"Tracker/Diet Plan/Progress" shell entirely · the per-screen back-arrow-plus-Menu-pill pattern.

**Coach role** gets its own shell in the same binary: `Clients · Check-ins · [+] · Messages · You`.

Rule for the future: **adding a tab requires an ADR.** That is how you stop shell #5.

## 2. Folder structure (large-app variant, since features share domain heavily)

```
lib/
├── core/
│   ├── theme/            app_theme.dart, app_colors.dart, app_text_styles.dart, app_spacing.dart
│   ├── network/           api_client.dart (dio + interceptors), api_endpoints.dart, error_mapper.dart
│   ├── storage/           secure_store.dart, hive_boxes.dart, offline_queue.dart
│   ├── errors/            failures.dart, exceptions.dart
│   ├── utils/             diary_date.dart, indian_currency.dart, measures.dart
│   ├── health/            health_data_source.dart (+ health_connect_/healthkit_/manual_ impls)
│   └── widgets/           app_button, app_card, state_views (loading/error/empty), rings
├── domain/
│   ├── entities/          user, profile, health_profile, diet_plan, meal, food, log, subscription…
│   ├── repositories/      abstract contracts
│   └── usecases/          generate_plan, log_food, fetch_active_plan, resolve_entitlements…
├── data/
│   ├── models/            *_model.dart with fromJson/toJson (json_serializable)
│   ├── datasources/       remote/*, local/*
│   └── repositories/      *_repository_impl.dart
├── presentation/
│   ├── shell/             client_shell.dart, coach_shell.dart, nav_controller.dart
│   ├── features/
│   │   ├── onboarding/    controllers, bindings, pages, widgets
│   │   ├── home/  plan/  logging/  progress/  account/
│   │   ├── coach_clients/ coach_checkins/ coach_chat/
│   │   └── billing/  privacy/
│   └── l10n/              app_en.arb, app_hi.arb
├── routes/                app_routes.dart, app_pages.dart, route_guards.dart
└── main.dart
```

Layer-first at the top (rather than feature-first) because plan, logging, progress and coach all share
the same entities and repositories — feature-first would duplicate the domain across five folders.

## 3. GetX conventions

- One controller per screen, `Get.lazyPut` in the feature binding. Never `Get.put` in a widget.
- Reactive state as explicit `.obs` fields; no god-object state classes.
- **A screen state is one of four things**, modelled explicitly, never inferred from nulls:
  ```dart
  sealed class ViewState<T> {}
  class Loading<T> extends ViewState<T> {}
  class Empty<T>   extends ViewState<T> {}
  class Failed<T>  extends ViewState<T> { final Failure f; }
  class Ready<T>   extends ViewState<T> { final T data; }
  ```
  Then `Obx(() => switch (c.state.value) { … })`. This is how you get the loading/error/empty coverage
  that NFR-8 requires without remembering to.
- Dispose every worker and stream in `onClose()`.
- Route guards: `AuthGuard`, `OnboardingGuard`, `EntitlementGuard`, `RoleGuard` — declared on
  `GetPage`, not checked inside pages.
- No business rule in a widget. If a widget computes a target, a BMI, or a price, it's in the wrong place.

## 4. Offline behaviour

| Data | Offline |
|---|---|
| Today's + tomorrow's plan | Cached in Hive, readable offline |
| Food search | Last 200 foods + all favourites cached |
| Food/water/weight logs | Written locally, queued, synced on reconnect |
| Steps | Read from the on-device health store; always available |
| Profile | Cached, read-only offline |
| Plan generation, billing, chat | Online only, with a clear offline state (not a spinner) |

Sync queue: FIFO, idempotency key per operation, exponential backoff, conflict resolution
last-write-wins **except** measurements (unique per diary day — server wins, client shows a merge notice).

## 5. Design system

Extract from the current build's better screens and formalise:
- **Colours:** primary deep green `#0B3B2E`, accent `#12A67F`, plus semantic tokens
  (`success/warning/danger/info`). Define light and dark; the settings screen already advertises a
  theme switch, so it must actually work.
- **Typography:** one family, six roles (display, h1, h2, body, label, caption). No ad-hoc sizes.
- **Spacing:** 4 pt scale (4/8/12/16/24/32). No magic numbers in widgets.
- **Radii:** 12 (cards), 24 (sheets), 999 (pills). Pick and stick.
- **Emoji:** the current build uses emoji as iconography (🌞 lunch, 🥜 snacks, 😎 avatar, 🎂 age).
  Emoji render differently per OS and per font, don't scale, and read as unfinished. Replace with a
  single icon set. Keep at most one emoji, in the greeting, as a deliberate voice choice.
- **Accessibility:** 48 dp touch targets, 4.5:1 contrast, tested at 200 % font scale, semantic labels
  on every icon-only button.

## 6. Screen inventory (client, v1)

Onboarding: splash · phone/OTP · profile basics · goal · activity · conditions + screening · food
preference/allergies · meal pattern · consent · plan ready.
Main: home · plan (day + week) · log sheet (food/water/weight/steps) · food search · food detail ·
custom food · progress · weight history · account · subscription · reminders · privacy & data ·
notifications list · help/tickets · coach (if assigned).
States for each: loading skeleton, error with retry, empty with a single clear action.

## 7. Specific fixes carried from the audit (doc 15)

- Raw enum leakage: profile shows `Goal: lose_weight`, `Activity Level: moderate`,
  `Diet Type: vegetarian` — map every enum through l10n before display.
- Water target hardcoded at 3 L; must come from the plan.
- Reminder times restricted to hourly presets with no custom picker; "Enable Reminders" is on while
  "No reminders set" — the toggle and the state disagree.
- Progress calendar marks past days red as "Missed"; change to neutral "not logged" (doc 05 §6).
- The `-30.0 kg` change readout and inconsistent weight entries (65.0, 58.0, 65.0 on consecutive days)
  — enforce one weight per diary day, plausibility confirm, and MA7 for display.
- "© 2024 Eatzify" in-app while dates read 2026 — a build-time constant.
