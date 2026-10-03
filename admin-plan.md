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
| Emails in lists | Full email for Super admin, Admin and Support; masked for Finance and Content; phones always masked behind Reveal (D-261) |

## Where it stands

| Phase | Built and tested | Live on the server |
|---|---|---|
| A: core | Yes | Yes: `eb65bca` (3 Oct), dashboard at `https://eatzify-admin.zynthovo.com` |
| B: payments | Yes | Yes: `ee9b7e7` (3 Oct) |
| C: communication | Yes | **No, not pushed yet** |
| D: reports | Yes | **No, not pushed yet** |

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
- [x] Migration ran on the server's Postgres (deploy of 3 Oct; `lastLoginAt` shows in the user list)

### Admin web app (verified 2026-10-03: `tsc` clean, `next build` OK, `npm test` 7/7)
- [x] **Fixed:** sign-in read the pre-D-250 login reply (`token`), so no one could sign in; it now reads `access`/`refresh` and takes the expiry from the token. Admits all five staff roles
- [x] Sidebar filtered by `GET /admin/me` (`lib/nav.ts`); opens on Dashboard. Kept the single-page shell rather than moving to URL routes (ponytail: works, and is a later refactor if deep links are wanted)
- [x] One guarded pass-through `app/api/admin/[...path]` (only `/admin/*`; forwards `x-totp` and `x-reason`) so new screens need no route file
- [x] Shared `components/ui` (`ViewHeader`, `KpiCard`, `Loadable`, `Pill`, `Button`, `LineChart` as SVG with no chart library, `ConfirmDialog` with reason and TOTP); `inr()` uses Indian digit grouping
- [x] Dashboard (cards, 30-day users and revenue charts, recent admin activity); Users list with filters and paging; user detail with reveal, block/unblock, edit name, password reset, resend code and delete; Verification; Admins & Roles; Audit action and date filters
- [x] Removed seven unused template widgets and the hardcoded 2024 date and 27°C
- [x] **Fixed:** sign-in errors say why ("cannot reach the API", status codes) instead of always "did not match"; only a 401 means a wrong password
- [x] Full email in Users, user detail and Verification for roles with `users.reveal` (D-261)
- [x] Vitest: `tests/nav.test.ts`, `tests/session.test.ts`
- [ ] ESLint is not configured for the admin app (`next lint` only offers to set it up), so lint is not run here
- [x] Hosting files: `admin/Dockerfile` (standalone), compose service `admin` behind profile `admin` (port 3004), nginx block for `eatzify-admin.zynthovo.com`
- [x] Live at `https://eatzify-admin.zynthovo.com`: DNS, nginx, certbot done; the old `eatzify-admin` container (node:22) was stopped and the new one took port 3004
- [x] Deploy builds the dashboard on every push touching `api/**` or `admin/**`; a dashboard build failure never fails the API deploy
- [x] Dashboard listens on `127.0.0.1:3004` only, reachable just through nginx over HTTPS
- [x] Deploy starts only `api` and `media` (plus `admin`); maildev and adminer no longer start on production

## Phase B: payments, failed transactions, refunds (verified 2026-10-03: API 861 + 7 new, app `flutter test` 934/934, admin `tsc` + `npm test` clean)
- [x] `refund_request` table (`1759400000000-RefundRequests`, one open request per order)
- [x] `RefundService.refundAsAdmin`: the self-serve path (Cashfree first, plan ends, commission reversed, credit note, email) without the 7-day window; self-serve keeps the window
- [x] App routes `GET /billing/payments` (each payment with `self_serve` / `request` / `requested`) and `POST /billing/refund-request`
- [x] Admin routes:
  - `GET /admin/payments` (status, user, date, cursor), `/payments/summary` (by status, today, failure reasons, open requests, store plans), `/payments/:orderId`
  - `POST /payments/:orderId/remind` (in-app + email, once a day)
  - `POST /payments/:orderId/refund` (finance + TOTP + reason)
  - `GET /admin/refunds?status=`, `POST /refunds/:id/approve` (TOTP), `/refunds/:id/reject` (note sent to the person)
- [x] Audit: `payment_remind`, `refund_admin`, `refund_approve`, `refund_reject`
- [x] Dashboard: Payments (7 cards, Successful/Pending/Failed/Refunded filters, failure reasons, detail with Refund and Remind) and Refund requests (Waiting/Approved/Rejected, Approve with TOTP, Reject with note)
- [x] App: "Payments and refunds" on Your plan, with Refund (inside 7 days) or Ask for a refund (after), en + hi, widget test for all four states and 200 % font
- [x] Tests: `test/admin-refunds.spec.ts`, `test/payments_page_test.dart`; `admin-guard.spec.ts` covers the new controller
- [ ] Play and App Store purchases are counted, not listed: the stores own their payments and refunds

## Phase C: notifications, announcements, offers (verified 2026-10-05: API 875/875, app 936/936, admin build + `npm test` clean)
- [x] Migration `1759500000000-CampaignsAnnouncementsOffers`: `notification_campaign`, `device_token`, `announcement`, offer columns on `coupon`
- [x] Campaigns: preview the audience count, send now or schedule (`CampaignScheduler`, every minute, claimed once), cancel, history with per-channel counts and read count. Audience: all, verified, unverified, plan, selected ids; health-condition targeting stays clinical-only; **commercial messages reach only people whose latest marketing consent is yes**
- [x] Push: `PushService` (FCM via firebase-admin), `POST /devices` and `/devices/unregister`, dead tokens removed. Off until `FIREBASE_SERVICE_ACCOUNT_FILE` is set
- [ ] SMS and WhatsApp: shown as "not set up" and refused; no provider code until there is an account to test against
- [x] Bell: `GET /admin/alerts` counts waiting coach applications, refund requests, tickets, day-old unconfirmed emails and a failed-payment spike, per role; live, no table
- [x] Announcements: draft, publish, unpublish, archive (publish audited); `GET /announcements` for the app by plan, most urgent first; Home banner (closable)
- [x] Offers: title, description, banner, start date, new-users-only, tier; edit (TOTP, audited, code and percentage locked); usage, revenue and discount per code; eligibility enforced at checkout
- [x] Dashboard screens: Messages (send and history), Announcements, Offers, bell with badge
- [x] Tests: `test/admin-comms.spec.ts` (11), `test/announcements_strip_test.dart`, guard test covers the new controller
- [ ] **Product owner:** Firebase project → `google-services.json` and `GoogleService-Info.plist` in the app, service-account JSON on the server. Then the app registers its push token (not built until the config exists)
- [ ] A critical announcement is a highlighted banner, not a pop-up shown once (that needs a stored "seen" list; add if wanted)

## Phase D: reports and analytics (verified 2026-10-05: API 881/881, admin build + `npm test` clean)
- [x] Migration `1759600000000-UserActivityDay`: one row per person per India day the app was used, written at sign-in and token refresh (no per-request write)
- [x] Reports `GET /admin/reports/:kind?from&to&format=json|csv` for users, payments, verification, notifications, offers. Aggregates only, every day in the range listed, India time; a CSV download is audited as `export`
- [x] Analytics `GET /admin/analytics`: active today, active in 30 days, came back after a week (signed up 7–37 days ago), payment success rate, refund rate, 30 days of daily active users
- [x] Dashboard: Reports (pick report and dates, preview, Download CSV) and Analytics (5 cards, 4 charts)
- [x] Tests: `test/admin-reports.spec.ts` (CSV quoting, one activity row per day, export audited); guard test covers the new controller
- [ ] Activity starts counting from this deploy: no history exists before it, so active-user figures and retention fill in over the following weeks
