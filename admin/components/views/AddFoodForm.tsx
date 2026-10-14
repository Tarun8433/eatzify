'use client';

import { useState, type FormEvent, type ReactNode } from 'react';
import { Button, inputClass } from '../ui';
import {
  ALLERGENS,
  COST_TIERS,
  EMPTY_FOOD,
  FOOD_PREFERENCES,
  foodErrorLines,
  toFoodRow,
  type FoodForm,
} from '@/lib/food-form';

/**
 * A food typed in by hand: `POST /admin/foods`. It always lands as a DRAFT (docs/08 §4), so it
 * reaches users only after someone marks it reviewed and someone publishes it. Every check —
 * required fields, kcal against the macros, allowed values — is the API's; this shows its answer.
 */
export function AddFoodForm({ onSaved, onCancel }: { onSaved: () => void; onCancel: () => void }) {
  const [form, setForm] = useState<FoodForm>(EMPTY_FOOD);
  const [errors, setErrors] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  const set = <K extends keyof FoodForm>(key: K, value: FoodForm[K]) =>
    setForm((f) => ({ ...f, [key]: value }));
  const toggle = (key: 'suitableFor' | 'allergens', value: string) =>
    setForm((f) => ({
      ...f,
      [key]: f[key].includes(value) ? f[key].filter((v) => v !== value) : [...f[key], value],
    }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setErrors([]);
    try {
      const res = await fetch('/api/foods', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ row: toFoodRow(form) }),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        setErrors(foodErrorLines(data));
        return;
      }
      setForm(EMPTY_FOOD);
      onSaved();
    } catch {
      setErrors(['Could not reach the server. Nothing was saved.']);
    } finally {
      setSaving(false);
    }
  }

  const text = (key: keyof FoodForm, label: string, placeholder = '', required = false) => (
    <Field label={label} required={required}>
      <input
        value={form[key] as string}
        onChange={(e) => set(key, e.target.value as never)}
        placeholder={placeholder}
        aria-label={label}
        className={`${inputClass} w-full`}
      />
    </Field>
  );
  const grams = (key: keyof FoodForm, label: string, required = false) => (
    <Field label={label} required={required}>
      <input
        type="number"
        min="0"
        step="any"
        inputMode="decimal"
        value={form[key] as string}
        onChange={(e) => set(key, e.target.value as never)}
        aria-label={label}
        className={`${inputClass} w-full`}
      />
    </Field>
  );

  return (
    <form onSubmit={submit} className="card flex flex-col gap-4 p-4">
      <div>
        <h3 className="text-[15px] font-semibold text-ink">Add food</h3>
        <p className="mt-0.5 text-[12px] text-ink-muted">
          Values per 100 g edible portion. Saved as a draft — users see it once it is reviewed and
          published.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
        {text('name', 'Name', 'Moong dal, cooked', true)}
        {text('nameHi', 'Hindi name', 'मूंग दाल')}
        {text('aliases', 'Other names (comma separated)', 'mung dal, green gram')}
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        {grams('kcal', 'kcal', true)}
        {grams('proteinG', 'Protein (g)', true)}
        {grams('fatG', 'Fat (g)', true)}
        {grams('carbG', 'Carbs (g)', true)}
        {grams('fibreG', 'Fibre (g)')}
      </div>

      <Field label="Suitable for" required>
        <Chips options={FOOD_PREFERENCES} selected={form.suitableFor} onToggle={(v) => toggle('suitableFor', v)} />
      </Field>
      <Field label="Allergens">
        <Chips options={ALLERGENS} selected={form.allergens} onToggle={(v) => toggle('allergens', v)} />
      </Field>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
        {text('measures', 'Household measures', 'katori=150*|spoon=15  (* = default)')}
        <Field label="Cost">
          <select
            value={form.costTier}
            onChange={(e) => set('costTier', e.target.value as FoodForm['costTier'])}
            aria-label="Cost"
            className={`${inputClass} w-full capitalize`}
          >
            {COST_TIERS.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </Field>
        {text('source', 'Source', 'IFCT2017, INDB, manual', true)}
      </div>

      {errors.length > 0 && (
        <ul role="alert" className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">
          {errors.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      )}

      <div className="flex justify-end gap-2">
        <Button onClick={onCancel} disabled={saving}>
          Cancel
        </Button>
        <Button type="submit" tone="primary" disabled={saving}>
          {saving ? 'Saving…' : 'Save as draft'}
        </Button>
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

function Chips({
  options,
  selected,
  onToggle,
}: {
  options: readonly string[];
  selected: string[];
  onToggle: (value: string) => void;
}) {
  return (
    <div className="flex flex-wrap gap-1.5 normal-case tracking-normal">
      {options.map((o) => {
        const on = selected.includes(o);
        return (
          <button
            key={o}
            type="button"
            aria-pressed={on}
            onClick={() => onToggle(o)}
            className={`rounded-full px-3 py-1 text-[12.5px] transition-colors ${
              on ? 'bg-mint text-mint-ink' : 'bg-surface text-ink-muted hover:bg-raised hover:text-ink'
            }`}
          >
            {o.replace('_', ' ')}
          </button>
        );
      })}
    </div>
  );
}
