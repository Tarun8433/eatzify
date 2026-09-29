import {
  check,
  CODE_TTL_MS,
  codeMatches,
  hashCode,
  MAX_ATTEMPTS,
  newCode,
} from '../src/auth/email-otp/email-otp.rules';

/// D-250: the rules that decide how guessable a sign-up code is.
describe('email sign-up codes', () => {
  const now = new Date('2026-09-29T10:00:00Z');
  const stored = (
    code: string,
    over: Partial<{ attempts: number; expiresAt: Date }> = {},
  ) => ({
    codeHash: hashCode(code),
    expiresAt: new Date(now.getTime() + CODE_TTL_MS),
    attempts: 0,
    ...over,
  });

  it('are six digits, zero-padded', () => {
    for (let i = 0; i < 500; i++) expect(newCode()).toMatch(/^\d{6}$/);
  });

  it('are never stored as themselves', () => {
    expect(hashCode('123456')).not.toContain('123456');
    expect(hashCode('123456')).toHaveLength(64);
  });

  it('match only the exact code', () => {
    expect(codeMatches('123456', hashCode('123456'))).toBe(true);
    expect(codeMatches('123457', hashCode('123456'))).toBe(false);
    expect(codeMatches('', hashCode('123456'))).toBe(false);
  });

  it('accept the right code before it expires', () => {
    expect(check(stored('004217'), '004217', now)).toBe('ok');
  });

  it('refuse a wrong code', () => {
    expect(check(stored('004217'), '004218', now)).toBe('wrong');
  });

  it('refuse even the right code once expired', () => {
    expect(check(stored('004217', { expiresAt: now }), '004217', now)).toBe(
      'expired',
    );
  });

  it(`refuse even the right code after ${MAX_ATTEMPTS} wrong tries`, () => {
    expect(
      check(stored('004217', { attempts: MAX_ATTEMPTS }), '004217', now),
    ).toBe('locked');
  });

  it('say there is nothing to check when no code was sent', () => {
    expect(check(null, '004217', now)).toBe('none');
  });
});
