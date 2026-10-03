'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { stamp } from '@/lib/format';
import { Button, ErrorNote, Loadable, Pill, ViewHeader, inputClass } from '../ui';

type Channel = 'in_app' | 'email' | 'push' | 'sms' | 'whatsapp';
type Campaign = {
  id: string;
  title: string;
  body: string;
  content_class: string;
  channels: Channel[];
  status: 'scheduled' | 'sending' | 'sent' | 'failed' | 'cancelled';
  scheduled_at: string;
  sent_at: string | null;
  audience: number | null;
  results: Partial<Record<Channel, { sent: number; failed: number }>>;
  read: number;
  error: string | null;
};

const CHANNEL_LABEL: Record<Channel, string> = {
  in_app: 'In-app',
  email: 'Email',
  push: 'Push',
  sms: 'SMS',
  whatsapp: 'WhatsApp',
};

const AUDIENCES = [
  { key: 'all', label: 'All users' },
  { key: 'active', label: 'Verified users' },
  { key: 'unverified', label: 'Unverified users' },
  { key: 'tier:BASIC', label: 'Basic plan' },
  { key: 'tier:PRO', label: 'Pro plan' },
  { key: 'selected', label: 'Selected users' },
] as const;

const CLASSES = [
  { key: 'service', label: 'Service (account, plan, app news)' },
  { key: 'commercial', label: 'Promotion (only people who allowed marketing)' },
  { key: 'clinical', label: 'Health (only for health guidance)' },
];

function segmentFor(audience: string, ids: string): Record<string, unknown> {
  if (audience === 'active' || audience === 'unverified') return { account_state: audience };
  if (audience.startsWith('tier:')) return { tier: audience.slice(5) };
  if (audience === 'selected') {
    return {
      user_ids: ids
        .split(/[\s,]+/)
        .map(Number)
        .filter((n) => Number.isInteger(n) && n > 0),
    };
  }
  return {};
}

/// Admin panel plan, Phase C: send a message to many people, now or later, and see how it did.
export function MessagesView() {
  const [tab, setTab] = useState<'send' | 'history'>('send');
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto pb-4">
      <ViewHeader title="Messages" subtitle="In-app, email and push. SMS and WhatsApp switch on once their providers are set up.">
        <Pill active={tab === 'send'} onClick={() => setTab('send')}>Send</Pill>
        <Pill active={tab === 'history'} onClick={() => setTab('history')}>History</Pill>
      </ViewHeader>
      {tab === 'send' ? <Compose onSent={() => setTab('history')} /> : <History />}
    </div>
  );
}

function Compose({ onSent }: { onSent: () => void }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [audience, setAudience] = useState('all');
  const [ids, setIds] = useState('');
  const [contentClass, setContentClass] = useState('service');
  const [channels, setChannels] = useState<Channel[]>(['in_app']);
  const [available, setAvailable] = useState<Record<Channel, boolean> | null>(null);
  const [when, setWhen] = useState('');
  const [count, setCount] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    call<Record<Channel, boolean>>('campaigns/channels').then(setAvailable).catch(() => undefined);
  }, []);

  const segment = segmentFor(audience, ids);
  const segmentKey = JSON.stringify(segment);

  useEffect(() => {
    setCount(null);
    const t = setTimeout(() => {
      call<{ count: number }>('campaigns/preview', {
        method: 'POST',
        body: { segment: JSON.parse(segmentKey), content_class: contentClass },
      })
        .then((r) => setCount(r.count))
        .catch((e) => setError(errorText(e, 'Could not count the audience.')));
    }, 300);
    return () => clearTimeout(t);
  }, [segmentKey, contentClass]);

  function toggle(c: Channel) {
    if (c === 'in_app') return;
    setChannels((now) => (now.includes(c) ? now.filter((x) => x !== c) : [...now, c]));
  }

  async function send() {
    setBusy(true);
    setError(null);
    try {
      await call('campaigns', {
        method: 'POST',
        body: {
          title,
          body,
          content_class: contentClass,
          segment,
          channels,
          ...(when ? { scheduled_at: new Date(when).toISOString() } : {}),
        },
      });
      onSent();
    } catch (e) {
      setError(errorText(e, 'Could not send.'));
    } finally {
      setBusy(false);
    }
  }

  const ready = title.trim().length >= 2 && body.trim().length >= 2 && (count ?? 0) > 0 && !busy;

  return (
    <section className="card max-w-[720px] space-y-3 p-5">
      <label className="block text-[12.5px] text-ink-muted">
        Title
        <input value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none" />
      </label>
      <label className="block text-[12.5px] text-ink-muted">
        Message
        <textarea value={body} maxLength={1000} rows={4} onChange={(e) => setBody(e.target.value)} className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none" />
      </label>

      <div className="grid gap-3 md:grid-cols-2">
        <label className="block text-[12.5px] text-ink-muted">
          Send to
          <select value={audience} onChange={(e) => setAudience(e.target.value)} className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none">
            {AUDIENCES.map((a) => <option key={a.key} value={a.key}>{a.label}</option>)}
          </select>
        </label>
        <label className="block text-[12.5px] text-ink-muted">
          Kind of message
          <select value={contentClass} onChange={(e) => setContentClass(e.target.value)} className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none">
            {CLASSES.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
          </select>
        </label>
      </div>
      {audience === 'selected' && (
        <label className="block text-[12.5px] text-ink-muted">
          User ids (comma or space separated)
          <input value={ids} onChange={(e) => setIds(e.target.value)} className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none" />
        </label>
      )}

      <fieldset>
        <legend className="text-[12.5px] text-ink-muted">Channels</legend>
        <div className="mt-1 flex flex-wrap gap-2">
          {(Object.keys(CHANNEL_LABEL) as Channel[]).map((c) => {
            const on = available?.[c] ?? c === 'in_app';
            return (
              <label key={c} className={`flex items-center gap-2 rounded-full bg-surface px-3 py-1.5 text-[12.5px] ${on ? 'text-ink' : 'text-ink-faint'}`}>
                <input type="checkbox" checked={channels.includes(c)} disabled={!on || c === 'in_app'} onChange={() => toggle(c)} />
                {CHANNEL_LABEL[c]}
                {!on && <span className="text-[11px]">(not set up)</span>}
              </label>
            );
          })}
        </div>
      </fieldset>

      <label className="block text-[12.5px] text-ink-muted">
        When (leave empty to send now)
        <input type="datetime-local" value={when} onChange={(e) => setWhen(e.target.value)} className={`mt-1 block ${inputClass}`} />
      </label>

      <p className="text-[13px] text-ink">
        {count === null ? 'Counting the audience…' : `This reaches ${count} ${count === 1 ? 'person' : 'people'}.`}
      </p>
      <ErrorNote message={error} />
      <div className="flex justify-end">
        <Button tone="primary" disabled={!ready} onClick={() => void send()}>
          {busy ? 'Sending…' : when ? 'Schedule' : 'Send now'}
        </Button>
      </div>
    </section>
  );
}

function History() {
  const [rows, setRows] = useState<Campaign[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setRows(await call<Campaign[]>('campaigns'));
    } catch (e) {
      setError(errorText(e, 'Could not load messages.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function cancel(id: string) {
    try {
      await call(`campaigns/${id}/cancel`, { method: 'POST' });
      await load();
    } catch (e) {
      setError(errorText(e, 'Could not cancel.'));
    }
  }

  return (
    <div className="card min-h-0 flex-1 overflow-auto p-2">
      <ErrorNote message={error} />
      <Loadable loading={loading} empty={rows.length === 0} emptyText="Nothing sent yet.">
        <table className="w-full border-collapse text-[13px]">
          <thead>
            <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
              <th className="px-3 py-2 font-medium">Message</th>
              <th className="px-3 py-2 font-medium">Status</th>
              <th className="px-3 py-2 font-medium">When</th>
              <th className="px-3 py-2 text-right font-medium">Audience</th>
              <th className="px-3 py-2 font-medium">Delivered</th>
              <th className="px-3 py-2 text-right font-medium">Read</th>
              <th className="px-3 py-2" />
            </tr>
          </thead>
          <tbody>
            {rows.map((c) => (
              <tr key={c.id} className="border-t border-line align-top">
                <td className="px-3 py-2 text-ink">
                  {c.title}
                  <div className="text-[12px] text-ink-muted">{c.body.slice(0, 90)}</div>
                </td>
                <td className="px-3 py-2 text-ink">
                  {c.status}
                  {c.error && <div className="text-[12px] text-[#ffb4b4]">{c.error}</div>}
                </td>
                <td className="px-3 py-2 text-ink-muted">{stamp(c.sent_at ?? c.scheduled_at)}</td>
                <td className="px-3 py-2 text-right text-ink">{c.audience ?? '—'}</td>
                <td className="px-3 py-2 text-ink-muted">
                  {Object.entries(c.results).map(([ch, r]) => (
                    <div key={ch}>
                      {CHANNEL_LABEL[ch as Channel]}: {r?.sent ?? 0}
                      {(r?.failed ?? 0) > 0 && ` (${r?.failed} failed)`}
                    </div>
                  ))}
                </td>
                <td className="px-3 py-2 text-right text-ink">{c.read}</td>
                <td className="px-3 py-2 text-right">
                  {c.status === 'scheduled' && <Button onClick={() => void cancel(c.id)}>Cancel</Button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Loadable>
    </div>
  );
}
