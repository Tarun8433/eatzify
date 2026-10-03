'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { stamp } from '@/lib/format';
import { Button, ConfirmDialog, ErrorNote, Loadable, ViewHeader } from '../ui';

type Staff = {
  user_id: number;
  name: string;
  email_masked: string | null;
  role_id: number;
  role: string;
  last_login_at: string | null;
};

/// D-260's five roles, plus "user" to take someone off the staff.
export const ROLE_OPTIONS = [
  { value: '8', label: 'Super admin — everything' },
  { value: '1', label: 'Admin — everything except staff' },
  { value: '7', label: 'Support — users, tickets, messages' },
  { value: '9', label: 'Finance — payments, refunds, reports' },
  { value: '10', label: 'Content — offers, foods, announcements' },
  { value: '2', label: 'Not staff (normal user)' },
];

/// Admins & Roles (admin panel plan, Phase A). Super admin only; each change needs the
/// authenticator code and is audited. Nobody can change their own role.
export function StaffView() {
  const [rows, setRows] = useState<Staff[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Staff | null>(null);
  const [addId, setAddId] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setRows(await call<Staff[]>('staff'));
    } catch (e) {
      setError(errorText(e, 'Could not load staff.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <ViewHeader title="Admins & roles" subtitle="Who can open this dashboard, and what each person can do.">
        <input
          value={addId}
          onChange={(e) => setAddId(e.target.value.replace(/\D/g, ''))}
          inputMode="numeric"
          placeholder="User id to add"
          aria-label="User id to make staff"
          className="w-[9rem] rounded-full bg-surface px-4 py-1.5 text-[12.5px] text-ink outline-none placeholder:text-ink-muted"
        />
        <Button
          disabled={!addId}
          onClick={() =>
            setEditing({ user_id: Number(addId), name: '', email_masked: null, role_id: 2, role: '', last_login_at: null })
          }
        >
          Give a role
        </Button>
      </ViewHeader>
      <ErrorNote message={error} />

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        <Loadable loading={loading} empty={rows.length === 0} emptyText="No staff accounts.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">Person</th>
                <th className="px-3 py-2 font-medium">Email</th>
                <th className="px-3 py-2 font-medium">Role</th>
                <th className="px-3 py-2 font-medium">Last sign-in</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map((s) => (
                <tr key={s.user_id} className="border-t border-line">
                  <td className="px-3 py-2 text-ink">
                    {s.name || '—'} <span className="text-[12px] text-ink-muted">#{s.user_id}</span>
                  </td>
                  <td className="px-3 py-2 text-ink-muted">{s.email_masked ?? '—'}</td>
                  <td className="px-3 py-2 text-ink">{s.role}</td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(s.last_login_at)}</td>
                  <td className="px-3 py-2 text-right">
                    <Button onClick={() => setEditing(s)}>Change role</Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Loadable>
      </div>

      {editing && (
        <ConfirmDialog
          title={`Role for user #${editing.user_id}`}
          body="Takes effect at their next sign-in or token refresh (within 15 minutes)."
          fields={[{ kind: 'select', name: 'role', label: 'Role', options: ROLE_OPTIONS }]}
          totp
          confirmLabel="Save role"
          onClose={() => setEditing(null)}
          onConfirm={async (v, totp) => {
            setRows(
              await call<Staff[]>(`staff/${editing.user_id}/role`, {
                method: 'POST',
                body: { role_id: Number(v.role) },
                totp,
              }),
            );
            setAddId('');
          }}
        />
      )}
    </div>
  );
}
