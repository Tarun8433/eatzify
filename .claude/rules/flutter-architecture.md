---
paths:
  - "lib/**/*.dart"
---

# Architecture rules

Governing spec: `docs/14-flutter-app-spec.md`.

## Layer discipline

- `domain/` is pure Dart. **No Flutter imports.** Entities are immutable with `final` fields and a
  `copyWith`. Repositories are abstract. Use cases do one thing and depend on abstractions.
- `data/` implements domain contracts. Models handle `fromJson`/`toJson`; entities stay clean.
  Data sources split `remote/` and `local/`.
- `presentation/` holds pages, widgets, controllers and bindings. Pages stay thin — compose widgets
  and read the controller.
- Dependency direction is one-way: presentation → domain ← data. A domain file importing from `data/`
  or `presentation/` is a bug.

## Error handling

- Every use case returns `Either<Failure, T>`. Map exceptions to `Failure` in the repository impl,
  never above it. No bare `try/catch` with a `print`.
- API errors carry a `code` and a `user_message`. Switch on `code`; render `user_message`.

## DI

- `Get.lazyPut` in the feature binding, wired on the `GetPage`. Never `Get.put` inside a widget and
  never construct a controller or use case in the widget tree.

## Naming

Descriptive over short: `PlanGenerationController`, not `PlanCtrl`. Files `snake_case.dart`.
