import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// D-238 — who may scan a meal photo, per tier.
const TIERS = ['FREE', 'BASIC', 'PRO'];

export async function GET() {
  const r = await proxy('/admin/scan-policy');
  return NextResponse.json(r.body, { status: r.status });
}

/// Changing a tier's scans changes what they cost and what a plan includes — TOTP-gated like an
/// offer (D-229); the code is forwarded once and never stored.
export async function PATCH(request: Request) {
  const { tier, ...patch } = await request.json().catch(() => ({}));
  // Checked here because it becomes part of the API path.
  if (!TIERS.includes(tier)) {
    return NextResponse.json({ error: 'Unknown tier.' }, { status: 400 });
  }
  const code = request.headers.get('x-totp');

  const r = await proxy(`/admin/scan-policy/${tier}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      ...(code ? { 'X-Totp': code } : {}),
    },
    body: JSON.stringify(patch),
  });
  return NextResponse.json(r.body, { status: r.status });
}
