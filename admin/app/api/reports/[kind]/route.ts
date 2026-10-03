import { NextResponse } from 'next/server';
import { adminFetch, NotSignedIn } from '@/lib/api';

/// A report as a CSV download (admin panel plan, Phase D). Its own route because the generic
/// pass-through reads JSON; this hands the API's file straight to the browser.
const KINDS = new Set(['users', 'payments', 'verification', 'notifications', 'offers']);

export async function GET(request: Request, { params }: { params: Promise<{ kind: string }> }) {
  const { kind } = await params;
  if (!KINDS.has(kind)) return NextResponse.json({ error: 'Unknown report.' }, { status: 404 });

  const q = new URL(request.url).searchParams;
  const passed = new URLSearchParams({ from: q.get('from') ?? '', to: q.get('to') ?? '', format: 'csv' });
  try {
    const res = await adminFetch(`/admin/reports/${kind}?${passed}`);
    if (!res.ok) {
      const body = (await res.json().catch(() => ({}))) as { error?: { user_message?: string } };
      return NextResponse.json(
        { error: body.error?.user_message ?? `The API refused the report (${res.status}).` },
        { status: res.status },
      );
    }
    return new NextResponse(await res.text(), {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': res.headers.get('content-disposition') ?? `attachment; filename="${kind}.csv"`,
      },
    });
  } catch (e) {
    const status = e instanceof NotSignedIn ? 401 : 502;
    return NextResponse.json({ error: e instanceof Error ? e.message : 'Could not reach the API.' }, { status });
  }
}
