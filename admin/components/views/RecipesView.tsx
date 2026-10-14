'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshIcon, SpinnerIcon } from '../icons';
import { foodErrorLines } from '@/lib/food-form';
import { AddRecipeForm } from './AddRecipeForm';

interface RecipeRow {
  id: string;
  name: string;
  name_hi: string | null;
  servings: number;
  slots: string[];
  status: 'draft' | 'reviewed' | 'published' | 'retired';
  suitable_for: string[];
  allergens: string[];
  per_serving: { kcal: number; protein_g: number; fat_g: number; carb_g: number };
  ingredients: { food_id: string; name: string; grams: number }[];
  available: boolean;
}

const STEPS = ['draft', 'reviewed', 'published', 'retired'] as const;

/// The food review's lifecycle, for recipes (D-263). Publishing straight from a draft is refused.
const ACTIONS: Record<RecipeRow['status'], { action: 'review' | 'publish' | 'retire'; label: string }[]> = {
  draft: [{ action: 'review', label: 'Mark reviewed' }],
  reviewed: [
    { action: 'publish', label: 'Publish' },
    { action: 'retire', label: 'Retire' },
  ],
  published: [{ action: 'retire', label: 'Retire' }],
  retired: [{ action: 'review', label: 'Back to reviewed' }],
};

/**
 * Recipes shown on the app's Plan tab (D-263): dishes made of published foods. Every figure is the
 * API's, worked out from the foods — nothing here is typed in as nutrition.
 */
export function RecipesView() {
  const [status, setStatus] = useState<(typeof STEPS)[number]>('draft');
  const [rows, setRows] = useState<RecipeRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/admin/recipes?status=${status}`);
      const data = await res.json();
      if (!res.ok) throw new Error(foodErrorLines(data).join(' '));
      setRows(data as RecipeRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the recipes.');
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
      const res = await fetch(`/api/admin/recipes/${id}/${action}`, { method: 'POST' });
      const data = await res.json().catch(() => null);
      if (!res.ok) throw new Error(foodErrorLines(data).join(' '));
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused that step.');
    } finally {
      setBusyId(null);
    }
  }

  /// A new recipe is a draft, so the queue shows the draft step once it is saved.
  function saved() {
    setAdding(false);
    if (status === 'draft') void load();
    else setStatus('draft');
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Recipes</h2>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Shown on the app&rsquo;s Plan tab once published. A recipe leaves the app if any of its foods is retired.
          </p>
        </div>

        <div className="flex items-center gap-2">
          {!adding && (
            <button
              onClick={() => setAdding(true)}
              className="rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink transition-opacity hover:opacity-90"
            >
              Add recipe
            </button>
          )}
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

      {adding && <AddRecipeForm onSaved={saved} onCancel={() => setAdding(false)} />}

      {error && <p role="alert" className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">{error}</p>}

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        {loading && rows.length === 0 ? (
          <Centered>
            <SpinnerIcon className="h-5 w-5 animate-spin text-ink-muted" />
            <span>Loading…</span>
          </Centered>
        ) : rows.length === 0 ? (
          <Centered>
            <span>No recipes at the {status} step.</span>
          </Centered>
        ) : (
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                <th className="px-3 py-2 font-medium">Recipe</th>
                <th className="px-3 py-2 font-medium">Per serving</th>
                <th className="px-3 py-2 font-medium">Suits</th>
                <th className="px-3 py-2 font-medium">Ingredients</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-white/5 align-top">
                  <td className="px-3 py-2.5">
                    <div className="font-medium text-ink">{r.name}</div>
                    {r.name_hi && <div className="text-ink-muted">{r.name_hi}</div>}
                    <div className="text-[11.5px] text-ink-muted">
                      {r.servings} serving{r.servings === 1 ? '' : 's'} · {r.slots.join(', ').replaceAll('_', ' ')}
                    </div>
                    {!r.available && (
                      <div className="text-[11.5px] text-[#ffb4b4]">A food in it is no longer published.</div>
                    )}
                  </td>
                  <td className="px-3 py-2.5 text-ink">
                    {Math.round(r.per_serving.kcal)} kcal
                    <div className="text-[11.5px] text-ink-muted">
                      P {r.per_serving.protein_g} · F {r.per_serving.fat_g} · C {r.per_serving.carb_g} g
                    </div>
                  </td>
                  <td className="px-3 py-2.5 text-ink-muted">
                    {r.suitable_for.join(', ').replaceAll('_', ' ') || '—'}
                    {r.allergens.length > 0 && (
                      <div className="text-[11.5px]">Allergens: {r.allergens.join(', ').replaceAll('_', ' ')}</div>
                    )}
                  </td>
                  <td className="px-3 py-2.5 text-ink-muted">
                    {r.ingredients.map((i) => `${i.name} ${i.grams} g`).join(', ')}
                  </td>
                  <td className="px-3 py-2.5">
                    <div className="flex justify-end gap-1.5">
                      {ACTIONS[r.status].map(({ action, label }) => (
                        <button
                          key={action}
                          disabled={busyId === r.id}
                          onClick={() => void step(r.id, action)}
                          className="rounded-full bg-surface px-3 py-1 text-[12px] text-ink transition-colors hover:bg-raised disabled:opacity-50"
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
  return <div className="flex h-full min-h-[160px] items-center justify-center gap-2 text-[13px] text-ink-muted">{children}</div>;
}
