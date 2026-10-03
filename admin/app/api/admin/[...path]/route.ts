import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * One pass-through for the admin API's `/admin/*` routes (admin panel plan, Phase A), so a new
 * screen needs no route file of its own.
 *
 * Only `/admin/...` is reachable: the path is appended to a fixed prefix, so nothing here can be
 * pointed at `/auth` or `/billing`. The two headers the API's dangerous actions read — the
 * authenticator code and the reason for a personal-data read — are forwarded; nothing else is.
 */
type Context = { params: Promise<{ path: string[] }> };

const FORWARDED_HEADERS = ['x-totp', 'x-reason'];

async function forward(request: Request, { params }: Context) {
  const { path } = await params;
  if (path.some((p) => p === '..' || p === '.' || p.includes('/'))) {
    return NextResponse.json({ error: 'Not found.' }, { status: 404 });
  }

  const search = new URL(request.url).search;
  const headers: Record<string, string> = {};
  for (const name of FORWARDED_HEADERS) {
    const value = request.headers.get(name);
    if (value) headers[name] = value;
  }

  const hasBody = request.method !== 'GET' && request.method !== 'DELETE';
  const body = hasBody ? await request.text() : undefined;
  if (body) headers['Content-Type'] = 'application/json';

  const r = await proxy(`/admin/${path.map(encodeURIComponent).join('/')}${search}`, {
    method: request.method,
    headers,
    body: body || undefined,
  });

  // 204s come back as an empty object; that is fine for every caller.
  return NextResponse.json(r.body, { status: r.status });
}

export const GET = forward;
export const POST = forward;
export const PATCH = forward;
export const DELETE = forward;
