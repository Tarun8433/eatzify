'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { stamp } from '@/lib/format';
import { attemptDetail, OUTCOME_LABEL, type AttemptOutcome, type StoreAttempt } from '@/lib/store-attempts';
import { Button, ErrorNote, Loadable, Pill, ViewHeader, inputClass } from '../ui';

const FILTERS: { key: '' | AttemptOutcome; label: string }[] = [
  { key: '', label: 'All' },
  { key: 'failed', label: 'Failed' },
  { key: 'refused', label: 'Refused by server' },
  { key: 'cancelled', label: 'Cancelled' },
  { key: 'pending', label: 'Pending' },
  { key: 'purchased', label: 'Purchased' },
];

/// D-266: every Google Play / App Store purchase attempt as the app saw it end — including the
/// failures that never reach the server any other way.
export function StoreAttemptsView() {
  const [outcome, setOutcome] = useState<'' | AttemptOutcome>('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [rows, setRows] = useState<StoreAttempt[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(
    async (after: string | null) => {
      setLoading(true);
      setError(null);
      const params = new URLSearchParams({ limit: '50' });
      if (outcome) params.set('outcome', outcome);
      if (from) params.set('from', new Date(from).toISOString());
      if (to) params.set('to', new Date(`${to}T23:59:59`).toISOString());
      if (after) params.set('cursor', after);
      try {
        const page = await call<{ rows: StoreAttempt[]; next_cursor: string | null }>(
          `payments/store-attempts?${params}`,
        );
        setRows((prev) => (after ? [...prev, ...page.rows] : page.rows));
        setCursor(page.next_cursor);
      } catch (e) {
        setError(errorText(e, 'Could not load store attempts.'));
      } finally {
        setLoading(false);
      }
    },
    [outcome, from, to],
  );

  useEffect(() => {
    void load(null);
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <ViewHeader title="Google Play attempts" subtitle="Every store purchase attempt the app saw end, failed ones included.">
        {FILTERS.map((f) => (
          <Pill key={f.key} active={outcome === f.key} onClick={() => setOutcome(f.key)}>
            {f.label}
          </Pill>
        ))}
        <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} aria-label="From" className={inputClass} />
        <input type="date" value={to} onChange={(e) => setTo(e.target.value)} aria-label="To" className={inputClass} />
      </ViewHeader>

      <ErrorNote message={error} />

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        <Loadable loading={loading} empty={rows.length === 0} emptyText="No attempts match.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">When</th>
                <th className="px-3 py-2 font-medium">User</th>
                <th className="px-3 py-2 font-medium">Plan</th>
                <th className="px-3 py-2 font-medium">Outcome</th>
                <th className="px-3 py-2 font-medium">Reason</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => (
                  <tr key={a.id} className="border-t border-line">
                    <td className="px-3 py-2 text-ink-muted">{stamp(a.created_at)}</td>
                    <td className="px-3 py-2 text-ink">
                      {a.user_name || '—'}
                      <span className="ml-1.5 text-[12px] text-ink-muted">#{a.user_id}</span>
                      <div className="text-[12px] text-ink-muted">
                        {[a.email ?? a.email_masked, a.phone ?? a.phone_masked].filter(Boolean).join(' · ') || '—'}
                      </div>
                    </td>
                    <td className="px-3 py-2 text-ink-muted">{a.plan}</td>
                    <td className="px-3 py-2 text-ink">{OUTCOME_LABEL[a.outcome]}</td>
                    <td className="px-3 py-2 text-[12px] text-ink-muted">{attemptDetail(a) || '—'}</td>
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
