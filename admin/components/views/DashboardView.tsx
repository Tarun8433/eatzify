'use client';

import { useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { inr, stamp } from '@/lib/format';
import { ErrorNote, KpiCard, LineChart, Loadable, ViewHeader } from '../ui';

type Today = {
  users: { total: number; new_today: number; pending_verification: number; blocked: number };
  payments?: {
    orders_today: number;
    paid_today: number;
    revenue_today_paise: string;
    failed_today: number;
    refunds_today: number;
  };
  notifications_today: number;
  recent_activity: {
    at: string;
    actor_user_id: number | null;
    action: string;
    resource: string;
    subject_user_id: number | null;
  }[];
};
type Point = { day: string; count: number; amount_paise: string };

const DAYS = 30;

function range(): string {
  const to = new Date();
  const from = new Date(to.getTime() - (DAYS - 1) * 86_400_000);
  return `from=${from.toISOString()}&to=${to.toISOString()}`;
}

/// The home screen (admin panel plan, Phase A): today's figures, 30-day trends, and what the
/// team did last. Money appears only for roles that may see payments.
export function DashboardView({ permissions }: { permissions: string[] }) {
  const [today, setToday] = useState<Today | null>(null);
  const [signups, setSignups] = useState<Point[]>([]);
  const [paid, setPaid] = useState<Point[]>([]);
  const [error, setError] = useState<string | null>(null);
  const canChart = permissions.includes('reports.read');

  useEffect(() => {
    call<Today>('dashboard')
      .then(setToday)
      .catch((e) => setError(errorText(e, 'Could not load the dashboard.')));
    if (!canChart) return;
    call<Point[]>(`metrics/series?metric=signups&${range()}`)
      .then(setSignups)
      .catch(() => undefined);
    call<Point[]>(`metrics/series?metric=payments_paid&${range()}`)
      .then(setPaid)
      .catch(() => undefined);
  }, [canChart]);

  const u = today?.users;
  const p = today?.payments;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-auto pb-4">
      <ViewHeader title="Dashboard" subtitle="Today, in India time. Demo accounts are left out." />
      <ErrorNote message={error} />

      <Loadable loading={!today && !error} empty={!today} emptyText="Nothing to show yet.">
        <section aria-label="Today" className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-5">
          <KpiCard label="Total users" value={u?.total ?? 0} />
          <KpiCard label="New today" value={u?.new_today ?? 0} />
          <KpiCard
            label="Pending verification"
            value={u?.pending_verification ?? 0}
            hint="Email not confirmed"
            highlight={(u?.pending_verification ?? 0) > 0}
          />
          <KpiCard label="Blocked" value={u?.blocked ?? 0} />
          <KpiCard label="Notifications today" value={today?.notifications_today ?? 0} />
          {p && (
            <>
              <KpiCard label="Orders today" value={p.orders_today} />
              <KpiCard label="Revenue today" value={inr(p.revenue_today_paise)} hint={`${p.paid_today} paid`} />
              <KpiCard
                label="Failed today"
                value={p.failed_today}
                highlight={p.failed_today > 0}
              />
              <KpiCard label="Refunds today" value={p.refunds_today} />
            </>
          )}
        </section>

        {canChart && (
          <section aria-label="Last 30 days" className="grid gap-3 lg:grid-cols-2">
            <LineChart
              label="New users, last 30 days"
              points={signups.map((s) => ({ day: s.day, value: s.count }))}
            />
            <LineChart
              label="Revenue, last 30 days"
              points={paid.map((s) => ({ day: s.day, value: Number(s.amount_paise) }))}
              format={inr}
            />
          </section>
        )}

        <section aria-label="Recent admin activity" className="card p-2">
          <h3 className="px-3 pt-2 text-[13px] font-medium text-ink">Recent admin activity</h3>
          <Loadable loading={false} empty={!today?.recent_activity.length} emptyText="No admin actions yet.">
            <table className="mt-1 w-full border-collapse text-[13px]">
              <tbody>
                {today?.recent_activity.map((a, i) => (
                  <tr key={i} className="border-t border-line">
                    <td className="px-3 py-2 text-ink-muted">{stamp(a.at)}</td>
                    <td className="px-3 py-2 text-ink">
                      {a.actor_user_id === null ? 'system' : `#${a.actor_user_id}`}
                    </td>
                    <td className="px-3 py-2 text-ink">{a.action.replace(/_/g, ' ')}</td>
                    <td className="px-3 py-2 text-ink-muted">
                      {a.subject_user_id === null ? a.resource : `#${a.subject_user_id}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Loadable>
        </section>
      </Loadable>
    </div>
  );
}
