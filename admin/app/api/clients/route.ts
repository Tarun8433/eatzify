import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// The client roster. Names and goals only — no diary, so this is not a health read and needs no
/// reason. Fetching the diary does; see `[userId]/route.ts`.
export async function GET() {
  const r = await proxy('/admin/clients');
  return NextResponse.json(r.body, { status: r.status });
}
