import { NextResponse } from 'next/server';
import { proxy } from '@/lib/api';

/// Starts enrolment. The secret comes back ONCE — a lost phone means a reset, not a second look.
export async function POST() {
  const r = await proxy('/admin/totp/enroll', { method: 'POST' });
  return NextResponse.json(r.body, { status: r.status });
}
