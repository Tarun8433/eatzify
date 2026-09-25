'use client';

import { useCallback, useEffect, useState } from 'react';
import type { AdminOverview } from '@/lib/types';
import { TotpPrompt } from '../TotpPrompt';

/**
 * The live numbers, straight from `GET /admin/metrics/overview`.
 *
 * The only screen on the dashboard where every figure is real. It says so at the top, because a
 * panel of placeholder data next to a panel of live data with nothing distinguishing them is how a
 * demo gets quoted in a meeting.
 */
export function MetricsView({ overview }: { overview: AdminOverview | null }) {
  if (!overview) {
    return (
      <div className="card flex min-h-[300px] flex-1 flex-col items-center justify-center gap-2 text-[13px] text-ink-muted">
        <p className="text-ink">No connection to the API.</p>
        <p>
          Set <code className="rounded bg-raised px-1.5 py-0.5">ADMIN_API_TOKEN</code> and start the
          API on port 3001.
        </p>
      </div>
    );
  }

  const { users, coach_applications: apps, invites, grants, subscriptions } = overview;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto pb-1">
      <header>
        <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Live metrics</h2>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          Every figure here comes from the API. Counts only — nothing on this page identifies anyone.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Big label="Total users" value={users.total} />
        <Big label="Normal users" value={users.normal} />
        <Big
          label="Awaiting review"
          value={apps.awaiting_review}
          // The one number with a person waiting at the other end of it.
          accent={apps.awaiting_review > 0}
          hint={
            apps.oldest_awaiting_review_days !== null
              ? `Oldest: ${apps.oldest_awaiting_review_days}d`
              : undefined
          }
        />
        <Big label="Active grants" value={grants.active} />
      </div>

      <RevenuePanel />

      <div className="grid gap-3 lg:grid-cols-2 xl:grid-cols-3">
        <Breakdown title="Users by role" data={users.by_role} />
        <Breakdown title="Applications by status" data={apps.by_status} />
        <Breakdown title="Applications by discipline" data={apps.by_discipline} />
        <Breakdown title="Verified attributes" data={apps.verified_by_attribute} />
        <Breakdown title="Invites by status" data={invites.by_status} />
        <Breakdown title="Grants by scope" data={grants.by_scope} />
        <Breakdown title="Subscriptions by tier" data={subscriptions.by_tier} />
        <Breakdown title="Subscriptions by status" data={subscriptions.by_status} />
        <div className="card p-4">
          <h3 className="text-[13.5px] font-medium text-ink">Sensitive access</h3>
          <p className="mt-3 text-figure font-medium text-ink">
            {grants.active_health_conditions}
          </p>
          <p className="mt-2 text-[11.5px] text-ink-muted">
            Coaches holding a <code>health_conditions</code> grant. This number should be small and
            watched (docs/10 §5.3).
          </p>
        </div>
      </div>
    </div>
  );
}

function Big({
  label,
  value,
  hint,
  accent,
}: {
  label: string;
  value: number | string;
  hint?: string;
  accent?: boolean;
}) {
  return (
    <div className={`card p-4 ${accent ? 'ring-1 ring-mint/40' : ''}`}>
      <p className="text-[12px] text-ink-muted">{label}</p>
      <p className={`mt-2 text-figure font-medium ${accent ? 'text-mint' : 'text-ink'}`}>
        {value}
      </p>
      {hint && <p className="mt-1 text-[11.5px] text-ink-muted">{hint}</p>}
    </div>
  );
}

function Breakdown({ title, data }: { title: string; data: Record<string, number> }) {
  const entries = Object.entries(data);
  const max = Math.max(1, ...entries.map(([, v]) => v));

  return (
    <div className="card p-4">
      <h3 className="text-[13.5px] font-medium text-ink">{title}</h3>
      {entries.length === 0 ? (
        <p className="mt-3 text-[12.5px] text-ink-faint">None yet.</p>
      ) : (
        <ul className="mt-3 flex flex-col gap-2.5">
          {entries.map(([key, value]) => (
            <li key={key}>
              <div className="flex items-baseline justify-between gap-2">
                <span className="truncate text-[12.5px] capitalize text-ink-muted">
                  {key.replace(/_/g, ' ')}
                </span>
                <span className="text-[13px] font-medium tabular-nums text-ink">{value}</span>
              </div>
              {/* A bar, so the shape of the breakdown reads before the numbers do. */}
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-raised">
                <div
                  className="h-full rounded-full bg-mint"
                  style={{ width: `${(value / max) * 100}%` }}
                />
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}


// ————— D-236: revenue and offers —————

interface Revenue {
  totals: { week_paise: string; month_paise: string; year_paise: string; all_time_paise: string };
  refunded_all_time_paise: string;
  by_plan: { tier: string; duration: string; sold: number; gross_paise: string }[];
  coupons: {
    code: string;
    percent_off: number;
    max_uses: number;
    used_count: number;
    expires_at: string | null;
    active: boolean;
  }[];
}

/// Integer paise (a string of bigint) → "₹1,24,560". Indian grouping, whole rupees.
function rupees(paise: string): string {
  const r = BigInt(paise || '0') / 100n;
  return `₹${Number(r).toLocaleString('en-IN')}`;
}

function RevenuePanel() {
  const [data, setData] = useState<Revenue | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/revenue');
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? 'Could not load revenue.');
      setData(body as Revenue);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load revenue.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (error) return <div className="card p-4 text-[13px] text-ink-muted">{error}</div>;
  if (!data) return <div className="card p-4 text-[13px] text-ink-muted">Loading revenue…</div>;

  const top = data.by_plan[0];

  return (
    <>
      <header className="mt-2">
        <h3 className="text-[15px] font-semibold text-ink">Revenue</h3>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          Money actually kept: paid orders only, demo accounts excluded, refunds shown apart.
          Windows are rolling — last 7 / 30 / 365 days.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Big label="This week" value={rupees(data.totals.week_paise)} />
        <Big label="This month" value={rupees(data.totals.month_paise)} />
        <Big label="This year" value={rupees(data.totals.year_paise)} />
        <Big
          label="All time"
          value={rupees(data.totals.all_time_paise)}
          hint={`Refunded: ${rupees(data.refunded_all_time_paise)}`}
        />
      </div>

      <div className="card p-4">
        <h4 className="text-[13px] font-semibold text-ink">Plans by sales</h4>
        {data.by_plan.length === 0 ? (
          <p className="mt-2 text-[12.5px] text-ink-muted">Nothing sold yet.</p>
        ) : (
          <table className="mt-2 w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="py-1.5 font-medium">Plan</th>
                <th className="py-1.5 font-medium">Sold</th>
                <th className="py-1.5 font-medium">Gross</th>
                <th className="py-1.5" />
              </tr>
            </thead>
            <tbody>
              {data.by_plan.map((p) => (
                <tr key={`${p.tier}-${p.duration}`} className="border-t border-edge">
                  <td className="py-1.5 text-ink">
                    {p.tier} · {p.duration}
                  </td>
                  <td className="py-1.5">{p.sold}</td>
                  <td className="py-1.5">{rupees(p.gross_paise)}</td>
                  <td className="py-1.5 text-right">
                    {top && p === top ? (
                      <span className="rounded-full bg-mint px-2 py-0.5 text-[11px] font-medium text-mint-ink">
                        Best seller
                      </span>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <OffersPanel coupons={data.coupons} onChanged={load} />
    </>
  );
}

function OffersPanel({
  coupons,
  onChanged,
}: {
  coupons: Revenue['coupons'];
  onChanged: () => Promise<void>;
}) {
  const [code, setCode] = useState('');
  const [pct, setPct] = useState('10');
  const [uses, setUses] = useState('50');
  const [expiry, setExpiry] = useState('');
  const [pending, setPending] = useState<null | { kind: 'create' } | { kind: 'deactivate'; code: string }>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  async function run(totp: string) {
    if (!pending) return;
    setBusy(true);
    setError(null);
    try {
      const res =
        pending.kind === 'create'
          ? await fetch('/api/coupons', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'x-totp': totp },
              body: JSON.stringify({
                code,
                percent_off: Number(pct),
                max_uses: Number(uses),
                expires_at: expiry === '' ? null : new Date(expiry).toISOString(),
              }),
            })
          : await fetch('/api/coupons/deactivate', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'x-totp': totp },
              body: JSON.stringify({ code: pending.code }),
            });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(body?.error?.user_message ?? body?.error ?? 'The API refused.');
      }
      setDone(pending.kind === 'create' ? `Offer ${body.code} is live.` : `Offer ${body.code} switched off.`);
      setPending(null);
      if (pending.kind === 'create') setCode('');
      await onChanged();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card flex flex-col gap-3 p-4">
      <div>
        <h4 className="text-[13px] font-semibold text-ink">Offers</h4>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          A code, a percentage off (max 90), a budget of uses, an optional expiry. A use is spent
          only when a payment actually lands. Creating or switching one off asks for your
          authenticator — offers change what people pay.
        </p>
      </div>

      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Code
          <input
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="DIWALI25"
            className="w-36 rounded-lg border border-edge bg-raised px-2 py-1.5 text-[13px] text-ink"
          />
        </label>
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          % off
          <input
            value={pct}
            onChange={(e) => setPct(e.target.value)}
            inputMode="numeric"
            className="w-20 rounded-lg border border-edge bg-raised px-2 py-1.5 text-[13px] text-ink"
          />
        </label>
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Max uses
          <input
            value={uses}
            onChange={(e) => setUses(e.target.value)}
            inputMode="numeric"
            className="w-24 rounded-lg border border-edge bg-raised px-2 py-1.5 text-[13px] text-ink"
          />
        </label>
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Expires (optional)
          <input
            type="date"
            value={expiry}
            onChange={(e) => setExpiry(e.target.value)}
            className="rounded-lg border border-edge bg-raised px-2 py-1.5 text-[13px] text-ink"
          />
        </label>
        <button
          type="button"
          onClick={() => {
            setDone(null);
            setPending({ kind: 'create' });
          }}
          disabled={code.trim().length < 3 || busy}
          className="rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
        >
          Create offer
        </button>
      </div>

      {coupons.length > 0 && (
        <table className="w-full border-collapse text-[13px]">
          <thead>
            <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
              <th className="py-1.5 font-medium">Code</th>
              <th className="py-1.5 font-medium">Off</th>
              <th className="py-1.5 font-medium">Used</th>
              <th className="py-1.5 font-medium">Expires</th>
              <th className="py-1.5" />
            </tr>
          </thead>
          <tbody>
            {coupons.map((c) => (
              <tr key={c.code} className="border-t border-edge">
                <td className="py-1.5 font-medium text-ink">{c.code}</td>
                <td className="py-1.5">{c.percent_off}%</td>
                <td className="py-1.5">
                  {c.used_count} / {c.max_uses}
                </td>
                <td className="py-1.5">
                  {c.expires_at ? new Date(c.expires_at).toLocaleDateString('en-IN') : '—'}
                </td>
                <td className="py-1.5 text-right">
                  {c.active ? (
                    <button
                      type="button"
                      onClick={() => {
                        setDone(null);
                        setPending({ kind: 'deactivate', code: c.code });
                      }}
                      className="text-[12px] text-ink-muted underline-offset-2 hover:underline"
                    >
                      Switch off
                    </button>
                  ) : (
                    <span className="text-[12px] text-ink-muted">off</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {pending && (
        <TotpPrompt
          action={pending.kind === 'create' ? `Creating offer ${code}` : `Switching off ${pending.code}`}
          busy={busy}
          error={error}
          onSubmit={(totp) => void run(totp)}
          onCancel={() => setPending(null)}
        />
      )}

      {done && (
        <p role="status" className="text-[12.5px] text-ink">
          {done}
        </p>
      )}
    </div>
  );
}
