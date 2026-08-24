---
paths:
  - "api/src/**/*.controller.ts"
  - "api/src/**/*.dto.ts"
  - "api/src/**/*.service.ts"
---

# API conventions

Governing spec: `docs/09-api-spec.md`.

- Request/response bodies are `snake_case`. Internal TS is `camelCase`. Map at the DTO boundary.
- One error envelope, everywhere: `{ error: { code, message, user_message, details, request_id } }`.
  `message` is for logs; `user_message` is the only string the app renders and it comes from the
  server-side copy table (`docs/05` §7). Never invent user-facing text in a controller.
- `Idempotency-Key` required on any POST that creates money or a plan. Store 24 h, replay the response.
- Cursor pagination only. No offset pagination on user-growable lists.
- Scope every query by the authenticated caller. Never accept a `user_id` from the body to decide scope.
- No health data in paths or query strings — POST a body even for filtered reads.
- Validate with DTOs and `forbidNonWhitelisted: true`. Reject unknown properties.
- Controllers contain no business logic and no query building. Service → repository.
- Health-field responses: add the audit interceptor and a `docs/10` matrix test in the same change.
