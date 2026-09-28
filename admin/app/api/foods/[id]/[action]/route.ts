import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

const ALLOWED = new Set(['review', 'publish', 'retire']);

/// docs/08 §4's steps. Publishing is allowed only from `reviewed`; the API decides that, not this.
export async function POST(
  _request: Request,
  { params }: { params: Promise<{ id: string; action: string }> },
) {
  const { id, action } = await params;
  if (!ALLOWED.has(action)) {
    return NextResponse.json({ error: 'No such action.' }, { status: 400 });
  }

  const r = await proxy(`/admin/foods/${id}/${action}`, { method: 'POST' });
  return NextResponse.json(r.body, { status: r.status });
}
