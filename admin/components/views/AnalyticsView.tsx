'use client';

import { useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { inr } from '@/lib/format';
import { ErrorNote, KpiCard, LineChart, Loadable, ViewHeader } from '../ui';

type Analytics = {
  dau_today: number;
  mau: number;
  retention_d7: number | null;
  payment_success_rate: number | null;
  refund_rate: number | null;
  dau: { day: string; count: number }[];
};
type Point = { day: string; count: number; amount_paise: string };

const pct = (v: number | null) => (v === null ? '—' : `${Math.round(v * 100)}%`);

/// Admin panel plan, Phase D: how many people use the app, whether they come back, and how
/// payments are going. Active means opened the app that day (counted at sign-in and refresh).
export function AnalyticsView() {
  const [a, setA] = useState<Analytics | null>(null);
  const [signups, setSignups] = useState<Point[]>([]);
  const [paid, setPaid] = useState<Point[]>([]);
  const [failed, setFailed] = useState<Point[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const to = new Date();
    const from = new Date(to.getTime() - 29 * 86_400_000);
    const range = `from=${from.toISOString()}&to=${to.toISOString()}`;
    call<Analytics>('analytics').then(setA).catch((e) => setError(errorText(e, 'Could not load analytics.')));
    call<Point[]>(`metrics/series?metric=signups&${range}`).then(setSignups).catch(() => undefined);
    call<Point[]>(`metrics/series?metric=payments_paid&${range}`).then(setPaid).catch(() => undefined);
    call<Point[]>(`metrics/series?metric=payments_failed&${range}`).then(setFailed).catch(() => undefined);
  }, []);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-auto pb-4">
      <ViewHeader title="Analytics" subtitle="Last 30 days, India time. Demo accounts are left out." />
      <ErrorNote message={error} />
      <Loadable loading={!a && !error} empty={!a} emptyText="No data yet.">
        <section className="grid grid-cols-2 gap-3 md:grid-cols-5">
          <KpiCard label="Active today" value={a?.dau_today ?? 0} />
          <KpiCard label="Active in 30 days" value={a?.mau ?? 0} />
          <KpiCard label="Came back after a week" value={pct(a?.retention_d7 ?? null)} hint="Signed up 7–37 days ago" />
          <KpiCard label="Payment success" value={pct(a?.payment_success_rate ?? null)} />
          <KpiCard label="Refund rate" value={pct(a?.refund_rate ?? null)} />
        </section>
        <section className="grid gap-3 lg:grid-cols-2">
          <LineChart label="Daily active users" points={(a?.dau ?? []).map((d) => ({ day: d.day, value: d.count }))} />
          <LineChart label="New users" points={signups.map((s) => ({ day: s.day, value: s.count }))} />
          <LineChart label="Revenue" points={paid.map((s) => ({ day: s.day, value: Number(s.amount_paise) }))} format={inr} />
          <LineChart label="Failed payments" points={failed.map((s) => ({ day: s.day, value: s.count }))} />
        </section>
      </Loadable>
    </div>
  );
}
