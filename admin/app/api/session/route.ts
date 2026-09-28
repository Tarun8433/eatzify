import { NextResponse } from 'next/server';
import { cookieOptions, readSession, signIn, signOut, SESSION_COOKIE } from '@/lib/session';

/// Signing in. The password goes from the form to the API and is never stored anywhere in between.
export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as {
    email?: string;
    password?: string;
  };

  if (!body.email || !body.password) {
    return NextResponse.json({ error: 'Email and password, please.' }, { status: 400 });
  }

  const result = await signIn(body.email, body.password);
  if ('error' in result) {
    return NextResponse.json({ error: result.error }, { status: 401 });
  }

  const response = NextResponse.json({ viewer: result.session.viewer });
  response.cookies.set(SESSION_COOKIE, JSON.stringify(result.session), cookieOptions());
  return response;
}

/// Signing out — on the API as well as here, because a token that still works is not logged out.
export async function DELETE() {
  const session = await readSession();
  if (session) await signOut(session);

  const response = new NextResponse(null, { status: 204 });
  response.cookies.delete(SESSION_COOKIE);
  return response;
}
