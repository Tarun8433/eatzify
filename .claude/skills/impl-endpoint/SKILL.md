---
description: Implement a REST endpoint from the Eatzify API spec, with DTOs, service, repository method, and a contract test
disable-model-invocation: true
argument-hint: <METHOD> <PATH>
---

## Target

Implement `$ARGUMENTS` exactly as specified in `docs/09-api-spec.md`.

## Steps

1. Locate the endpoint in `docs/09-api-spec.md` and quote the spec back to me — request shape,
   response shape, error codes, rate limit, entitlement. If it isn't in the spec, stop and say so.
2. List the files you will create or change before writing any of them.
3. Implement: DTO (with `forbidNonWhitelisted`), controller, service, repository method.
4. If the response contains a health field: add the audit interceptor and a `docs/10` matrix test.
5. If it creates money or a plan: implement `Idempotency-Key` handling with 24 h replay.
6. Write the contract test, including at least one failure path asserting the exact error `code`.

## Constraints

- Error envelope per `docs/09` §2. `user_message` comes from the server-side copy table, never invented.
- Scope by the authenticated caller. Never trust a `user_id` from the request body.
- No health data in the path or query string.
- No business logic in the controller.

## Output

Files, then one paragraph on what a client must change to consume it, then a `docs/09` diff if the
spec itself needs correcting.
