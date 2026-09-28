import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// The review queue. The browser never holds a credential — every admin call goes through a route
/// handler, because a token in a bundle is a token anyone with devtools now has.
export async function GET(request: Request) {
  const status = new URL(request.url).searchParams.get('status') ?? 'submitted';
  const r = await proxy(`/admin/coaches/applications?status=${encodeURIComponent(status)}`);
  return NextResponse.json(r.body, { status: r.status });
}
