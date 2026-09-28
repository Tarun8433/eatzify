'use client';

import { useState } from 'react';
import { SearchIcon, SpinnerIcon } from '../icons';

interface UserRow {
  user_id: number;
  name: string;
  goal: string;
  tier: string;
  phone_masked: string | null;
  last_logged_date: string | null;
}

/// docs/10 §4's closed list. A free-text reason is a reason nobody reads.
const REASONS = ['support_ticket', 'fraud_review', 'data_subject_request', 'safety_review'] as const;

const REASON_LABEL: Record<(typeof REASONS)[number], string> = {
  support_ticket: 'Support ticket',
  fraud_review: 'Fraud review',
  data_subject_request: 'Data subject request',
  safety_review: 'Safety review',
};

/**
 * docs/09 §9's `POST /admin/users/search` (D-227).
 *
 * A POST because a filter may name a health condition, and api rule 6 keeps health data out of
 * query strings. Searching BY a condition is itself a health read: it needs a reason from the
 * closed list and writes an audit row. Searching by name does not — demanding a reason for every
 * lookup is how reasons stop meaning anything.
 *
 * The number is masked. The full one lives behind the client detail's own audited read.
 */
export function UserSearchView() {
  const [query, setQuery] = useState('');
  const [conditions, setConditions] = useState('');
  const [reason, setReason] = useState<(typeof REASONS)[number]>('support_ticket');
  const [rows, setRows] = useState<UserRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const byCondition = conditions.trim().length > 0;

  async function search() {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/users/search', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(byCondition ? { 'X-Reason': reason } : {}),
        },
        body: JSON.stringify({
          query: query.trim() || undefined,
          filters: byCondition
            ? {
                conditions: conditions
                  .split(',')
                  .map((c) => c.trim())
                  .filter(Boolean),
              }
            : undefined,
        }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'The API refused that search.');
      setRows(data as UserRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused that search.');
      setRows(null);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header>
        <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Find someone</h2>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          Names, goals and a masked number — never a diary.
        </p>
      </header>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          void search();
        }}
        className="card flex flex-wrap items-end gap-3 p-4"
      >
        <label className="flex min-w-[14rem] flex-1 flex-col gap-1 text-[12px] text-ink-muted">
          Name, phone or user id
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="e.g. Priya, 98765…, 42"
            className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
          />
        </label>

        <label className="flex min-w-[14rem] flex-1 flex-col gap-1 text-[12px] text-ink-muted">
          Health conditions (comma separated)
          <input
            value={conditions}
            onChange={(e) => setConditions(e.target.value)}
            placeholder="type2_diabetes, hypertension"
            className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
          />
        </label>

        {byCondition && (
          <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
            Reason (audited)
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as (typeof REASONS)[number])}
              className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none"
            >
              {REASONS.map((r) => (
                <option key={r} value={r}>
                  {REASON_LABEL[r]}
                </option>
              ))}
            </select>
          </label>
        )}

        <button
          type="submit"
          disabled={busy}
          className="flex items-center gap-1.5 rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
        >
          {busy ? <SpinnerIcon className="h-3.5 w-3.5 animate-spin" /> : <SearchIcon className="h-3.5 w-3.5" />}
          Search
        </button>
      </form>

      {byCondition && (
        <p className="text-[12px] text-ink-muted">
          Searching by condition is a health read — this one lands in the audit log with the reason
          above.
        </p>
      )}

      {error && <p className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">{error}</p>}

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        {rows === null ? (
          <Centered>
            <span>Search to see people.</span>
          </Centered>
        ) : rows.length === 0 ? (
          <Centered>
            <span>Nobody matched.</span>
          </Centered>
        ) : (
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">User</th>
                <th className="px-3 py-2 font-medium">Phone</th>
                <th className="px-3 py-2 font-medium">Goal</th>
                <th className="px-3 py-2 font-medium">Tier</th>
                <th className="px-3 py-2 font-medium">Last diary day</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.user_id} className="border-t border-line">
                  <td className="px-3 py-2 text-ink">
                    {row.name || '—'} <span className="text-ink-muted">#{row.user_id}</span>
                  </td>
                  <td className="px-3 py-2 text-ink-muted">{row.phone_masked ?? '—'}</td>
                  <td className="px-3 py-2 text-ink-muted">{row.goal || '—'}</td>
                  <td className="px-3 py-2 text-ink-muted">{row.tier || '—'}</td>
                  <td className="px-3 py-2 text-ink-muted">{row.last_logged_date ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 py-16 text-[13px] text-ink-muted">
      {children}
    </div>
  );
}
