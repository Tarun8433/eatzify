import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * One client's diary, plan and weights.
 *
 * **This is a health read.** docs/10 §4 requires a reason from a closed list, and the API rejects
 * the call without one. The reason is forwarded from the caller rather than hardcoded: a proxy that
 * always sent `support_ticket` would make every audit row say the same thing and turn the
 * requirement into decoration.
 */
export async function GET(
  request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  const { userId } = await params;
  const reason = new URL(request.url).searchParams.get('reason');

  if (!reason) {
    return NextResponse.json(
      { error: 'A reason is required to open a client record.' },
      { status: 400 },
    );
  }

  const r = await proxy(`/admin/clients/${userId}`, { headers: { 'X-Reason': reason } });
  return NextResponse.json(r.body, { status: r.status });
}
