# Email sign-in — replaces phone OTP (D-250)

A box is ticked only after its check has passed. Do this before payments Phase 3.

## What the product owner asked (29 Sept 2026)

- Sign in with **email + password**.
- **First time**: a 6-digit **code emailed** to verify the address.
- **Forgot password**: a **reset link** by email.
- **Remove phone login.** The phone number is still **collected**, at sign-up, as contact info
  (Cashfree needs one per order) — never used to sign in.
- Google sign-in stays as it is.

## Found in the existing code (fix as part of this)

- `validateLogin` says `notFound` vs `incorrectPassword` → tells anyone which emails have accounts.
  Must be one generic "email or password is incorrect".
- `validateLogin` lets **unverified** (inactive) accounts sign in. Must refuse with
  `EMAIL_NOT_VERIFIED`, send a fresh code, and the app routes to the code screen.
- `forgotPassword` returns `emailNotExists` → same leak. Must always answer 204.
- Email login returns `{token, refreshToken, tokenExpires, user}`; the app's session is
  `{access, refresh, user, onboarding_required}` (the old phone login's shape). One shared
  `issueSession(user)` helper for every way in.
- Reset link goes to `FRONTEND_DOMAIN/password-change` — no such page. Point it at
  `https://eatzify.zynthovo.com/reset-password/` and add that page to `site/` (form → `POST
  /api/v1/auth/reset/password`); the API's CORS must allow the site origin.

## Tracker

> **Verified 2026-09-29:** API `npx jest` 721/721, lint + `tsc` clean. App `flutter test` 904/904, `flutter analyze` no new issues.

### Server
- [x] Migration `1758900000000-EmailSignIn`: `email_otp` table (SHA-256 of the code only), drop `UQ_user_phone`
- [x] `user.phone` no longer unique in the entity
- [x] `EmailOtpEntity` (`src/auth/email-otp/email-otp.entity.ts`) and the pure rules
      (`email-otp.rules.ts`: `newCode`, `hashCode`, timing-safe `codeMatches`, `check` →
      ok/wrong/expired/locked/none) — `test/email-otp-rules.spec.ts` 8/8
- [x] `EmailOtpService`: `issue(user)` — count rows in the last hour (max 5, else
      429 `CODE_RATE_LIMITED`), save `hashCode(newCode())` with 10-min expiry, email it; `verify(userId,
      code)` — latest row by `createdAt`, `check()`, on `wrong` increment `attempts`, on `ok` delete
      the user's rows. Register the entity (`TypeOrmModule.forFeature`) and service in `AuthModule`
- [x] Code email — sent through the existing `MailService.notification` (plain template), no new `.hbs`
- [x] `AuthService`: `issueSession(user)`; `register(email, password, phone)` → inactive + code;
      `verifyEmail(email, code)` → active + session; `resendCode(email)` (always 204);
      `validateLogin` generic errors + unverified handling + session shape; `forgotPassword` always 204
- [x] Routes: `email/register` {email, password, phone_e164}, `email/verify`, `email/resend`,
      `email/login`, `forgot/password`, `reset/password`. **Remove** `otp/request`, `otp/verify`,
      `OtpService`, `validatePhoneLogin`, their specs
- [x] Emails lowercased and trimmed everywhere; password min 8 (sign-up and reset)
- [x] Tests (`test/email-otp-service.spec.ts`, `test/auth-email-flow.spec.ts`): register → code → verify → session; wrong code ×5 locks; expired code; resend limit;
      login unverified; login generic error for both unknown email and wrong password; forgot
      always 204; reset with the emailed hash

### Website
- [x] `site/reset-password/index.html`: new-password form → API. CORS is env-driven: set
      `APP_CORS_ORIGINS` (and `FRONTEND_DOMAIN`) to `https://eatzify.zynthovo.com` on the server

### App
- [x] Sign-in screen: email, password, "Forgot password?", "Create account", Google button, agreement line
- [x] Sign-up screen: email, password, **phone number** (collected, not verified)
- [x] Verify-email screen: 6-digit code, resend with a cooldown
- [x] Forgot-password screen: email → "check your inbox" (same message whether or not it exists)
- [x] Remove the phone and OTP steps; l10n en + hi; tests for each screen

### Needs the product owner
- [ ] **Gmail SMTP with an app password** (chosen 29 Sept for testing, ≈500/day). On the server:
      `MAIL_HOST=smtp.gmail.com` `MAIL_PORT=587` `MAIL_USER=<gmail>` `MAIL_PASSWORD=<16-char app
      password>` `MAIL_SECURE=false` `MAIL_REQUIRE_TLS=true` `MAIL_IGNORE_TLS=false`
      `MAIL_DEFAULT_EMAIL=<same gmail>` (Gmail rewrites any other From). No SPF/DKIM needed on a
      gmail.com sender. Move to Brevo/SES before real volume
- [ ] Existing phone-only accounts can't sign in after this. (No public users yet — they re-register.)
