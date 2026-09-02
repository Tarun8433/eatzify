import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';

const OTP_TTL_MS = 5 * 60 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;
const RATE_LIMIT_MAX = 3;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;

type Pending = { code: string; expiresAt: number; attempts: number };

/// docs/09 §3. Dev stub: no SMS provider is wired, so every number gets the same fixed code from
/// OTP_DEV_CODE. Swap `deliver()` for MSG91 (DLT templates, per docs/09 §3) without touching callers.
///
/// ponytail: in-memory maps — single instance only. Move to Redis when the API runs more than one
/// process, otherwise the rate limit and the codes are per-process and both become meaningless.
@Injectable()
export class OtpService {
  private readonly pending = new Map<string, Pending>();
  private readonly sends = new Map<string, number[]>();

  private get devCode(): string {
    return process.env.OTP_DEV_CODE ?? '000000';
  }

  /// Returns silently whether or not the number is known — docs/09 §3: never reveal existence.
  issue(phone: string, now: number): void {
    const recent = (this.sends.get(phone) ?? []).filter(
      (t) => now - t < RATE_LIMIT_WINDOW_MS,
    );

    if (recent.length >= RATE_LIMIT_MAX) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'OTP_RATE_LIMITED',
          user_message: 'Too many code requests. Please try again in an hour.',
        },
      });
    }

    this.sends.set(phone, [...recent, now]);
    this.pending.set(phone, {
      code: this.devCode,
      expiresAt: now + OTP_TTL_MS,
      attempts: 0,
    });
    // Deliberately no logging — docs/09 §3: never log an OTP.
  }

  /// Throws a 422 with a server-authored user_message on any failure; consumes the code on success.
  consume(phone: string, otp: string, now: number): void {
    const entry = this.pending.get(phone);

    if (!entry || entry.expiresAt < now) {
      this.pending.delete(phone);
      throw this.rejected('That code has expired. Request a new one.');
    }

    if (entry.attempts >= MAX_VERIFY_ATTEMPTS) {
      this.pending.delete(phone);
      throw this.rejected('Too many attempts. Request a new code.');
    }

    if (entry.code !== otp) {
      this.pending.set(phone, { ...entry, attempts: entry.attempts + 1 });
      throw this.rejected('That code is not correct.');
    }

    this.pending.delete(phone);
  }

  private rejected(userMessage: string): UnprocessableEntityException {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code: 'OTP_INVALID', user_message: userMessage },
    });
  }
}
