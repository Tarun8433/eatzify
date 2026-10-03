# Admin panel: everything from the brief, phased

The full plan, with what exists and what is missing, is at
`~/.claude/plans/opengym-main-i-want-to-kind-babbage.md`. A box is ticked only after its check has passed.

## Decisions (product owner, 3 Oct 2026)

| Topic | Decision |
|---|---|
| "Verify" | Email verification (D-250), coach applications and partner KYC. No ID documents from users |
| Roles | Five roles with one permission map: super_admin, admin, support, finance, content (D-260) |
| Channels | In-app, email, push (FCM), SMS, WhatsApp. SMS and WhatsApp stay off until credentials and templates exist |
| Delivery | Phased: A core, B payments, C communication, D reports |

## Phase A: foundation, dashboard, users, verification, roles, audit

### API (verified 2026-10-03: `npx jest --maxWorkers=2` 851/851, lint and `tsc` clean)
- [x] `src/admin/permissions.ts` permission map and `PermissionsGuard` with `@Permit`, applied to every admin route (a route with no `@Permit` is refused)
- [x] Roles finance=9 and content=10; status blocked=3. Migration `1759200000000-AdminUsersAndRoles` inserts role and status rows idempotently, creates `user_block`, and adds `user.lastLoginAt`
- [x] `UserAccessService`: sign-in (email, verify, Google) and token refresh refuse a blocked account; expired blocks lift on first contact; `lastLoginAt` is stamped
- [x] Routes:
  - `GET /admin/me`, `GET /admin/dashboard`, `GET /admin/metrics/series`
  - `GET /admin/users` (cursor), `/users/counts`, `/users/:id`
  - reveal (reason, `read_pii`), block, unblock, `PATCH` (names), `DELETE` (super admin + TOTP), password-reset, resend-verification
  - `GET /admin/verification/summary`, `/verification/email`
  - `GET /admin/staff`, `POST /admin/staff/:id/role` (super admin + TOTP)
- [x] Audit: new actions; before/after in `meta` (field names only for personal data); coupon and scan-policy changes are now audited; `GET /admin/audit?action=`
- [x] Boilerplate `POST/PATCH /users` can no longer set a role or status
- [x] Tests: `admin-users.spec.ts` (permission matrix, guard, block/unblock/expiry, masking, reveal audit), `admin-dashboard.spec.ts`; `admin-guard.spec.ts` and `roles.spec.ts` updated to the new rules
- [ ] Migration run against a real Postgres (happens on the next deploy)

### Admin web app (verified 2026-10-03: `tsc` clean, `next build` OK, `npm test` 7/7)
- [x] **Fixed:** sign-in read the pre-D-250 login reply (`token`), so no one could sign in; it now reads `access`/`refresh` and takes the expiry from the token. Admits all five staff roles
- [x] Sidebar filtered by `GET /admin/me` (`lib/nav.ts`); opens on Dashboard. Kept the single-page shell rather than moving to URL routes (ponytail: works, and is a later refactor if deep links are wanted)
- [x] One guarded pass-through `app/api/admin/[...path]` (only `/admin/*`; forwards `x-totp` and `x-reason`) so new screens need no route file
- [x] Shared `components/ui` (`ViewHeader`, `KpiCard`, `Loadable`, `Pill`, `Button`, `LineChart` as SVG with no chart library, `ConfirmDialog` with reason and TOTP); `inr()` uses Indian digit grouping
- [x] Dashboard (cards, 30-day users and revenue charts, recent admin activity); Users list with filters and paging; user detail with reveal, block/unblock, edit name, password reset, resend code and delete; Verification; Admins & Roles; Audit action and date filters
- [x] Removed seven unused template widgets and the hardcoded 2024 date and 27°C
- [x] Vitest: `tests/nav.test.ts`, `tests/session.test.ts`
- [ ] ESLint is not configured for the admin app (`next lint` only offers to set it up), so lint is not run here
- [x] Hosting files: `admin/Dockerfile` (standalone), compose service `admin` behind profile `admin` (port 3004), nginx block for `eatzify-admin.zynthovo.com`
- [ ] **Product owner:** DNS for `eatzify-admin.zynthovo.com`, copy the nginx file, certbot, then `docker compose --profile admin up -d --build admin`

## Phase B: payments, failed transactions, refunds
- [ ] Not started

## Phase C: notifications, announcements, offers
- [ ] Not started

## Phase D: reports and analytics
- [ ] Not started
