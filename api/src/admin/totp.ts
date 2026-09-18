import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * RFC 6238 time-based one-time passwords, for the handful of admin actions that are worth a second
 * factor (docs/09 §9's rule-pack activation, exports, and the full phone reveal).
 *
 * Written here rather than pulled in: it is HMAC-SHA1 plus a truncation, the RFC publishes test
 * vectors for exactly that, and `rfc6238Vectors` in the spec checks this code against them. A
 * dependency for thirty lines would be a dependency to keep patched forever.
 *
 * SHA-1, 6 digits, 30-second steps — not a preference, but what Google Authenticator, Authy and
 * 1Password all implement. A "better" choice here is one nobody can enrol.
 */

const STEP_SECONDS = 30;
const DIGITS = 6;

/// How far either side of now a code is still accepted. One step: a phone clock a few seconds out
/// still works, and a stolen code is good for at most a minute and a half.
const DRIFT_STEPS = 1;

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(bytes: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = '';

  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32[(value << (5 - bits)) & 31];

  return out;
}

export function base32Decode(text: string): Buffer {
  let bits = 0;
  let value = 0;
  const out: number[] = [];

  for (const char of text.toUpperCase().replace(/[=\s]/g, '')) {
    const index = BASE32.indexOf(char);
    if (index < 0) throw new Error('not base32');

    value = (value << 5) | index;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }

  return Buffer.from(out);
}

/// A new shared secret, base32 as every authenticator app expects it. 20 bytes is the RFC's own
/// size for SHA-1.
export function newSecret(): string {
  return base32Encode(randomBytes(20));
}

/**
 * The code for one moment.
 *
 * [digits] and [algorithm] are parameters only so the RFC's own test vectors (which use eight
 * digits, and SHA-256 and SHA-512 as well) can be run against this function. Everything in the app
 * uses the defaults.
 */
export function totpCode(
  secret: Buffer | string,
  at: Date,
  { digits = DIGITS, algorithm = 'sha1' } = {},
): string {
  const key = typeof secret === 'string' ? base32Decode(secret) : secret;
  const counter = Math.floor(at.getTime() / 1000 / STEP_SECONDS);

  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));

  const digest = createHmac(algorithm, key).update(message).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);

  return (binary % 10 ** digits).toString().padStart(digits, '0');
}

/// Whether [code] is this person's, now. Compares in constant time — a comparison that returns
/// early tells an attacker how much of a guess was right.
export function verifyTotp(secret: string, code: string, at: Date): boolean {
  const given = (code ?? '').trim();
  if (!/^\d{6}$/.test(given)) return false;

  for (let step = -DRIFT_STEPS; step <= DRIFT_STEPS; step++) {
    const when = new Date(at.getTime() + step * STEP_SECONDS * 1000);
    const expected = totpCode(secret, when);
    if (timingSafeEqual(Buffer.from(expected), Buffer.from(given))) return true;
  }

  return false;
}

/// What an authenticator app scans. The label is what the person sees in their app's list.
export function otpauthUri(secret: string, label: string): string {
  const issuer = 'Eatzify';
  return `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(label)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=${DIGITS}&period=${STEP_SECONDS}`;
}
