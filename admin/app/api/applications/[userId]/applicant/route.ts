import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * Reveal one applicant's identity and what they declared. The API writes a `read_pii` audit row
 * before answering — that is the "audited action" docs/13 §4 trades the list-view masking for.
 *
 * Since D-229 it also needs a TOTP code: the full phone number is one of the three things worth a
 * second factor. The code is forwarded from the browser and never stored — it is good once.
 */
export async function GET(
  request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  const { userId } = await params;
  const code = request.headers.get('x-totp');

  const r = await proxy(`/admin/coaches/${userId}/applicant`, {
    headers: code ? { 'X-Totp': code } : {},
  });

  return NextResponse.json(r.body, { status: r.status });
}
