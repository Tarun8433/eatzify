import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

const ALLOWED = new Set(['reply', 'resolve', 'close']);

/// `reply`, `resolve` and `close` (docs/09 §9, D-228). The action is checked against a list rather
/// than forwarded — a path segment from the browser must never choose an API route by itself.
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string; action: string }> },
) {
  const { id, action } = await params;
  if (!ALLOWED.has(action)) {
    return NextResponse.json({ error: 'No such action.' }, { status: 400 });
  }

  const body = await request.json().catch(() => ({}));
  const r = await proxy(`/admin/tickets/${id}/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  return NextResponse.json(r.body, { status: r.status });
}
