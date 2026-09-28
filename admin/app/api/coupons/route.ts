import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

export async function GET() {
  const r = await proxy('/admin/coupons');
  return NextResponse.json(r.body, { status: r.status });
}

/// Creating an offer changes what people pay — TOTP-gated like the other dangerous actions
/// (D-229); the code is forwarded once and never stored.
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const code = request.headers.get('x-totp');

  const r = await proxy('/admin/coupons', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(code ? { 'X-Totp': code } : {}),
    },
    body: JSON.stringify(body),
  });
  return NextResponse.json(r.body, { status: r.status });
}
