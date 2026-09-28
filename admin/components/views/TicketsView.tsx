'use client';

import { useCallback, useEffect, useState } from 'react';
import { CheckIcon, RefreshIcon, SpinnerIcon } from '../icons';

interface TicketRow {
  id: string;
  user_id: number;
  subject: string;
  status: 'new' | 'open' | 'waiting_user' | 'resolved' | 'closed';
  request_id: string | null;
  last_message_at: string;
  created_at: string;
}

interface TicketMessage {
  id: string;
  body: string;
  from_support: boolean;
  created_at: string;
}

type Thread = TicketRow & { messages: TicketMessage[] };

/// The queue first, then the named states. "Waiting" is the work; the rest is history.
const FILTERS = [
  { key: '', label: 'Waiting on us' },
  { key: 'waiting_user', label: 'Waiting on them' },
  { key: 'resolved', label: 'Resolved' },
  { key: 'closed', label: 'Closed' },
] as const;

const STATUS_LABEL: Record<TicketRow['status'], string> = {
  new: 'New',
  open: 'Open',
  waiting_user: 'Waiting on them',
  resolved: 'Resolved',
  closed: 'Closed',
};

function when(iso: string | null): string {
  return iso
    ? new Date(iso).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' })
    : '—';
}

/**
 * docs/09 §9's `GET /admin/tickets` and its replies (D-228).
 *
 * Opening a conversation writes a `read_pii` audit row, which is why the thread is a deliberate
 * click rather than an expanded row in a list: reading somebody's ticket is an action, not a
 * side effect of scrolling past it.
 */
export function TicketsView() {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]['key']>('');
  const [rows, setRows] = useState<TicketRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/tickets${filter ? `?status=${filter}` : ''}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not load the queue.');
      setRows(data as TicketRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the queue.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Support</h2>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Oldest first — a queue sorted newest-first has a bottom nobody reaches.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div role="tablist" aria-label="Filter" className="flex items-center gap-1 rounded-full bg-surface p-1">
            {FILTERS.map((f) => (
              <button
                key={f.key || 'waiting'}
                role="tab"
                aria-selected={f.key === filter}
                onClick={() => {
                  setFilter(f.key);
                  setOpenId(null);
                }}
                className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium transition-colors ${
                  f.key === filter ? 'bg-mint text-mint-ink' : 'text-ink-muted hover:bg-raised hover:text-ink'
                }`}
              >
                {f.label}
              </button>
            ))}
          </div>

          <button
            onClick={() => void load()}
            aria-label="Refresh"
            className="flex h-[34px] w-[34px] items-center justify-center rounded-full bg-surface text-ink-muted transition-colors hover:bg-raised hover:text-ink"
          >
            <RefreshIcon className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </header>

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        {loading && rows.length === 0 ? (
          <Centered>
            <SpinnerIcon className="h-5 w-5 animate-spin text-ink-muted" />
            <span>Loading the queue…</span>
          </Centered>
        ) : error ? (
          <Centered>
            <span className="text-[#ffb4b4]">{error}</span>
            <button
              onClick={() => void load()}
              className="rounded-full bg-raised px-4 py-1.5 text-[12.5px] text-ink hover:bg-line"
            >
              Try again
            </button>
          </Centered>
        ) : rows.length === 0 ? (
          <Centered>
            <span>{filter === '' ? 'Nobody is waiting on us.' : 'Nothing here.'}</span>
          </Centered>
        ) : (
          <ul className="flex flex-col gap-1.5">
            {rows.map((row) => (
              <TicketCard
                key={row.id}
                row={row}
                open={openId === row.id}
                onToggle={() => setOpenId(openId === row.id ? null : row.id)}
                onChanged={() => void load()}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function TicketCard({
  row,
  open,
  onToggle,
  onChanged,
}: {
  row: TicketRow;
  open: boolean;
  onToggle: () => void;
  onChanged: () => void;
}) {
  const [thread, setThread] = useState<Thread | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reply, setReply] = useState('');
  const [busy, setBusy] = useState(false);

  const read = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/tickets/${row.id}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not open the conversation.');
      setThread(data as Thread);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not open the conversation.');
    } finally {
      setLoading(false);
    }
  }, [row.id]);

  useEffect(() => {
    if (open && thread === null) void read();
  }, [open, thread, read]);

  async function act(action: 'reply' | 'resolve' | 'close', body?: object) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/tickets/${row.id}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body ?? {}),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? 'The API refused that.');
      setReply('');
      await read();
      onChanged();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused that.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="rounded-tile bg-surface">
      <button
        onClick={onToggle}
        aria-expanded={open}
        className="flex w-full items-center gap-3 px-4 py-3 text-left"
      >
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[13.5px] text-ink">{row.subject}</span>
          <span className="mt-0.5 block text-[12px] text-ink-muted">
            user {row.user_id} · {STATUS_LABEL[row.status]} · {when(row.last_message_at)}
            {row.request_id ? ` · request ${row.request_id}` : ''}
          </span>
        </span>
        <span className="shrink-0 text-[12px] text-ink-muted">{open ? 'Close' : 'Open'}</span>
      </button>

      {open && (
        <div className="flex flex-col gap-3 border-t border-line px-4 py-3">
          {loading ? (
            <p className="flex items-center gap-2 text-[12.5px] text-ink-muted">
              <SpinnerIcon className="h-4 w-4 animate-spin" /> Reading…
            </p>
          ) : thread ? (
            <>
              <ul className="flex flex-col gap-2">
                {thread.messages.map((m) => (
                  <li
                    key={m.id}
                    className={`max-w-[44rem] rounded-tile px-3 py-2 ${
                      m.from_support ? 'bg-raised' : 'bg-shell'
                    }`}
                  >
                    <p className="text-[11.5px] text-ink-muted">
                      {m.from_support ? 'Support' : `User ${thread.user_id}`} · {when(m.created_at)}
                    </p>
                    <p className="mt-1 whitespace-pre-wrap text-[13px] text-ink">{m.body}</p>
                  </li>
                ))}
              </ul>

              {thread.status !== 'closed' && (
                <div className="flex flex-col gap-2">
                  <textarea
                    value={reply}
                    onChange={(e) => setReply(e.target.value)}
                    rows={3}
                    maxLength={4000}
                    placeholder="Write a reply"
                    aria-label="Reply"
                    className="w-full max-w-[44rem] rounded-tile bg-raised px-3 py-2 text-[13px] text-ink outline-none placeholder:text-ink-muted"
                  />

                  <div className="flex flex-wrap items-center gap-2">
                    <button
                      onClick={() => void act('reply', { body: reply.trim() })}
                      disabled={reply.trim().length === 0 || busy}
                      className="flex items-center gap-1.5 rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
                    >
                      {busy && <SpinnerIcon className="h-3.5 w-3.5 animate-spin" />}
                      Send reply
                    </button>

                    {thread.status !== 'resolved' && (
                      <button
                        onClick={() => void act('resolve')}
                        disabled={busy}
                        className="flex items-center gap-1.5 rounded-full bg-raised px-4 py-1.5 text-[12.5px] text-ink hover:bg-line disabled:opacity-40"
                      >
                        <CheckIcon className="h-3.5 w-3.5" />
                        Mark resolved
                      </button>
                    )}

                    <button
                      onClick={() => void act('close')}
                      disabled={busy}
                      className="rounded-full px-3 py-1.5 text-[12.5px] text-ink-muted hover:text-ink disabled:opacity-40"
                      title="Final — a closed conversation cannot be reopened"
                    >
                      Close for good
                    </button>
                  </div>
                </div>
              )}
            </>
          ) : null}

          {error && <p className="text-[12.5px] text-[#ffb4b4]">{error}</p>}
        </div>
      )}
    </li>
  );
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 py-16 text-[13px] text-ink-muted">
      {children}
    </div>
  );
}
