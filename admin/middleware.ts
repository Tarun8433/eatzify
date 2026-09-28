import { NextResponse, type NextRequest } from 'next/server';
import {
  cookieOptions,
  FRESH_TOKEN_HEADER,
  needsRefresh,
  parseSession,
  refreshSession,
  SESSION_COOKIE,
} from '@/lib/session';

/**
 * No session, no dashboard (D-234) — and the one place the session can be renewed.
 *
 * The API rotates refresh tokens, so a renewal has to be written back to the cookie. Middleware is
 * the only layer that sees every request AND can set a cookie on the way out; doing it in each of
 * the sixteen route handlers would be sixteen chances to forget.
 *
 * The freshly minted token is also pushed onto the REQUEST headers, so the handler this request is
 * about to reach uses it rather than the expired one in the cookie it arrived with.
 */
export async function middleware(request: NextRequest) {
  const session = parseSession(request.cookies.get(SESSION_COOKIE)?.value);
  if (!session) return signedOut(request);

  if (!needsRefresh(session)) return NextResponse.next();

  const renewed = await refreshSession(session);
  if (!renewed) return signedOut(request);

  const headers = new Headers(request.headers);
  headers.set(FRESH_TOKEN_HEADER, renewed.token);

  const response = NextResponse.next({ request: { headers } });
  response.cookies.set(SESSION_COOKIE, JSON.stringify(renewed), cookieOptions());
  return response;
}

/// An API call gets a 401 it can act on; a page gets sent to the login screen.
function signedOut(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith('/api/')) {
    return NextResponse.json({ error: 'Sign in to use the dashboard.' }, { status: 401 });
  }

  const response = NextResponse.redirect(new URL('/login', request.url));
  response.cookies.delete(SESSION_COOKIE);
  return response;
}

/// Everything except the login page, the session route itself, and Next's own assets.
export const config = {
  matcher: ['/((?!login|api/session|_next/static|_next/image|favicon.ico).*)'],
};
