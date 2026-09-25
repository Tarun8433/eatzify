import { adminFetch } from '@/lib/api';

/**
 * Stream one of an applicant's documents to the browser.
 *
 * The bytes pass through this handler rather than the browser fetching them from the API directly,
 * for the same reason every other admin call does: the API credential stays on the server. The
 * browser gets an image with no token, no signed URL and nothing to forward — and the API writes an
 * audit row for every open.
 */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ userId: string; kind: string }> },
) {
  const { userId, kind } = await params;

  if (kind !== 'id' && kind !== 'qualification') {
    return Response.json({ error: 'No such document.' }, { status: 400 });
  }

  try {
    const res = await adminFetch(`/admin/coaches/${userId}/documents/${kind}`);

    if (!res.ok) {
      return Response.json(
        { error: res.status === 404 ? 'Not on file.' : `Refused (${res.status}).` },
        { status: res.status },
      );
    }

    return new Response(res.body, {
      headers: {
        'Content-Type': res.headers.get('content-type') ?? 'application/octet-stream',
        // A verification document must not sit in a disk cache after the tab closes.
        'Cache-Control': 'no-store, private',
        'Content-Disposition': res.headers.get('content-disposition') ?? 'inline',
      },
    });
  } catch {
    return Response.json({ error: 'Could not reach the API.' }, { status: 502 });
  }
}
