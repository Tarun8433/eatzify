---
paths:
  - "**/*_controller.dart"
  - "**/*_binding.dart"
---

# GetX controller rules

- Controllers hold reactive state (`.obs`), call use cases, and expose actions. **No Flutter imports**
  and no knowledge of widget structure.
- Screen state is a `ViewState<T>` sealed class — `Loading | Empty | Failed | Ready` — never a set of
  independent booleans and never inferred from a null.
- `Obx(() => ...)` in widgets by default; `GetBuilder` only when you need fine-grained rebuild control.
- Dispose every worker, stream subscription and timer in `onClose()`. A leaked worker in a controller
  that rebuilds is the most common memory bug in this stack.
- Never compute a target, BMI, price or entitlement in a controller. Those come from the API.
- Never compute a diary date. Ask the server.
- Guard against double-submit: disable the action while `isLoading` is true, and make write calls
  idempotent by sending the API's `Idempotency-Key` where the endpoint requires one.
