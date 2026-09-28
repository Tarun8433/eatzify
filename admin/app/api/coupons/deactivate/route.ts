import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// Deactivation, never deletion. TOTP-gated for the same reason creation is.
export async function POST(request: Request) {
  const { code: coupon } = await request.json().catch(() => ({ code: '' }));
  const code = request.headers.get('x-totp');

  const r = await proxy(`/admin/coupons/${encodeURIComponent(coupon)}/deactivate`, {
    method: 'POST',
    headers: { ...(code ? { 'X-Totp': code } : {}) },
  });
  return NextResponse.json(r.body, { status: r.status });
}
