'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { stamp } from '@/lib/format';
import { Button, ErrorNote, Loadable, ViewHeader } from '../ui';

type Announcement = {
  id: string;
  title: string;
  body: string;
  image_url: string | null;
  priority: 'normal' | 'important' | 'critical';
  audience: 'all' | 'free' | 'paid';
  status: 'draft' | 'published' | 'archived';
  starts_at: string;
  ends_at: string | null;
};

const EMPTY = {
  title: '',
  body: '',
  image_url: '',
  priority: 'normal',
  audience: 'all',
  starts_at: '',
  ends_at: '',
};

const PRIORITY_LABEL = {
  normal: 'Announcement',
  important: 'Important update',
  critical: 'Critical (shown as a pop-up)',
};

/// Admin panel plan, Phase C: news and important updates shown on the app's home screen.
export function AnnouncementsView() {
  const [rows, setRows] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState(EMPTY);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setRows(await call<Announcement[]>('announcements'));
    } catch (e) {
      setError(errorText(e, 'Could not load announcements.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  function edit(a: Announcement | null) {
    setEditing(a?.id ?? 'new');
    setForm(
      a
        ? {
            title: a.title,
            body: a.body,
            image_url: a.image_url ?? '',
            priority: a.priority,
            audience: a.audience,
            starts_at: a.starts_at.slice(0, 16),
            ends_at: a.ends_at?.slice(0, 16) ?? '',
          }
        : EMPTY,
    );
  }

  async function save() {
    setError(null);
    const body = {
      title: form.title,
      body: form.body,
      image_url: form.image_url || null,
      priority: form.priority,
      audience: form.audience,
      ...(form.starts_at ? { starts_at: new Date(form.starts_at).toISOString() } : {}),
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
    };
    try {
      if (editing === 'new') await call('announcements', { method: 'POST', body });
      else await call(`announcements/${editing}`, { method: 'PATCH', body });
      setEditing(null);
      await load();
    } catch (e) {
      setError(errorText(e, 'Could not save.'));
    }
  }

  async function act(id: string, action: 'publish' | 'unpublish' | 'archive') {
    try {
      await call(`announcements/${id}/${action}`, { method: 'POST' });
      await load();
    } catch (e) {
      setError(errorText(e, 'That did not work.'));
    }
  }

  const field = 'mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none';

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto pb-4">
      <ViewHeader title="Announcements" subtitle="Shown on the app's home screen while published and between its dates.">
        <Button tone="primary" onClick={() => edit(null)}>New announcement</Button>
      </ViewHeader>
      <ErrorNote message={error} />

      {editing && (
        <section className="card max-w-[720px] space-y-3 p-5">
          <label className="block text-[12.5px] text-ink-muted">Title
            <input value={form.title} maxLength={120} onChange={(e) => setForm({ ...form, title: e.target.value })} className={field} />
          </label>
          <label className="block text-[12.5px] text-ink-muted">Text
            <textarea value={form.body} maxLength={2000} rows={4} onChange={(e) => setForm({ ...form, body: e.target.value })} className={field} />
          </label>
          <label className="block text-[12.5px] text-ink-muted">Image link (optional)
            <input value={form.image_url} onChange={(e) => setForm({ ...form, image_url: e.target.value })} className={field} />
          </label>
          <div className="grid gap-3 md:grid-cols-2">
            <label className="block text-[12.5px] text-ink-muted">Kind
              <select value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })} className={field}>
                {Object.entries(PRIORITY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </label>
            <label className="block text-[12.5px] text-ink-muted">Who sees it
              <select value={form.audience} onChange={(e) => setForm({ ...form, audience: e.target.value })} className={field}>
                <option value="all">Everyone</option>
                <option value="free">Free plan</option>
                <option value="paid">Paid plans</option>
              </select>
            </label>
            <label className="block text-[12.5px] text-ink-muted">From (empty: now)
              <input type="datetime-local" value={form.starts_at} onChange={(e) => setForm({ ...form, starts_at: e.target.value })} className={field} />
            </label>
            <label className="block text-[12.5px] text-ink-muted">Until (empty: no end)
              <input type="datetime-local" value={form.ends_at} onChange={(e) => setForm({ ...form, ends_at: e.target.value })} className={field} />
            </label>
          </div>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setEditing(null)}>Cancel</Button>
            <Button tone="primary" disabled={form.title.trim().length < 2 || form.body.trim().length < 2} onClick={() => void save()}>Save as draft</Button>
          </div>
        </section>
      )}

      <div className="card p-2">
        <Loadable loading={loading} empty={rows.length === 0} emptyText="No announcements yet.">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">Title</th>
                <th className="px-3 py-2 font-medium">Kind</th>
                <th className="px-3 py-2 font-medium">Who</th>
                <th className="px-3 py-2 font-medium">Status</th>
                <th className="px-3 py-2 font-medium">Window</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map((a) => (
                <tr key={a.id} className="border-t border-line">
                  <td className="px-3 py-2 text-ink">{a.title}</td>
                  <td className="px-3 py-2 text-ink-muted">{PRIORITY_LABEL[a.priority]}</td>
                  <td className="px-3 py-2 text-ink-muted">{a.audience}</td>
                  <td className="px-3 py-2 text-ink">{a.status}</td>
                  <td className="px-3 py-2 text-ink-muted">{stamp(a.starts_at)} → {a.ends_at ? stamp(a.ends_at) : 'no end'}</td>
                  <td className="px-3 py-2 text-right">
                    <div className="flex justify-end gap-2">
                      <Button onClick={() => edit(a)}>Edit</Button>
                      {a.status === 'published' ? (
                        <Button onClick={() => void act(a.id, 'unpublish')}>Unpublish</Button>
                      ) : (
                        <Button tone="primary" onClick={() => void act(a.id, 'publish')}>Publish</Button>
                      )}
                      {a.status !== 'archived' && <Button onClick={() => void act(a.id, 'archive')}>Archive</Button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Loadable>
      </div>
    </div>
  );
}
