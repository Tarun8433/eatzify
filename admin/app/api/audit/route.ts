import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// docs/09 §9: `GET /admin/audit?actor=&subject=&from=&to=`. Ids and reasons — never what was read.
export async function GET(request: Request) {
  const from = new URL(request.url).searchParams;
  const passed = new URLSearchParams();
  for (const key of ['actor', 'subject', 'from', 'to', 'limit']) {
    const value = from.get(key);
    if (value) passed.set(key, value);
  }

  const query = passed.toString();
  const r = await proxy(`/admin/audit${query ? `?${query}` : ''}`);
  return NextResponse.json(r.body, { status: r.status });
}
