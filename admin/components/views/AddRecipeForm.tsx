'use client';

import { useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { Button, inputClass } from '../ui';
import { foodErrorLines } from '@/lib/food-form';
import { EMPTY_RECIPE, MEAL_SLOTS, matchFoods, toRecipeBody, type RecipeForm } from '@/lib/recipe-form';

interface PublishedFood {
  id: string;
  name: string;
  nameHi: string | null;
}

/**
 * A recipe typed in by hand: `POST /admin/recipes` (D-263). It lands as a DRAFT and is built only
 * from PUBLISHED foods — its nutrition, diets and allergens are all derived from them by the API.
 */
export function AddRecipeForm({ onSaved, onCancel }: { onSaved: () => void; onCancel: () => void }) {
  const [form, setForm] = useState<RecipeForm>(EMPTY_RECIPE);
  const [foods, setFoods] = useState<PublishedFood[]>([]);
  const [query, setQuery] = useState('');
  const [errors, setErrors] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  // ponytail: every published food, once, filtered in the browser — a few hundred rows. Move to a
  // server search when the catalogue reaches the thousands.
  useEffect(() => {
    fetch('/api/admin/foods?status=published')
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((rows: PublishedFood[]) => setFoods(rows))
      .catch(() => setErrors(['Could not load the published foods to choose from.']));
  }, []);

  const set = <K extends keyof RecipeForm>(key: K, value: RecipeForm[K]) =>
    setForm((f) => ({ ...f, [key]: value }));

  const addIngredient = (food: PublishedFood) => {
    setForm((f) => ({ ...f, ingredients: [...f.ingredients, { foodId: food.id, name: food.name, grams: '' }] }));
    setQuery('');
  };
  const setGrams = (foodId: string, grams: string) =>
    setForm((f) => ({
      ...f,
      ingredients: f.ingredients.map((i) => (i.foodId === foodId ? { ...i, grams } : i)),
    }));
  const removeIngredient = (foodId: string) =>
    setForm((f) => ({ ...f, ingredients: f.ingredients.filter((i) => i.foodId !== foodId) }));
  const toggleSlot = (slot: string) =>
    setForm((f) => ({
      ...f,
      slots: f.slots.includes(slot) ? f.slots.filter((s) => s !== slot) : [...f.slots, slot],
    }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setErrors([]);
    try {
      const res = await fetch('/api/admin/recipes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(toRecipeBody(form)),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        setErrors(foodErrorLines(data));
        return;
      }
      setForm(EMPTY_RECIPE);
      onSaved();
    } catch {
      setErrors(['Could not reach the server. Nothing was saved.']);
    } finally {
      setSaving(false);
    }
  }

  const matches = matchFoods(
    foods,
    query,
    form.ingredients.map((i) => i.foodId),
  );

  return (
    <form onSubmit={submit} className="card flex flex-col gap-4 p-4">
      <div>
        <h3 className="text-[15px] font-semibold text-ink">Add recipe</h3>
        <p className="mt-0.5 text-[12px] text-ink-muted">
          Built from published foods. Nutrition, diets and allergens are worked out from them. Saved as a draft —
          users see it once it is reviewed and published.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
        <Field label="Name" required>
          <input value={form.name} onChange={(e) => set('name', e.target.value)} aria-label="Name"
            placeholder="Moong dal chilla" className={`${inputClass} w-full`} />
        </Field>
        <Field label="Hindi name">
          <input value={form.nameHi} onChange={(e) => set('nameHi', e.target.value)} aria-label="Hindi name"
            placeholder="मूंग दाल चीला" className={`${inputClass} w-full`} />
        </Field>
        <Field label="Servings this makes" required>
          <input type="number" min="1" max="20" step="1" value={form.servings}
            onChange={(e) => set('servings', e.target.value)} aria-label="Servings" className={`${inputClass} w-full`} />
        </Field>
      </div>

      <Field label="Meals it suits" required>
        <div className="flex flex-wrap gap-1.5 normal-case tracking-normal">
          {MEAL_SLOTS.map((s) => {
            const on = form.slots.includes(s);
            return (
              <button key={s} type="button" aria-pressed={on} onClick={() => toggleSlot(s)}
                className={`rounded-full px-3 py-1 text-[12.5px] transition-colors ${
                  on ? 'bg-mint text-mint-ink' : 'bg-surface text-ink-muted hover:bg-raised hover:text-ink'
                }`}>
                {s.replace('_', ' ')}
              </button>
            );
          })}
        </div>
      </Field>

      <Field label="Ingredients (grams for the whole recipe)" required>
        <div className="flex flex-col gap-2 normal-case tracking-normal">
          {form.ingredients.map((i) => (
            <div key={i.foodId} className="flex items-center gap-2">
              <span className="flex-1 text-[13px] text-ink">{i.name}</span>
              <input type="number" min="0" step="any" inputMode="decimal" value={i.grams}
                onChange={(e) => setGrams(i.foodId, e.target.value)} aria-label={`Grams of ${i.name}`}
                placeholder="g" className={`${inputClass} w-24`} />
              <Button onClick={() => removeIngredient(i.foodId)}>Remove</Button>
            </div>
          ))}
          <div className="relative">
            <input value={query} onChange={(e) => setQuery(e.target.value)} aria-label="Find a food to add"
              placeholder="Type to find a published food…" className={`${inputClass} w-full`} />
            {matches.length > 0 && (
              <ul className="absolute z-10 mt-1 w-full rounded-tile bg-raised p-1 shadow-lg">
                {matches.map((f) => (
                  <li key={f.id}>
                    <button type="button" onClick={() => addIngredient(f)}
                      className="w-full rounded-full px-3 py-1.5 text-left text-[13px] text-ink hover:bg-surface">
                      {f.name}
                      {f.nameHi && <span className="ml-2 text-ink-muted">{f.nameHi}</span>}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </Field>

      <Field label="Short description">
        <input value={form.description} onChange={(e) => set('description', e.target.value)} aria-label="Description"
          placeholder="A protein-rich savoury pancake" className={`${inputClass} w-full`} />
      </Field>
      <Field label="Method (one step per line)">
        <textarea value={form.steps} onChange={(e) => set('steps', e.target.value)} aria-label="Method" rows={5}
          className="w-full rounded-tile bg-surface px-4 py-2 text-[12.5px] normal-case tracking-normal text-ink outline-none placeholder:text-ink-muted"
          placeholder={'Soak the dal for 2 hours\nGrind to a batter\nCook on a hot tawa'} />
      </Field>

      {errors.length > 0 && (
        <ul role="alert" className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">
          {errors.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      )}

      <div className="flex justify-end gap-2">
        <Button onClick={onCancel} disabled={saving}>Cancel</Button>
        <Button type="submit" tone="primary" disabled={saving}>{saving ? 'Saving…' : 'Save as draft'}</Button>
      </div>
    </form>
  );
}

function Field({ label, required = false, children }: { label: string; required?: boolean; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1 text-[11.5px] uppercase tracking-wide text-ink-muted">
      <span>
        {label}
        {required && <span className="text-[#ffb4b4]"> *</span>}
      </span>
      {children}
    </label>
  );
}
