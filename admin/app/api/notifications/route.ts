import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * docs/09 §9: `POST /admin/notifications`.
 *
 * docs/13 §5's rule lives in the API: a segment naming a health condition is allowed only when
 * `content_class` is `clinical`. Nothing here second-guesses it — the refusal is what the sender
 * needs to read.
 */
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const r = await proxy('/admin/notifications', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return NextResponse.json(r.body, { status: r.status });
}
