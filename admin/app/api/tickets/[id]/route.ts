import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// One conversation in full. The API writes a `read_pii` audit row before answering — somebody's
/// own words about their own problem are routinely their phone number and their order id.
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  const r = await proxy(`/admin/tickets/${id}`);
  return NextResponse.json(r.body, { status: r.status });
}
