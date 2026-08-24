---
description: Scaffold a new Flutter screen with Clean Architecture layers, GetX binding, all four view states and a widget test
disable-model-invocation: true
argument-hint: <screen name>
---

## Screen requested

$ARGUMENTS

## Steps

1. Find the screen in `docs/14-flutter-app-spec.md` §6 and `docs/02-prd.md`. Quote what it must do,
   which tab it lives under, and which API endpoints it needs from `docs/09-api-spec.md`. If it isn't
   in the specs, stop and ask — do not invent a screen.
2. Check `docs/15-ux-audit-screenshots.md` for defects listed against this screen in the old build.
   Fix them here rather than porting them forward.
3. List every file you will create, in layer order: entity → repository interface → use case → model →
   data source → repository impl → controller → binding → page → widgets → test.
4. Implement. All four `ViewState` cases rendered. Theme tokens and l10n keys only.
5. Register the route in `routes/app_pages.dart` with its binding and any guards
   (`AuthGuard`, `OnboardingGuard`, `EntitlementGuard`, `RoleGuard`).
6. Write the widget test covering Loading, Empty, Failed and Ready.

## Constraints

- No business logic in the widget. No hardcoded strings, colors or sizes.
- No new bottom-nav tab. If the screen seems to need one, stop and tell me — that needs an ADR.
- Enums mapped through l10n before display.

## Output

The files, then the l10n keys you added (en + hi), then anything the backend must provide that doesn't
exist yet.
