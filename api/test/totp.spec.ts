import {
  base32Decode,
  base32Encode,
  newSecret,
  otpauthUri,
  totpCode,
  verifyTotp,
} from '../src/admin/totp';

/// RFC 6238's own test vectors. The reason this code can be written here rather than installed:
/// the specification publishes the answers.
///
/// The seed is the ASCII string "12345678901234567890", repeated to the algorithm's key length.
const SHA1_SEED = Buffer.from('12345678901234567890', 'ascii');
const SHA256_SEED = Buffer.from('12345678901234567890123456789012', 'ascii');
const SHA512_SEED = Buffer.from(
  '1234567890123456789012345678901234567890123456789012345678901234',
  'ascii',
);

describe('RFC 6238 test vectors', () => {
  const vectors: [number, string, string, Buffer][] = [
    [59, 'sha1', '94287082', SHA1_SEED],
    [59, 'sha256', '46119246', SHA256_SEED],
    [59, 'sha512', '90693936', SHA512_SEED],
    [1111111109, 'sha1', '07081804', SHA1_SEED],
    [1111111111, 'sha1', '14050471', SHA1_SEED],
    [1234567890, 'sha1', '89005924', SHA1_SEED],
    [2000000000, 'sha1', '69279037', SHA1_SEED],
    [20000000000, 'sha1', '65353130', SHA1_SEED],
    [1111111109, 'sha256', '68084774', SHA256_SEED],
    [1111111109, 'sha512', '25091201', SHA512_SEED],
  ];

  it.each(vectors)(
    'should match the published code at t=%i (%s)',
    (seconds, algorithm, expected, seed) => {
      expect(
        totpCode(seed, new Date(seconds * 1000), { digits: 8, algorithm }),
      ).toBe(expected);
    },
  );
});

describe('base32 (RFC 4648)', () => {
  it('should round-trip a secret', () => {
    const secret = newSecret();

    expect(secret).toMatch(/^[A-Z2-7]+$/);
    expect(base32Encode(base32Decode(secret))).toBe(secret);
  });

  it('should match the published encodings', () => {
    expect(base32Encode(Buffer.from('foobar', 'ascii'))).toBe('MZXW6YTBOI');
    expect(base32Decode('MZXW6YTBOI').toString('ascii')).toBe('foobar');
  });

  it('should refuse something that is not base32', () => {
    expect(() => base32Decode('1!8')).toThrow();
  });
});

describe('checking a code', () => {
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  const now = new Date('2026-09-18T10:00:00Z');

  it('should accept the code for right now', () => {
    expect(verifyTotp(secret, totpCode(secret, now), now)).toBe(true);
  });

  /// A phone clock a few seconds out still works.
  it('should accept one step either side', () => {
    const before = new Date(now.getTime() - 30_000);
    const after = new Date(now.getTime() + 30_000);

    expect(verifyTotp(secret, totpCode(secret, before), now)).toBe(true);
    expect(verifyTotp(secret, totpCode(secret, after), now)).toBe(true);
  });

  it('should refuse a code from two minutes ago', () => {
    const old = new Date(now.getTime() - 120_000);

    expect(verifyTotp(secret, totpCode(secret, old), now)).toBe(false);
  });

  it('should refuse anything that is not six digits', () => {
    for (const bad of ['', '12345', '1234567', 'abcdef', '12 34 56']) {
      expect(verifyTotp(secret, bad, now)).toBe(false);
    }
  });

  it('should refuse another secret’s code', () => {
    expect(verifyTotp(secret, totpCode(newSecret(), now), now)).toBe(false);
  });
});

describe('what the authenticator app scans', () => {
  it('should carry the secret and the parameters this code actually uses', () => {
    const uri = otpauthUri('GEZDGNBVGY3TQOJQ', 'admin 7');

    expect(uri).toContain('otpauth://totp/Eatzify:admin%207');
    expect(uri).toContain('secret=GEZDGNBVGY3TQOJQ');
    expect(uri).toContain('algorithm=SHA1');
    expect(uri).toContain('digits=6');
    expect(uri).toContain('period=30');
  });
});
