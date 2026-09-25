import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// docs/09 §9: the review queue, one step at a time.
export async function GET(request: Request) {
  const status = new URL(request.url).searchParams.get('status') ?? 'draft';
  const r = await proxy(`/admin/foods?status=${status}`);
  return NextResponse.json(r.body, { status: r.status });
}

/// A food typed in by hand. It lands as a DRAFT whatever the form says (docs/08 §4).
export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}));
  const r = await proxy('/admin/foods', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return NextResponse.json(r.body, { status: r.status });
}
