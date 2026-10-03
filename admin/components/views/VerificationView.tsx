'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { stamp } from '@/lib/format';
import { Button, ErrorNote, KpiCard, Loadable, ViewHeader } from '../ui';
import type { UserRow } from './UsersView';

type Summary = {
  email: { pending: number; verified: number };
  coach: Record<string, number>;
  partner_kyc: Record<string, number>;
};

/// "Verify" in Eatzify (admin panel plan, decision 1): confirmed emails, coach applications and
/// partner bank details. Coach applications are reviewed on their own screen.
export function VerificationView({
  permissions,
  onOpenPartners,
}: {
  permissions: string[];
  onOpenPartners: () => void;
}) {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [pending, setPending] = useState<UserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [s, p] = await Promise.all([
        call<Summary>('verification/summary'),
        call<UserRow[]>('verification/email'),
      ]);
      setSummary(s);
      setPending(p);
    } catch (e) {
      setError(errorText(e, 'Could not load verification.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function resend(id: number) {
    setNotice(null);
    try {
      await call(`users/${id}/resend-verification`, { method: 'POST' });
      setNotice(`A new code was sent to user #${id}.`);
    } catch (e) {
      setError(errorText(e, 'Could not send the code.'));
    }
  }

  const coach = summary?.coach ?? {};
  const kyc = summary?.partner_kyc ?? {};

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto pb-4">
      <ViewHeader title="Verification" subtitle="Emails waiting on their code, coach applications and partner bank details.">
        {permissions.includes('verification.manage') && (
          <Button onClick={onOpenPartners}>Review coach applications</Button>
        )}
      </ViewHeader>
      <ErrorNote message={error} />
      {notice && <p className="rounded-tile bg-raised px-4 py-3 text-[13px] text-ink">{notice}</p>}

      <section className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <KpiCard label="Email pending" value={summary?.email.pending ?? 0} highlight={(summary?.email.pending ?? 0) > 0} />
        <KpiCard label="Email confirmed" value={summary?.email.verified ?? 0} />
        <KpiCard label="Coach: submitted" value={coach.submitted ?? 0} highlight={(coach.submitted ?? 0) > 0} />
        <KpiCard label="Coach: verified" value={coach.verified ?? 0} />
        <KpiCard label="Coach: rejected" value={coach.rejected ?? 0} />
        <KpiCard label="Partner KYC pending" value={kyc.pending ?? 0} highlight={(kyc.pending ?? 0) > 0} />
      </section>

      <section className="card p-2">
        <h3 className="px-3 pt-2 text-[13px] font-medium text-ink">Waiting on their email code (oldest first)</h3>
        <Loadable loading={loading} empty={pending.length === 0} emptyText="Nobody is waiting.">
          <table className="mt-1 w-full border-collapse text-[13px]">
            <tbody>
              {pending.map((u) => (
                <tr key={u.user_id} className="border-t border-line">
                  <td className="px-3 py-2 text-ink">
                    {u.name || '—'} <span className="text-[12px] text-ink-muted">#{u.user_id}</span>
                  </td>
                  <td className="px-3 py-2 text-ink-muted">{u.email_masked ?? '—'}</td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(u.registered_at)}</td>
                  <td className="px-3 py-2 text-right">
                    {permissions.includes('users.manage') && (
                      <Button onClick={() => void resend(u.user_id)}>Resend code</Button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Loadable>
      </section>
    </div>
  );
}
