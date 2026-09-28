import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// Whether this account has an authenticator set up (D-229).
export async function GET() {
  const r = await proxy('/admin/totp');
  return NextResponse.json(r.body, { status: r.status });
}
