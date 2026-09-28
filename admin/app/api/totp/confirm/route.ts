import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// Proves the app is really set up before anything starts depending on it.
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const r = await proxy('/admin/totp/confirm', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return NextResponse.json(r.body, { status: r.status });
}
