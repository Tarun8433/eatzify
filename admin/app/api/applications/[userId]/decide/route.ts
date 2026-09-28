import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/**
 * Verify or reject one application.
 *
 * One handler for both: they are the same decision with opposite answers and identical guards, and
 * splitting them duplicates the validation and lets the two drift. The API's own refusal messages
 * pass through unchanged — `user_message` is server-authored by design (rule 7), and friendlier copy
 * invented here would mean the admin sees one reason while the audit log records another.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  const { userId } = await params;
  const body = (await request.json()) as {
    decision?: 'verify' | 'reject';
    verified_attributes?: string[];
    reason?: string;
  };

  if (body.decision !== 'verify' && body.decision !== 'reject') {
    return NextResponse.json({ error: 'decision must be verify or reject.' }, { status: 400 });
  }

  // Checked here as well as server-side so the admin gets the message before a round trip, not
  // instead of one — the API enforces both regardless of what this sends.
  if (body.decision === 'verify' && !body.verified_attributes?.length) {
    return NextResponse.json({ error: 'Record what was checked before verifying.' }, { status: 422 });
  }
  if (body.decision === 'reject' && !body.reason?.trim()) {
    return NextResponse.json({ error: 'A rejection has to say why.' }, { status: 422 });
  }

  const payload =
    body.decision === 'verify'
      ? { verified_attributes: body.verified_attributes }
      : { reason: body.reason };

  const r = await proxy(`/admin/coaches/${userId}/${body.decision}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return NextResponse.json(r.body, { status: r.status });
}
