import { currentToken } from './session';

const API = process.env.ADMIN_API_URL ?? 'http://localhost:3001/api/v1';

/**
 * Server-side access to the admin API, as the person using the dashboard (D-234).
 *
 * It used to sign in as one service account whose credentials sat in `.env.local`, which meant the
 * dashboard had no login: anybody who could open the page had every admin power, and every audit
 * row said the service account did it. Now the caller's own session is used, so `GET /admin/audit`
 * answers "who read this" with a person.
 *
 * Nothing here ever reaches the browser: the cookie is httpOnly and the access token lives only in
 * the server's memory.
 */
/// Thrown when there is no usable session. The routes turn it into a 401 and the page into a
/// redirect — never into a silent fall back to some other identity.
export class NotSignedIn extends Error {
  constructor() {
    super('Sign in to use the dashboard.');
    this.name = 'NotSignedIn';
  }
}

export async function adminFetch(
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  // Renewal is the middleware's job; by the time a handler runs, the token is either good or
  // there is no session at all.
  const token = await currentToken();
  if (!token) throw new NotSignedIn();

  return fetch(`${API}${path}`, {
    ...init,
    headers: { ...init.headers, Authorization: `Bearer ${token}` },
    cache: 'no-store',
  });
}

/// One shape for every proxy route, so a failure reads the same wherever it happened.
export async function proxy(path: string, init?: RequestInit) {
  try {
    const res = await adminFetch(path, init);
    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      const message =
        (data as { error?: { user_message?: string } })?.error?.user_message ??
        `The API refused the request (${res.status}).`;
      return { ok: false as const, status: res.status, body: { error: message } };
    }

    return { ok: true as const, status: 200, body: data };
  } catch (e) {
    // A signed-out caller is a 401, not a 502: the screen has to send them to the login page
    // rather than tell them the API is down.
    if (e instanceof NotSignedIn) {
      return { ok: false as const, status: 401, body: { error: e.message } };
    }

    return {
      ok: false as const,
      status: 502,
      body: {
        error:
          e instanceof Error ? e.message : 'Could not reach the API. Is it running on port 3001?',
      },
    };
  }
}
