'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { ErrorNote, Loadable, Pill, ViewHeader, inputClass } from '../ui';

type Report = { kind: string; from: string; to: string; columns: string[]; rows: (string | number)[][] };

const KINDS = [
  { key: 'users', label: 'Users' },
  { key: 'payments', label: 'Payments' },
  { key: 'verification', label: 'Verification' },
  { key: 'notifications', label: 'Notifications' },
  { key: 'offers', label: 'Offers' },
] as const;

function isoDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/// Admin panel plan, Phase D: totals by day or by item for a date range, with a CSV download.
/// Reports carry counts and amounts only — never a name, email or phone.
export function ReportsView() {
  const today = new Date();
  const [kind, setKind] = useState<(typeof KINDS)[number]['key']>('users');
  const [from, setFrom] = useState(isoDay(new Date(today.getTime() - 29 * 86_400_000)));
  const [to, setTo] = useState(isoDay(today));
  const [report, setReport] = useState<Report | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const range = `from=${new Date(`${from}T00:00:00+05:30`).toISOString()}&to=${new Date(`${to}T23:59:59+05:30`).toISOString()}`;

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setReport(await call<Report>(`reports/${kind}?${range}`));
    } catch (e) {
      setError(errorText(e, 'Could not build the report.'));
    } finally {
      setLoading(false);
    }
  }, [kind, range]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <ViewHeader title="Reports" subtitle="Totals only, by India time. Downloads are recorded in the audit log.">
        {KINDS.map((k) => (
          <Pill key={k.key} active={kind === k.key} onClick={() => setKind(k.key)}>{k.label}</Pill>
        ))}
        <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} aria-label="From" className={inputClass} />
        <input type="date" value={to} onChange={(e) => setTo(e.target.value)} aria-label="To" className={inputClass} />
        <a
          href={`/api/reports/${kind}?${range}`}
          download
          className="rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink hover:opacity-90"
        >
          Download CSV
        </a>
      </ViewHeader>
      <ErrorNote message={error} />
      <div className="card min-h-0 flex-1 overflow-auto p-2">
        <Loadable loading={loading} empty={!report || report.rows.length === 0} emptyText="Nothing in this range.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                {report?.columns.map((c) => <th key={c} className="px-3 py-2 font-medium">{c.replace(/_/g, ' ')}</th>)}
              </tr>
            </thead>
            <tbody>
              {report?.rows.map((r, i) => (
                <tr key={i} className="border-t border-line">
                  {r.map((v, j) => (
                    <td key={j} className={`px-3 py-2 ${j === 0 ? 'text-ink' : 'text-ink-muted'}`}>{v}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </Loadable>
      </div>
    </div>
  );
}
