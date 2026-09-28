import { cookies, headers } from 'next/headers';

/**
 * Who is using the dashboard, and how it proves that to the API.
 *
 * **This replaces signing in as one service account (D-234).** The old arrangement kept an
 * `ADMIN_API_EMAIL` / `ADMIN_API_PASSWORD` pair in `.env.local` and used it for every request from
 * anybody who could open the page — so the dashboard had no login at all, and every audit row said
 * "the service account read this" whoever actually did.
 *
 * The whole session lives in one httpOnly cookie: no script on the page can read it, and there is
 * no server-side store to keep in step across restarts.
 *
 * **The API rotates refresh tokens** — using one invalidates it and returns the next — so the
 * refreshed pair has to be written back to the cookie. That happens in `middleware.ts`, which is
 * the one place that can set a cookie on every kind of request.
 */

export const SESSION_COOKIE = 'eatzify_admin';

/// Set by the middleware when it has just refreshed, so this request uses the new token rather than
/// the expired one still sitting in the cookie it was sent with.
export const FRESH_TOKEN_HEADER = 'x-admin-fresh-token';

/// docs/10 §1: only these two reach the admin surface. Checked at sign-in as well as by the API, so
/// a coach who signs in here is told plainly rather than shown a dashboard of 403s.
export const ADMIN_ROLE_IDS = [1, 8];

const API = process.env.ADMIN_API_URL ?? 'http://localhost:3001/api/v1';

/// Thirty days, matching the API's own refresh-token lifetime.
const COOKIE_MAX_AGE = 30 * 24 * 60 * 60;

/// Refresh this far before the access token actually expires: one that dies mid-flight is a 401
/// the person reads as a bug.
export const REFRESH_SLACK_MS = 60_000;

export type Viewer = { userId: number; name: string; roleId: number };

export type Session = {
  token: string;
  tokenExpires: number;
  refreshToken: string;
  viewer: Viewer;
};

export function parseSession(raw: string | undefined): Session | null {
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as Session;
    return parsed.token && parsed.refreshToken ? parsed : null;
  } catch {
    // A cookie we cannot read is a cookie that is not a session.
    return null;
  }
}

export async function readSession(): Promise<Session | null> {
  return parseSession((await cookies()).get(SESSION_COOKIE)?.value);
}

export function cookieOptions() {
  return {
    httpOnly: true,
    sameSite: 'lax' as const,
    // Off in development, because localhost is not https and a secure cookie would never be set.
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    maxAge: COOKIE_MAX_AGE,
  };
}

/// Signs in against the API, or says why it refused.
export async function signIn(
  email: string,
  password: string,
): Promise<{ session: Session } | { error: string }> {
  const res = await fetch(`${API}/auth/email/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
    cache: 'no-store',
  });

  if (!res.ok) {
    // Deliberately the same sentence for a wrong password and an unknown address: telling somebody
    // which half they got right is how an address list gets enumerated.
    return { error: 'That email and password did not match an account.' };
  }

  const data = (await res.json()) as {
    token?: string;
    refreshToken?: string;
    tokenExpires?: number;
    user?: { id: number; firstName: string | null; role?: { id: number } };
  };

  if (!data.token || !data.refreshToken || !data.user) {
    return { error: 'The API signed in but returned no session.' };
  }

  const roleId = Number(data.user.role?.id ?? 0);
  if (!ADMIN_ROLE_IDS.includes(roleId)) {
    return { error: 'That account is not an admin on this system.' };
  }

  return {
    session: {
      token: data.token,
      tokenExpires: data.tokenExpires ?? Date.now() + 60_000,
      refreshToken: data.refreshToken,
      viewer: {
        userId: data.user.id,
        name: data.user.firstName ?? 'Admin',
        roleId,
      },
    },
  };
}

export function needsRefresh(session: Session, now = Date.now()): boolean {
  return session.tokenExpires - now < REFRESH_SLACK_MS;
}

/**
 * Trades the refresh token for a new pair.
 *
 * Single use: the API invalidates the token it was called with, which is why the result has to be
 * written back to the cookie and why two requests refreshing at the same moment would leave one of
 * them signed out. On a dashboard used by a handful of people, a fifteen-minute token makes that
 * rare enough to accept rather than build a lock for.
 */
export async function refreshSession(session: Session): Promise<Session | null> {
  const res = await fetch(`${API}/auth/refresh`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${session.refreshToken}` },
    cache: 'no-store',
  });

  if (!res.ok) return null;

  const data = (await res.json()) as {
    token?: string;
    refreshToken?: string;
    tokenExpires?: number;
  };

  if (!data.token || !data.refreshToken) return null;

  return {
    ...session,
    token: data.token,
    refreshToken: data.refreshToken,
    tokenExpires: data.tokenExpires ?? Date.now() + 60_000,
  };
}

/// The token this request should use: the one the middleware just minted, or the cookie's.
export async function currentToken(): Promise<string | null> {
  const fresh = (await headers()).get(FRESH_TOKEN_HEADER);
  if (fresh) return fresh;

  return (await readSession())?.token ?? null;
}

/// Ends the session on the API as well as here — a token that still works after "log out" is not
/// logged out.
export async function signOut(session: Session): Promise<void> {
  try {
    await fetch(`${API}/auth/logout`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${session.token}` },
      cache: 'no-store',
    });
  } catch {
    // The cookie is cleared regardless. A network failure must not leave somebody signed in.
  }
}
