import { describe, expect, it, vi } from 'vitest';

// session.ts reads cookies/headers from next/headers; only the pure helper is under test.
vi.mock('next/headers', () => ({ cookies: vi.fn(), headers: vi.fn() }));
const { tokenExpiry, ADMIN_ROLE_IDS } = await import('../lib/session');

function jwt(payload: object): string {
  const b64 = (o: object) => btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64({ alg: 'HS256' })}.${b64(payload)}.signature`;
}

describe('tokenExpiry', () => {
  it("reads the access token's own exp claim, in milliseconds", () => {
    expect(tokenExpiry(jwt({ id: 1, exp: 1_790_000_000 }))).toBe(1_790_000_000_000);
  });

  it('answers null rather than guessing for a token it cannot read', () => {
    expect(tokenExpiry('not-a-jwt')).toBeNull();
    expect(tokenExpiry(jwt({ id: 1 }))).toBeNull();
  });
});

describe('ADMIN_ROLE_IDS', () => {
  it('admits the five staff roles and nobody else (D-260)', () => {
    expect([...ADMIN_ROLE_IDS].sort((a, b) => a - b)).toEqual([1, 7, 8, 9, 10]);
  });
});
