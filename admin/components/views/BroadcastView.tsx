'use client';

import { useState } from 'react';
import { BellIcon, SpinnerIcon } from '../icons';

/// docs/13 §5. The class is part of the message, not a guess made later — the targeting rules turn
/// on it, and the API refuses a condition-targeted send that is not clinical.
const CLASSES = [
  { key: 'service', label: 'Service', hint: 'About their account, their plan, their subscription.' },
  { key: 'clinical', label: 'Clinical', hint: 'Safety or condition-related. The only class that may target a condition.' },
  { key: 'commercial', label: 'Commercial', hint: 'Offers and marketing. Never aimed at a health condition.' },
] as const;

interface BroadcastResult {
  sent: number;
  content_class: string;
}

/**
 * docs/09 §9's `POST /admin/notifications` (D-227).
 *
 * The count is shown before anything is written nowhere — there is no dry run, so the send says
 * how many it reached afterwards and the segment is deliberately hard to fill in by accident.
 */
export function BroadcastView() {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [contentClass, setContentClass] = useState<(typeof CLASSES)[number]['key']>('service');
  const [conditions, setConditions] = useState('');
  const [tier, setTier] = useState('');
  const [userIds, setUserIds] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState<BroadcastResult | null>(null);

  const byCondition = conditions.trim().length > 0;
  const ready = title.trim().length > 0 && body.trim().length > 0;

  async function send() {
    setBusy(true);
    setError(null);
    setSent(null);
    try {
      const ids = userIds
        .split(',')
        .map((s) => Number(s.trim()))
        .filter((n) => Number.isInteger(n) && n > 0);

      const segment = {
        ...(byCondition
          ? { conditions: conditions.split(',').map((c) => c.trim()).filter(Boolean) }
          : {}),
        ...(tier.trim() ? { tier: tier.trim() } : {}),
        ...(ids.length > 0 ? { user_ids: ids } : {}),
      };

      const res = await fetch('/api/notifications', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: title.trim(),
          body: body.trim(),
          content_class: contentClass,
          ...(Object.keys(segment).length > 0 ? { segment } : {}),
        }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'The API refused that send.');
      setSent(data as BroadcastResult);
      setTitle('');
      setBody('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused that send.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">
      <header>
        <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Send a message</h2>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          Lands in the app&rsquo;s message list. No segment means everybody.
        </p>
      </header>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (ready && !busy) void send();
        }}
        className="card flex max-w-[52rem] flex-col gap-4 p-5"
      >
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Title
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={120}
            className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none"
          />
        </label>

        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Message
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={4}
            maxLength={1000}
            className="rounded-tile bg-raised px-4 py-2 text-[13px] text-ink outline-none"
          />
        </label>

        <fieldset className="flex flex-col gap-2">
          <legend className="text-[12px] text-ink-muted">What kind of message is this?</legend>
          <div className="flex flex-wrap gap-2">
            {CLASSES.map((c) => (
              <button
                key={c.key}
                type="button"
                onClick={() => setContentClass(c.key)}
                className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium transition-colors ${
                  c.key === contentClass ? 'bg-mint text-mint-ink' : 'bg-raised text-ink-muted hover:text-ink'
                }`}
              >
                {c.label}
              </button>
            ))}
          </div>
          <p className="text-[12px] text-ink-muted">
            {CLASSES.find((c) => c.key === contentClass)?.hint}
          </p>
        </fieldset>

        <div className="flex flex-wrap gap-3">
          <label className="flex min-w-[12rem] flex-1 flex-col gap-1 text-[12px] text-ink-muted">
            Tier (optional)
            <input
              value={tier}
              onChange={(e) => setTier(e.target.value)}
              placeholder="PRO"
              className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
            />
          </label>

          <label className="flex min-w-[12rem] flex-1 flex-col gap-1 text-[12px] text-ink-muted">
            Health conditions (optional)
            <input
              value={conditions}
              onChange={(e) => setConditions(e.target.value)}
              placeholder="type2_diabetes"
              className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
            />
          </label>

          <label className="flex min-w-[12rem] flex-1 flex-col gap-1 text-[12px] text-ink-muted">
            Named people (optional)
            <input
              value={userIds}
              onChange={(e) => setUserIds(e.target.value)}
              placeholder="7, 42"
              className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
            />
          </label>
        </div>

        {byCondition && contentClass !== 'clinical' && (
          <p className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[12.5px] text-[#ffb4b4]">
            docs/13 §5: aiming at a health condition is allowed only for a clinical message. The API
            will refuse this one.
          </p>
        )}

        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={!ready || busy}
            className="flex items-center gap-1.5 rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
          >
            {busy ? <SpinnerIcon className="h-3.5 w-3.5 animate-spin" /> : <BellIcon className="h-3.5 w-3.5" />}
            Send
          </button>

          {sent && (
            <span role="status" className="text-[12.5px] text-ink">
              Sent to {sent.sent} {sent.sent === 1 ? 'person' : 'people'}.
            </span>
          )}
        </div>

        {error && <p className="text-[12.5px] text-[#ffb4b4]">{error}</p>}
      </form>
    </div>
  );
}
