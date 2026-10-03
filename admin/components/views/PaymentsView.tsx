'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { inr, stamp } from '@/lib/format';
import {
  Button,
  ConfirmDialog,
  ErrorNote,
  KpiCard,
  Loadable,
  Pill,
  ViewHeader,
  inputClass,
} from '../ui';

type Status = 'created' | 'paid' | 'failed' | 'refunded';

type Payment = {
  order_id: string;
  user_id: number;
  user_name: string;
  email?: string | null;
  email_masked: string | null;
  amount_paise: string;
  discount_paise: string;
  coupon: string | null;
  plan: string;
  kind: string;
  status: Status;
  gateway: string;
  via_play_choice: boolean;
  failure_reason: string | null;
  created_at: string;
  paid_at: string | null;
  refunded_at: string | null;
};

type Detail = Payment & {
  phone_masked: string | null;
  refund_requests: { id: string; status: string; reason: string; created_at: string }[];
  subscription: { tier: string; status: string; ends_at: string | null } | null;
};

type Summary = {
  by_status: Record<Status, { count: number; amount_paise: string }>;
  today: { orders: number; collected_paise: string; failed: number };
  failure_reasons: { reason: string; count: number }[];
  refund_requests_open: number;
  store_subscriptions: { play: number; app_store: number };
};

export const STATUS_LABEL: Record<Status, string> = {
  created: 'Pending',
  paid: 'Successful',
  failed: 'Failed',
  refunded: 'Refunded',
};

const FILTERS: { key: '' | Status; label: string }[] = [
  { key: '', label: 'All' },
  { key: 'paid', label: 'Successful' },
  { key: 'created', label: 'Pending' },
  { key: 'failed', label: 'Failed' },
  { key: 'refunded', label: 'Refunded' },
];

/// Admin panel plan, Phase B: Cashfree payments, failures and refunds. Play and App Store money
/// is handled by the stores; their live plans are counted on the cards.
export function PaymentsView({
  permissions,
  initialStatus = '',
}: {
  permissions: string[];
  initialStatus?: '' | Status;
}) {
  const [status, setStatus] = useState<'' | Status>(initialStatus);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [rows, setRows] = useState<Payment[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);

  const load = useCallback(
    async (after: string | null) => {
      setLoading(true);
      setError(null);
      const params = new URLSearchParams({ limit: '50' });
      if (status) params.set('status', status);
      if (from) params.set('from', new Date(from).toISOString());
      if (to) params.set('to', new Date(`${to}T23:59:59`).toISOString());
      if (after) params.set('cursor', after);
      try {
        const page = await call<{ rows: Payment[]; next_cursor: string | null }>(
          `payments?${params}`,
        );
        setRows((prev) => (after ? [...prev, ...page.rows] : page.rows));
        setCursor(page.next_cursor);
      } catch (e) {
        setError(errorText(e, 'Could not load payments.'));
      } finally {
        setLoading(false);
      }
    },
    [status, from, to],
  );

  useEffect(() => {
    void load(null);
    call<Summary>('payments/summary').then(setSummary).catch(() => undefined);
  }, [load]);

  if (open) {
    return (
      <PaymentDetail
        orderId={open}
        permissions={permissions}
        onBack={() => {
          setOpen(null);
          void load(null);
        }}
      />
    );
  }

  const s = summary;
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <ViewHeader title="Payments" subtitle="Cashfree orders. Open one to see the details, remind the person or refund.">
        {FILTERS.map((f) => (
          <Pill key={f.key} active={status === f.key} onClick={() => setStatus(f.key)}>
            {f.label}
          </Pill>
        ))}
        <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} aria-label="From" className={inputClass} />
        <input type="date" value={to} onChange={(e) => setTo(e.target.value)} aria-label="To" className={inputClass} />
      </ViewHeader>

      {s && (
        <section className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-7">
          <KpiCard label="Collected today" value={inr(s.today.collected_paise)} hint={`${s.today.orders} paid`} />
          <KpiCard label="Successful" value={inr(s.by_status.paid.amount_paise)} hint={`${s.by_status.paid.count} orders`} />
          <KpiCard label="Pending" value={s.by_status.created.count} hint="Started, never finished" />
          <KpiCard label="Failed" value={s.by_status.failed.count} hint={`${s.today.failed} today`} highlight={s.today.failed > 0} />
          <KpiCard label="Refunded" value={inr(s.by_status.refunded.amount_paise)} hint={`${s.by_status.refunded.count} orders`} />
          <KpiCard label="Refund requests" value={s.refund_requests_open} highlight={s.refund_requests_open > 0} />
          <KpiCard label="Store plans" value={s.store_subscriptions.play + s.store_subscriptions.app_store} hint={`Play ${s.store_subscriptions.play} · Apple ${s.store_subscriptions.app_store}`} />
        </section>
      )}

      {status === 'failed' && s && s.failure_reasons.length > 0 && (
        <section className="card p-4">
          <h3 className="mb-2 text-[13px] font-medium text-ink">Why payments failed</h3>
          {s.failure_reasons.map((r) => (
            <div key={r.reason} className="flex justify-between border-t border-line py-1.5 text-[13px] first:border-t-0">
              <span className="text-ink">{r.reason}</span>
              <span className="text-ink-muted">{r.count}</span>
            </div>
          ))}
        </section>
      )}

      <ErrorNote message={error} />

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        <Loadable loading={loading} empty={rows.length === 0} emptyText="No payments match.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">Order</th>
                <th className="px-3 py-2 font-medium">User</th>
                <th className="px-3 py-2 text-right font-medium">Amount</th>
                <th className="px-3 py-2 font-medium">Plan</th>
                <th className="px-3 py-2 font-medium">Status</th>
                <th className="px-3 py-2 font-medium">When</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.order_id} onClick={() => setOpen(p.order_id)} className="cursor-pointer border-t border-line hover:bg-raised/50">
                  <td className="px-3 py-2 font-mono text-[12px] text-ink-muted">{p.order_id}</td>
                  <td className="px-3 py-2 text-ink">
                    {p.user_name || p.email || p.email_masked || '—'}
                    <span className="ml-1.5 text-[12px] text-ink-muted">#{p.user_id}</span>
                  </td>
                  <td className="px-3 py-2 text-right text-ink">{inr(p.amount_paise)}</td>
                  <td className="px-3 py-2 text-ink-muted">{p.plan}</td>
                  <td className="px-3 py-2 text-ink">
                    {STATUS_LABEL[p.status]}
                    {p.status === 'failed' && p.failure_reason && (
                      <span className="ml-1.5 text-[12px] text-ink-muted">({p.failure_reason})</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(p.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {cursor && (
            <div className="flex justify-center py-3">
              <Button onClick={() => void load(cursor)} disabled={loading}>Load more</Button>
            </div>
          )}
        </Loadable>
      </div>
    </div>
  );
}

function PaymentDetail({
  orderId,
  permissions,
  onBack,
}: {
  orderId: string;
  permissions: string[];
  onBack: () => void;
}) {
  const [p, setP] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [action, setAction] = useState<'refund' | 'remind' | null>(null);
  const canManage = permissions.includes('refunds.manage');

  const load = useCallback(async () => {
    try {
      setP(await call<Detail>(`payments/${encodeURIComponent(orderId)}`));
    } catch (e) {
      setError(errorText(e, 'Could not load this payment.'));
    }
  }, [orderId]);

  useEffect(() => {
    void load();
  }, [load]);

  const rows: [string, string][] = p
    ? [
        ['Order', p.order_id],
        ['User', `${p.user_name || '—'} #${p.user_id}`],
        ['Email', p.email ?? p.email_masked ?? '—'],
        ['Mobile', p.phone_masked ?? '—'],
        ['Amount', inr(p.amount_paise)],
        ['Discount', p.coupon ? `${inr(p.discount_paise)} (${p.coupon})` : '—'],
        ['Plan', `${p.plan} · ${p.kind}`],
        ['Gateway', p.via_play_choice ? 'Cashfree (chosen on Play)' : 'Cashfree'],
        ['Status', STATUS_LABEL[p.status]],
        ['Failure reason', p.failure_reason ?? '—'],
        ['Created', stamp(p.created_at)],
        ['Paid', stamp(p.paid_at)],
        ['Refunded', stamp(p.refunded_at)],
        ['Plan now', p.subscription ? `${p.subscription.tier} · ${p.subscription.status} · ends ${stamp(p.subscription.ends_at)}` : '—'],
      ]
    : [];

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto pb-4">
      <ViewHeader title="Payment" subtitle={orderId}>
        {p && canManage && p.status === 'paid' && (
          <Button tone="danger" onClick={() => setAction('refund')}>Refund</Button>
        )}
        {p && canManage && (p.status === 'failed' || p.status === 'created') && (
          <Button onClick={() => setAction('remind')}>Remind to retry</Button>
        )}
        <Button onClick={onBack}>Back to payments</Button>
      </ViewHeader>
      <ErrorNote message={error} />
      {notice && <p className="rounded-tile bg-raised px-4 py-3 text-[13px] text-ink">{notice}</p>}

      <Loadable loading={!p && !error} empty={!p} emptyText="No such payment.">
        <section className="card p-4">
          {rows.map(([k, v]) => (
            <div key={k} className="flex justify-between gap-4 border-t border-line py-1.5 text-[13px] first:border-t-0">
              <span className="text-ink-muted">{k}</span>
              <span className="text-right text-ink">{v}</span>
            </div>
          ))}
        </section>
        {p && p.refund_requests.length > 0 && (
          <section className="card p-4">
            <h3 className="mb-2 text-[13px] font-medium text-ink">Refund requests</h3>
            {p.refund_requests.map((r) => (
              <div key={r.id} className="border-t border-line py-1.5 text-[13px] first:border-t-0">
                <span className="text-ink">{r.status}</span>
                <span className="ml-2 text-ink-muted">{stamp(r.created_at)} — {r.reason}</span>
              </div>
            ))}
          </section>
        )}
      </Loadable>

      {action === 'refund' && p && (
        <ConfirmDialog
          title={`Refund ${inr(p.amount_paise)}`}
          body="The money goes back through Cashfree, the plan it paid for ends now, and the person is emailed."
          fields={[{ kind: 'text', name: 'reason', label: 'Reason (kept in the audit log)' }]}
          totp
          tone="danger"
          confirmLabel="Refund"
          onClose={() => setAction(null)}
          onConfirm={async (v, totp) => {
            await call(`payments/${encodeURIComponent(orderId)}/refund`, { method: 'POST', body: { reason: v.reason }, totp });
            setNotice('Refunded.');
            await load();
          }}
        />
      )}
      {action === 'remind' && (
        <ConfirmDialog
          title="Remind them to try again"
          body="Sends an in-app message and an email: nothing was charged, and they can retry from Plans."
          confirmLabel="Send reminder"
          onClose={() => setAction(null)}
          onConfirm={async () => {
            await call(`payments/${encodeURIComponent(orderId)}/remind`, { method: 'POST' });
            setNotice('Reminder sent.');
          }}
        />
      )}
    </div>
  );
}
