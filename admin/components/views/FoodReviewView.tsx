'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshIcon, SpinnerIcon } from '../icons';

interface FoodRow {
  id: string;
  name: string;
  nameHi: string | null;
  kcal: string | number;
  proteinG: string | number;
  fatG: string | number;
  carbG: string | number;
  status: 'draft' | 'reviewed' | 'published' | 'retired';
  reviewedByUserId: number | null;
  publishedByUserId: number | null;
}

const STEPS = ['draft', 'reviewed', 'published', 'retired'] as const;

/// What each step offers next. Publishing from a draft is the review step quietly not happening,
/// so the API refuses it and this never offers it.
const ACTIONS: Record<FoodRow['status'], { action: 'review' | 'publish' | 'retire'; label: string }[]> = {
  draft: [{ action: 'review', label: 'Mark reviewed' }],
  reviewed: [
    { action: 'publish', label: 'Publish' },
    { action: 'retire', label: 'Retire' },
  ],
  published: [{ action: 'retire', label: 'Retire' }],
  retired: [{ action: 'review', label: 'Back to reviewed' }],
};

function number(value: string | number): string {
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? String(Math.round(n * 10) / 10) : '—';
}

/**
 * docs/08 §4's lifecycle: draft → reviewed → published → retired, with somebody's name against each
 * step (D-227). A food's macros end up in a person's plan, which is why nothing published itself.
 */
export function FoodReviewView() {
  const [status, setStatus] = useState<(typeof STEPS)[number]>('draft');
  const [rows, setRows] = useState<FoodRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/foods?status=${status}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not load the queue.');
      setRows(data as FoodRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the queue.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [status]);

  useEffect(() => {
    void load();
  }, [load]);

  async function step(id: string, action: 'review' | 'publish' | 'retire') {
    setBusyId(id);
    setError(null);
    try {
      const res = await fetch(`/api/foods/${id}/${action}`, { method: 'POST' });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error ?? 'The API refused that step.');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused that step.');
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Food review</h2>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Nothing is deleted — a retired food is still in somebody&rsquo;s diary.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div role="tablist" aria-label="Step" className="flex items-center gap-1 rounded-full bg-surface p-1">
            {STEPS.map((s) => (
              <button
                key={s}
                role="tab"
                aria-selected={s === status}
                onClick={() => setStatus(s)}
                className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium capitalize transition-colors ${
                  s === status ? 'bg-mint text-mint-ink' : 'text-ink-muted hover:bg-raised hover:text-ink'
                }`}
              >
                {s}
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

      {error && <p className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">{error}</p>}

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        {loading && rows.length === 0 ? (
          <Centered>
            <SpinnerIcon className="h-5 w-5 animate-spin text-ink-muted" />
            <span>Loading…</span>
          </Centered>
        ) : rows.length === 0 ? (
          <Centered>
            <span>Nothing at the {status} step.</span>
          </Centered>
        ) : (
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">Food</th>
                <th className="px-3 py-2 font-medium">kcal</th>
                <th className="px-3 py-2 font-medium">P / F / C</th>
                <th className="px-3 py-2 font-medium">Who</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className="border-t border-line">
                  <td className="px-3 py-2 text-ink">
                    {row.name}
                    {row.nameHi ? <span className="ml-2 text-ink-muted">{row.nameHi}</span> : null}
                  </td>
                  <td className="px-3 py-2 text-ink-muted">{number(row.kcal)}</td>
                  <td className="px-3 py-2 text-ink-muted">
                    {number(row.proteinG)} / {number(row.fatG)} / {number(row.carbG)}
                  </td>
                  <td className="px-3 py-2 text-[12px] text-ink-muted">
                    {row.reviewedByUserId ? `reviewed by ${row.reviewedByUserId}` : '—'}
                    {row.publishedByUserId ? ` · published by ${row.publishedByUserId}` : ''}
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex justify-end gap-1.5">
                      {ACTIONS[row.status].map(({ action, label }) => (
                        <button
                          key={action}
                          onClick={() => void step(row.id, action)}
                          disabled={busyId === row.id}
                          className="rounded-full bg-raised px-3 py-1 text-[12px] text-ink hover:bg-line disabled:opacity-40"
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                  </td>
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
