import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// What is live, what is on disk, and every switch that has ever been made (D-229).
export async function GET() {
  const r = await proxy('/admin/rule-packs');
  return NextResponse.json(r.body, { status: r.status });
}
