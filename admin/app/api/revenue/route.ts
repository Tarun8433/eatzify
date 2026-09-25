import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// D-236: sums only — nothing here names a buyer.
export async function GET() {
  const r = await proxy('/admin/metrics/revenue');
  return NextResponse.json(r.body, { status: r.status });
}
