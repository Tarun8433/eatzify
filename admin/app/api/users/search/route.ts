import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * docs/09 §9: `POST /admin/users/search`. A POST because a filter may name a health condition, and
 * api rule 6 keeps health data out of query strings.
 *
 * The reason header is forwarded, not invented here: searching BY a condition is a health read
 * (docs/10 §4) and the API refuses it without one. A proxy that supplied a default reason would
 * make every audit row say the same thing, which is the same as saying nothing.
 */
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const reason = request.headers.get('x-reason');

  const r = await proxy('/admin/users/search', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(reason ? { 'X-Reason': reason } : {}),
    },
    body: JSON.stringify(body),
  });

  return NextResponse.json(r.body, { status: r.status });
}
