'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshIcon, SpinnerIcon } from '../icons';

interface AuditRow {
  id: string;
  actorUserId: number | null;
  actorRole: string;
  action: string;
  subjectUserId: number | null;
  resource: string;
  meta: Record<string, unknown>;
  reason: string | null;
  createdAt: string;
}

const ACTION_LABEL: Record<string, string> = {
  read_health: 'Read health data',
  read_pii: 'Revealed identity',
  export: 'Exported',
  override_plan: 'Overrode a plan',
  change_price: 'Changed a price',
  grant_revoke: 'Revoked a grant',
  coach_verify: 'Verified a partner',
  coach_reject: 'Rejected a partner',
  rule_pack_activate: 'Activated a rule pack',
};

function when(iso: string): string {
  return new Date(iso).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' });
}

/**
 * docs/09 §9's `GET /admin/audit` — who read what, and why.
 *
 * The rows carry ids, actions and reasons. They never carry what was READ: api rule 5 keeps names,
 * numbers and conditions out of logs, and this table is a log. "An admin read user 42's health data
 * for a support ticket" is the record; what it said is not.
 */
export function AuditView() {
  const [actor, setActor] = useState('');
  const [subject, setSubject] = useState('');
  const [rows, setRows] = useState<AuditRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams();
      if (actor.trim()) params.set('actor', actor.trim());
      if (subject.trim()) params.set('subject', subject.trim());

      const res = await fetch(`/api/audit${params.toString() ? `?${params}` : ''}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not read the audit log.');
      setRows(data as AuditRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not read the audit log.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [actor, subject]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Audit log</h2>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Append-only. Who read what, and why — never what it said.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <input
            value={actor}
            onChange={(e) => setActor(e.target.value.replace(/\D/g, ''))}
            inputMode="numeric"
            placeholder="Actor id"
            aria-label="Filter by actor"
            className="w-[7.5rem] rounded-full bg-surface px-4 py-1.5 text-[12.5px] text-ink outline-none placeholder:text-ink-muted"
          />
          <input
            value={subject}
            onChange={(e) => setSubject(e.target.value.replace(/\D/g, ''))}
            inputMode="numeric"
            placeholder="Subject id"
            aria-label="Filter by subject"
            className="w-[7.5rem] rounded-full bg-surface px-4 py-1.5 text-[12.5px] text-ink outline-none placeholder:text-ink-muted"
          />
          <button
            onClick={() => void load()}
            aria-label="Refresh"
            className="flex h-[34px] w-[34px] items-center justify-center rounded-full bg-surface text-ink-muted transition-colors hover:bg-raised hover:text-ink"
          >
            <RefreshIcon className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </header>

      {error && <p className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">{error}</p>}

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        {loading && rows.length === 0 ? (
          <div className="flex h-full items-center justify-center gap-2 py-16 text-[13px] text-ink-muted">
            <SpinnerIcon className="h-5 w-5 animate-spin" /> Loading…
          </div>
        ) : rows.length === 0 ? (
          <p className="py-16 text-center text-[13px] text-ink-muted">Nothing recorded yet.</p>
        ) : (
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">When</th>
                <th className="px-3 py-2 font-medium">Who</th>
                <th className="px-3 py-2 font-medium">Did</th>
                <th className="px-3 py-2 font-medium">To</th>
                <th className="px-3 py-2 font-medium">Resource</th>
                <th className="px-3 py-2 font-medium">Reason</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className="border-t border-line">
                  <td className="px-3 py-2 text-ink-muted">{when(row.createdAt)}</td>
                  <td className="px-3 py-2 text-ink">
                    {row.actorUserId === null ? 'system' : `#${row.actorUserId}`}
                    <span className="ml-1.5 text-[12px] text-ink-muted">({row.actorRole})</span>
                  </td>
                  <td className="px-3 py-2 text-ink">{ACTION_LABEL[row.action] ?? row.action}</td>
                  <td className="px-3 py-2 text-ink-muted">
                    {row.subjectUserId === null ? '—' : `#${row.subjectUserId}`}
                  </td>
                  <td className="px-3 py-2 font-mono text-[12px] text-ink-muted">{row.resource}</td>
                  <td className="px-3 py-2 text-ink-muted">{row.reason ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
