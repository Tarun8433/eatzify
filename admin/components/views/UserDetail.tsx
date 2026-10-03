'use client';

import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { call, errorText } from '@/lib/client';
import { inr, stamp } from '@/lib/format';
import { Button, ConfirmDialog, ErrorNote, Loadable, ViewHeader, type ConfirmField } from '../ui';
import { STATE_LABEL, type UserRow } from './UsersView';

type Detail = UserRow & {
  provider: string;
  is_demo: boolean;
  subscription: { tier: string; status: string; ends_at: string | null } | null;
  blocks: {
    reason: string;
    note: string | null;
    blocked_by: number;
    blocked_at: string;
    until: string | null;
    lifted_at: string | null;
    lifted_by: number | null;
  }[];
  sessions: { started_at: string }[];
  payments: {
    order_id: string;
    amount_paise: string;
    status: string;
    tier: string;
    duration: string;
    created_at: string;
  }[];
  tickets: { id: string; subject: string; status: string; last_message_at: string }[];
};

type Action =
  | 'reveal'
  | 'block'
  | 'unblock'
  | 'edit'
  | 'reset'
  | 'resend'
  | 'delete'
  | null;

const REASONS = [
  { value: 'support_ticket', label: 'Support ticket' },
  { value: 'fraud_review', label: 'Fraud review' },
  { value: 'data_subject_request', label: 'Data request from the person' },
  { value: 'safety_review', label: 'Safety review' },
];

const BLOCK_FIELDS: ConfirmField[] = [
  {
    kind: 'select',
    name: 'reason',
    label: 'Reason',
    options: [
      { value: 'spam', label: 'Spam' },
      { value: 'fraud', label: 'Fraud' },
      { value: 'abuse', label: 'Abuse' },
      { value: 'suspicious', label: 'Suspicious activity' },
      { value: 'policy', label: 'Policy violation' },
      { value: 'other', label: 'Other' },
    ],
  },
  {
    kind: 'select',
    name: 'duration',
    label: 'Duration',
    options: [
      { value: '24h', label: '24 hours' },
      { value: '7d', label: '7 days' },
      { value: '30d', label: '30 days' },
      { value: 'permanent', label: 'Permanent' },
    ],
  },
  { kind: 'text', name: 'note', label: 'Admin note', optional: true },
];

/// One person: profile, plan, payments, tickets, moderation history, and every action an admin
/// may take on the account. Each action is audited by the API.
export function UserDetail({
  userId,
  permissions,
  onBack,
}: {
  userId: number;
  permissions: string[];
  onBack: () => void;
}) {
  const [user, setUser] = useState<Detail | null>(null);
  const [contact, setContact] = useState<{ email: string | null; phone: string | null } | null>(
    null,
  );
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [action, setAction] = useState<Action>(null);
  const can = (p: string) => permissions.includes(p);

  const load = useCallback(async () => {
    try {
      setUser(await call<Detail>(`users/${userId}`));
    } catch (e) {
      setError(errorText(e, 'Could not load this user.'));
    }
  }, [userId]);

  useEffect(() => {
    void load();
  }, [load]);

  const done = (message: string, next?: Detail) => {
    setNotice(message);
    if (next) setUser(next);
    else void load();
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto pb-4">
      <ViewHeader
        title={user ? user.name || `User #${userId}` : `User #${userId}`}
        subtitle={user ? `${STATE_LABEL[user.state]} · ${user.role} · signed up with ${user.provider}` : undefined}
      >
        <Button onClick={onBack}>Back to users</Button>
      </ViewHeader>
      <ErrorNote message={error} />
      {notice && <p className="rounded-tile bg-raised px-4 py-3 text-[13px] text-ink">{notice}</p>}

      <Loadable loading={!user && !error} empty={!user} emptyText="No such user.">
        {user && (
          <>
            {can('users.manage') && (
              <div className="flex flex-wrap gap-2">
                {can('users.reveal') && !contact && (
                  <Button onClick={() => setAction('reveal')}>Reveal contact</Button>
                )}
                {user.state === 'blocked' ? (
                  <Button onClick={() => setAction('unblock')}>Unblock</Button>
                ) : (
                  <Button tone="danger" onClick={() => setAction('block')}>
                    Block
                  </Button>
                )}
                <Button onClick={() => setAction('edit')}>Edit name</Button>
                <Button onClick={() => setAction('reset')}>Send password reset</Button>
                {user.state === 'unverified' && (
                  <Button onClick={() => setAction('resend')}>Resend verification code</Button>
                )}
                {can('staff.manage') && (
                  <Button tone="danger" onClick={() => setAction('delete')}>
                    Delete account
                  </Button>
                )}
              </div>
            )}

            <div className="grid gap-3 lg:grid-cols-2">
              <Section title="Profile">
                <Row label="User id" value={`#${user.user_id}`} />
                <Row label="Email" value={contact?.email ?? user.email_masked ?? '—'} />
                <Row label="Mobile" value={contact?.phone ?? user.phone_masked ?? '—'} />
                <Row label="Registered" value={stamp(user.registered_at)} />
                <Row label="Last sign-in" value={stamp(user.last_login_at)} />
                <Row label="Demo account" value={user.is_demo ? 'Yes' : 'No'} />
              </Section>
              <Section title="Plan">
                {user.subscription ? (
                  <>
                    <Row label="Tier" value={user.subscription.tier} />
                    <Row label="Status" value={user.subscription.status} />
                    <Row label="Ends" value={stamp(user.subscription.ends_at)} />
                  </>
                ) : (
                  <p className="text-[13px] text-ink-muted">Free plan.</p>
                )}
                <Row label="Recent sessions" value={String(user.sessions.length)} />
              </Section>
            </div>

            <Section title="Payments">
              <SimpleTable
                empty="No payments."
                head={['Order', 'Amount', 'Plan', 'Status', 'When']}
                rows={user.payments.map((p) => [
                  p.order_id,
                  inr(p.amount_paise),
                  `${p.tier} ${p.duration}`,
                  p.status,
                  stamp(p.created_at),
                ])}
              />
            </Section>
            <Section title="Support tickets">
              <SimpleTable
                empty="No tickets."
                head={['Subject', 'Status', 'Last message']}
                rows={user.tickets.map((t) => [t.subject, t.status, stamp(t.last_message_at)])}
              />
            </Section>
            <Section title="Blocks">
              <SimpleTable
                empty="Never blocked."
                head={['Reason', 'By', 'When', 'Until', 'Lifted']}
                rows={user.blocks.map((b) => [
                  b.note ? `${b.reason} — ${b.note}` : b.reason,
                  `#${b.blocked_by}`,
                  stamp(b.blocked_at),
                  b.until ? stamp(b.until) : 'Permanent',
                  b.lifted_at ? `${stamp(b.lifted_at)}${b.lifted_by ? ` by #${b.lifted_by}` : ' (expired)'}` : '—',
                ])}
              />
            </Section>
          </>
        )}
      </Loadable>

      {action === 'reveal' && (
        <ConfirmDialog
          title="Reveal contact details"
          body="This is recorded in the audit log with the reason you give."
          fields={[{ kind: 'select', name: 'reason', label: 'Reason', options: REASONS }]}
          confirmLabel="Reveal"
          onClose={() => setAction(null)}
          onConfirm={async (v) => {
            setContact(
              await call(`users/${userId}/reveal`, { method: 'POST', body: { reason: v.reason } }),
            );
          }}
        />
      )}
      {action === 'block' && (
        <ConfirmDialog
          title="Block this account"
          body="They are signed out within 15 minutes and cannot sign in until the block ends."
          fields={BLOCK_FIELDS}
          confirmLabel="Block user"
          tone="danger"
          onClose={() => setAction(null)}
          onConfirm={async (v) =>
            done(
              'Blocked.',
              await call<Detail>(`users/${userId}/block`, {
                method: 'POST',
                body: { reason: v.reason, duration: v.duration, note: v.note || undefined },
              }),
            )
          }
        />
      )}
      {action === 'unblock' && (
        <ConfirmDialog
          title="Unblock this account"
          confirmLabel="Unblock"
          onClose={() => setAction(null)}
          onConfirm={async () =>
            done('Unblocked.', await call<Detail>(`users/${userId}/unblock`, { method: 'POST' }))
          }
        />
      )}
      {action === 'edit' && (
        <ConfirmDialog
          title="Edit name"
          fields={[
            { kind: 'text', name: 'first_name', label: 'First name', optional: true },
            { kind: 'text', name: 'last_name', label: 'Last name', optional: true },
          ]}
          confirmLabel="Save"
          onClose={() => setAction(null)}
          onConfirm={async (v) => {
            const body: Record<string, string> = {};
            if (v.first_name) body.first_name = v.first_name;
            if (v.last_name) body.last_name = v.last_name;
            done('Saved.', await call<Detail>(`users/${userId}`, { method: 'PATCH', body }));
          }}
        />
      )}
      {action === 'reset' && (
        <ConfirmDialog
          title="Send a password reset link"
          body="An email goes to the address on the account with a link to choose a new password."
          confirmLabel="Send link"
          onClose={() => setAction(null)}
          onConfirm={async () => {
            await call(`users/${userId}/password-reset`, { method: 'POST' });
            done('Reset link sent.');
          }}
        />
      )}
      {action === 'resend' && (
        <ConfirmDialog
          title="Resend the verification code"
          confirmLabel="Send code"
          onClose={() => setAction(null)}
          onConfirm={async () => {
            await call(`users/${userId}/resend-verification`, { method: 'POST' });
            done('Code sent.');
          }}
        />
      )}
      {action === 'delete' && (
        <ConfirmDialog
          title="Delete this account"
          body="The person can no longer sign in. Payments and the audit log keep their records."
          totp
          confirmLabel="Delete account"
          tone="danger"
          onClose={() => setAction(null)}
          onConfirm={async (_v, totp) => {
            await call(`users/${userId}`, { method: 'DELETE', totp });
            onBack();
          }}
        />
      )}
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="card p-4">
      <h3 className="mb-2 text-[13px] font-medium text-ink">{title}</h3>
      {children}
    </section>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4 border-t border-line py-1.5 text-[13px] first:border-t-0">
      <span className="text-ink-muted">{label}</span>
      <span className="text-right text-ink">{value}</span>
    </div>
  );
}

function SimpleTable({ head, rows, empty }: { head: string[]; rows: string[][]; empty: string }) {
  if (rows.length === 0) return <p className="text-[13px] text-ink-muted">{empty}</p>;
  return (
    <table className="w-full border-collapse text-[13px]">
      <thead>
        <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
          {head.map((h) => (
            <th key={h} className="px-2 py-1.5 font-medium">
              {h}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((r, i) => (
          <tr key={i} className="border-t border-line">
            {r.map((cell, j) => (
              <td key={j} className={`px-2 py-1.5 ${j === 0 ? 'text-ink' : 'text-ink-muted'}`}>
                {cell}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
