'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { inr, stamp } from '@/lib/format';
import { Button, ConfirmDialog, ErrorNote, Loadable, Pill, ViewHeader } from '../ui';

type Request = {
  id: string;
  order_id: string;
  user_id: number;
  amount_paise: string;
  plan: string;
  paid_at: string | null;
  reason: string;
  status: 'requested' | 'approved' | 'rejected';
  decided_by: number | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
};

const TABS = [
  { key: 'requested', label: 'Waiting' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Rejected' },
] as const;

/// Admin panel plan, Phase B: refunds asked for after the 7-day self-serve window. Approving runs
/// the real refund (Cashfree first); rejecting sends the person your note.
export function RefundsView({ permissions }: { permissions: string[] }) {
  const [tab, setTab] = useState<Request['status']>('requested');
  const [rows, setRows] = useState<Request[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [acting, setActing] = useState<{ kind: 'approve' | 'reject'; row: Request } | null>(null);
  const canManage = permissions.includes('refunds.manage');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setRows(await call<Request[]>(`refunds?status=${tab}`));
    } catch (e) {
      setError(errorText(e, 'Could not load refund requests.'));
    } finally {
      setLoading(false);
    }
  }, [tab]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <ViewHeader title="Refund requests" subtitle="Asked for after the 7-day self-serve window. Oldest first.">
        {TABS.map((t) => (
          <Pill key={t.key} active={tab === t.key} onClick={() => setTab(t.key)}>
            {t.label}
          </Pill>
        ))}
      </ViewHeader>
      <ErrorNote message={error} />

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        <Loadable loading={loading} empty={rows.length === 0} emptyText="Nothing here.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">Order</th>
                <th className="px-3 py-2 font-medium">User</th>
                <th className="px-3 py-2 text-right font-medium">Amount</th>
                <th className="px-3 py-2 font-medium">Paid</th>
                <th className="px-3 py-2 font-medium">Their reason</th>
                <th className="px-3 py-2 font-medium">{tab === 'requested' ? 'Asked' : 'Decided'}</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-line align-top">
                  <td className="px-3 py-2 font-mono text-[12px] text-ink-muted">{r.order_id}</td>
                  <td className="px-3 py-2 text-ink">#{r.user_id}</td>
                  <td className="px-3 py-2 text-right text-ink">{inr(r.amount_paise)}</td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(r.paid_at)}</td>
                  <td className="px-3 py-2 text-ink">
                    {r.reason}
                    {r.decision_note && <div className="mt-1 text-[12px] text-ink-muted">Reply: {r.decision_note}</div>}
                  </td>
                  <td className="px-3 py-2 text-ink-muted">
                    {stamp(tab === 'requested' ? r.created_at : r.decided_at)}
                    {r.decided_by && <div className="text-[12px]">by #{r.decided_by}</div>}
                  </td>
                  <td className="px-3 py-2 text-right">
                    {tab === 'requested' && canManage && (
                      <div className="flex justify-end gap-2">
                        <Button tone="primary" onClick={() => setActing({ kind: 'approve', row: r })}>Approve</Button>
                        <Button onClick={() => setActing({ kind: 'reject', row: r })}>Reject</Button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Loadable>
      </div>

      {acting?.kind === 'approve' && (
        <ConfirmDialog
          title={`Refund ${inr(acting.row.amount_paise)}`}
          body="Cashfree returns the money, the plan it paid for ends now, and the person is emailed."
          totp
          tone="danger"
          confirmLabel="Approve and refund"
          onClose={() => setActing(null)}
          onConfirm={async (_v, totp) => {
            await call(`refunds/${acting.row.id}/approve`, { method: 'POST', totp });
            await load();
          }}
        />
      )}
      {acting?.kind === 'reject' && (
        <ConfirmDialog
          title="Reject this request"
          body="Your note is sent to the person by in-app message and email."
          fields={[{ kind: 'text', name: 'note', label: 'Note to the person' }]}
          confirmLabel="Reject"
          onClose={() => setActing(null)}
          onConfirm={async (v) => {
            await call(`refunds/${acting.row.id}/reject`, { method: 'POST', body: { note: v.note } });
            await load();
          }}
        />
      )}
    </div>
  );
}
