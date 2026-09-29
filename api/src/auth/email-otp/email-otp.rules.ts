import { createHash, randomInt, timingSafeEqual } from 'crypto';

/// Sign-up code rules (D-250). Security limits, not clinical constants — named here so the numbers
/// that decide how guessable a code is sit in one reviewed place.
export const CODE_DIGITS = 6;
export const CODE_TTL_MS = 10 * 60 * 1000;
/// Wrong guesses before the code dies. 5 tries at 1-in-a-million is a 0.0005 % chance per code.
export const MAX_ATTEMPTS = 5;
export const MAX_SENDS_PER_HOUR = 5;
export const HOUR_MS = 60 * 60 * 1000;

/// A cryptographically random, zero-padded code: `004217` is as likely as `731980`.
export function newCode(): string {
  return randomInt(0, 10 ** CODE_DIGITS)
    .toString()
    .padStart(CODE_DIGITS, '0');
}

export function hashCode(code: string): string {
  return createHash('sha256').update(code).digest('hex');
}

/// Constant-time, so a wrong guess takes as long as a nearly-right one.
export function codeMatches(code: string, storedHash: string): boolean {
  const given = Buffer.from(hashCode(code), 'hex');
  const stored = Buffer.from(storedHash, 'hex');
  return given.length === stored.length && timingSafeEqual(given, stored);
}

export type CheckResult = 'ok' | 'wrong' | 'expired' | 'locked' | 'none';

/// What a guess against the latest code means, without touching storage.
export function check(
  latest: { codeHash: string; expiresAt: Date; attempts: number } | null,
  code: string,
  now: Date,
): CheckResult {
  if (!latest) return 'none';
  if (latest.attempts >= MAX_ATTEMPTS) return 'locked';
  if (latest.expiresAt.getTime() <= now.getTime()) return 'expired';
  return codeMatches(code, latest.codeHash) ? 'ok' : 'wrong';
}
