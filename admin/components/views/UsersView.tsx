'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { stamp } from '@/lib/format';
import { ErrorNote, Button, Loadable, Pill, ViewHeader, inputClass } from '../ui';
import { UserDetail } from './UserDetail';

export type UserRow = {
  user_id: number;
  name: string;
  /// Present only for roles allowed to see contact details (D-261).
  email?: string | null;
  email_masked: string | null;
  phone_masked: string | null;
  role: string;
  state: 'active' | 'unverified' | 'blocked';
  registered_at: string;
  last_login_at: string | null;
};

const STATES = [
  { key: '', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'unverified', label: 'Pending verification' },
  { key: 'blocked', label: 'Blocked' },
] as const;

export const STATE_LABEL: Record<UserRow['state'], string> = {
  active: 'Active',
  unverified: 'Email not confirmed',
  blocked: 'Blocked',
};

/// Admin panel plan, Phase A: every account, newest first. Contact details are masked; the full
/// value is one audited "Reveal" away on the person's own page.
export function UsersView({
  permissions,
  initialState = '',
}: {
  permissions: string[];
  initialState?: '' | UserRow['state'];
}) {
  const [state, setState] = useState<string>(initialState);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [rows, setRows] = useState<UserRow[]>([]);
  const [cursor, setCursor] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<number | null>(null);

  const load = useCallback(
    async (after: number | null) => {
      setLoading(true);
      setError(null);
      const params = new URLSearchParams({ limit: '50' });
      if (state) params.set('state', state);
      if (from) params.set('from', new Date(from).toISOString());
      if (to) params.set('to', new Date(`${to}T23:59:59`).toISOString());
      if (after) params.set('cursor', String(after));
      try {
        const page = await call<{ rows: UserRow[]; next_cursor: number | null }>(
          `users?${params}`,
        );
        setRows((prev) => (after ? [...prev, ...page.rows] : page.rows));
        setCursor(page.next_cursor);
      } catch (e) {
        setError(errorText(e, 'Could not load users.'));
      } finally {
        setLoading(false);
      }
    },
    [state, from, to],
  );

  useEffect(() => {
    void load(null);
  }, [load]);

  if (open !== null) {
    return (
      <UserDetail
        userId={open}
        permissions={permissions}
        onBack={() => {
          setOpen(null);
          void load(null);
        }}
      />
    );
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <ViewHeader title="Users" subtitle="Mobile numbers are masked. Open a person to act on their account or reveal their number.">
        {STATES.map((s) => (
          <Pill key={s.key} active={state === s.key} onClick={() => setState(s.key)}>
            {s.label}
          </Pill>
        ))}
        <input
          type="date"
          value={from}
          onChange={(e) => setFrom(e.target.value)}
          aria-label="Registered from"
          className={inputClass}
        />
        <input
          type="date"
          value={to}
          onChange={(e) => setTo(e.target.value)}
          aria-label="Registered to"
          className={inputClass}
        />
      </ViewHeader>

      <ErrorNote message={error} />

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        <Loadable loading={loading} empty={rows.length === 0} emptyText="No users match.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">User</th>
                <th className="px-3 py-2 font-medium">Email</th>
                <th className="px-3 py-2 font-medium">Mobile</th>
                <th className="px-3 py-2 font-medium">Registered</th>
                <th className="px-3 py-2 font-medium">Status</th>
                <th className="px-3 py-2 font-medium">Last sign-in</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr
                  key={r.user_id}
                  onClick={() => setOpen(r.user_id)}
                  className="cursor-pointer border-t border-line hover:bg-raised/50"
                >
                  <td className="px-3 py-2 text-ink">
                    {r.name || '—'}
                    <span className="ml-1.5 text-[12px] text-ink-muted">#{r.user_id}</span>
                  </td>
                  <td className="px-3 py-2 text-ink-muted">{r.email ?? r.email_masked ?? '—'}</td>
                  <td className="px-3 py-2 text-ink-muted">{r.phone_masked ?? '—'}</td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(r.registered_at)}</td>
                  <td className="px-3 py-2 text-ink">{STATE_LABEL[r.state]}</td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(r.last_login_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {cursor && (
            <div className="flex justify-center py-3">
              <Button onClick={() => void load(cursor)} disabled={loading}>
                Load more
              </Button>
            </div>
          )}
        </Loadable>
      </div>
    </div>
  );
}
