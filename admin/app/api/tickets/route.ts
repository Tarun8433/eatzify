import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// docs/09 §9: the support queue. No status means everything still waiting on us, oldest first.
export async function GET(request: Request) {
  const status = new URL(request.url).searchParams.get('status');
  const r = await proxy(`/admin/tickets${status ? `?status=${status}` : ''}`);
  return NextResponse.json(r.body, { status: r.status });
}
