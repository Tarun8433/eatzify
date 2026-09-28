import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * docs/09 §9: `POST /admin/rule-packs/activate` — super_admin only, requires `reviewed_by`, and
 * behind a TOTP code (D-229).
 *
 * The code is forwarded from the browser and never stored: it is good for one action and one only.
 */
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const code = request.headers.get('x-totp');

  const r = await proxy('/admin/rule-packs/activate', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(code ? { 'X-Totp': code } : {}),
    },
    body: JSON.stringify(body),
  });

  return NextResponse.json(r.body, { status: r.status });
}
