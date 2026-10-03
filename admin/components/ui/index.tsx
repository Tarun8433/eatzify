'use client';

import { useState, type ReactNode } from 'react';
import { SpinnerIcon } from '../icons';

/// Shared pieces for the admin screens (admin panel plan, Phase A): one look for headers, figures,
/// states and confirmations, instead of each view drawing its own.

export function ViewHeader({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children?: ReactNode;
}) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">{title}</h2>
        {subtitle && <p className="mt-0.5 text-[12.5px] text-ink-muted">{subtitle}</p>}
      </div>
      {children && <div className="flex flex-wrap items-center gap-2">{children}</div>}
    </header>
  );
}

export function KpiCard({
  label,
  value,
  hint,
  highlight = false,
}: {
  label: string;
  value: string | number;
  hint?: string;
  highlight?: boolean;
}) {
  return (
    <div className={`card p-4 ${highlight ? 'ring-1 ring-mint/60' : ''}`}>
      <p className="text-[12px] text-ink-muted">{label}</p>
      <p className="mt-1 text-[24px] font-semibold tracking-[-0.02em] text-ink">{value}</p>
      {hint && <p className="mt-0.5 text-[11.5px] text-ink-muted">{hint}</p>}
    </div>
  );
}

export function ErrorNote({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p role="alert" className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">
      {message}
    </p>
  );
}

/// Loading, empty, or the content — never a spinner that outlives its request.
export function Loadable({
  loading,
  empty,
  emptyText,
  children,
}: {
  loading: boolean;
  empty: boolean;
  emptyText: string;
  children: ReactNode;
}) {
  if (loading && empty) {
    return (
      <div className="flex items-center justify-center gap-2 py-16 text-[13px] text-ink-muted">
        <SpinnerIcon className="h-5 w-5 animate-spin" /> Loading…
      </div>
    );
  }
  if (empty) return <p className="py-16 text-center text-[13px] text-ink-muted">{emptyText}</p>;
  return <>{children}</>;
}

export function Pill({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-full px-4 py-1.5 text-[12.5px] transition-colors ${
        active ? 'bg-ink text-shell' : 'bg-surface text-ink-muted hover:bg-raised hover:text-ink'
      }`}
    >
      {children}
    </button>
  );
}

export function Button({
  onClick,
  children,
  tone = 'plain',
  disabled = false,
  type = 'button',
}: {
  onClick?: () => void;
  children: ReactNode;
  tone?: 'plain' | 'primary' | 'danger';
  disabled?: boolean;
  type?: 'button' | 'submit';
}) {
  const tones = {
    plain: 'bg-surface text-ink hover:bg-raised',
    primary: 'bg-mint text-mint-ink hover:opacity-90',
    danger: 'bg-[#5a2323] text-[#ffd0d0] hover:bg-[#6b2a2a]',
  };
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`rounded-full px-4 py-1.5 text-[12.5px] font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${tones[tone]}`}
    >
      {children}
    </button>
  );
}

export const inputClass =
  'rounded-full bg-surface px-4 py-1.5 text-[12.5px] text-ink outline-none placeholder:text-ink-muted';

/// A daily line, drawn as SVG (no chart library). Values are plain numbers; the axis labels are
/// the first and last day.
export function LineChart({
  points,
  label,
  format = (n) => String(n),
}: {
  points: { day: string; value: number }[];
  label: string;
  format?: (n: number) => string;
}) {
  const width = 600;
  const height = 140;
  const max = Math.max(1, ...points.map((p) => p.value));
  const step = points.length > 1 ? width / (points.length - 1) : width;
  const path = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'}${(i * step).toFixed(1)},${(height - (p.value / max) * height).toFixed(1)}`)
    .join(' ');
  const total = points.reduce((sum, p) => sum + p.value, 0);

  return (
    <figure className="card p-4">
      <figcaption className="flex items-baseline justify-between">
        <span className="text-[12.5px] text-ink-muted">{label}</span>
        <span className="text-[15px] font-semibold text-ink">{format(total)}</span>
      </figcaption>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        preserveAspectRatio="none"
        className="mt-3 h-[140px] w-full"
        role="img"
        aria-label={`${label}: ${format(total)} over ${points.length} days`}
      >
        <path d={path} fill="none" stroke="currentColor" strokeWidth={2} className="text-mint" />
      </svg>
      {points.length > 0 && (
        <div className="mt-1 flex justify-between text-[11px] text-ink-muted">
          <span>{points[0].day}</span>
          <span>{points[points.length - 1].day}</span>
        </div>
      )}
    </figure>
  );
}

export type ConfirmField =
  | { kind: 'select'; name: string; label: string; options: { value: string; label: string }[] }
  | { kind: 'text'; name: string; label: string; optional?: boolean };

/**
 * A confirmation for an action that changes something. Asks for whatever the API needs — a
 * reason, a duration, the authenticator code — and shows the API's refusal in place.
 */
export function ConfirmDialog({
  title,
  body,
  fields = [],
  totp = false,
  confirmLabel,
  tone = 'primary',
  onConfirm,
  onClose,
}: {
  title: string;
  body?: string;
  fields?: ConfirmField[];
  totp?: boolean;
  confirmLabel: string;
  tone?: 'primary' | 'danger';
  onConfirm: (values: Record<string, string>, totp: string) => Promise<void>;
  onClose: () => void;
}) {
  const [values, setValues] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      fields.map((f) => [f.name, f.kind === 'select' ? (f.options[0]?.value ?? '') : '']),
    ),
  );
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const missing =
    fields.some((f) => f.kind === 'text' && !f.optional && !values[f.name]?.trim()) ||
    (totp && code.length !== 6);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await onConfirm(values, code);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That did not work.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!missing && !busy) void submit();
        }}
        className="card w-full max-w-[420px] space-y-3 p-5"
      >
        <h3 className="text-[16px] font-semibold text-ink">{title}</h3>
        {body && <p className="text-[13px] text-ink-muted">{body}</p>}

        {fields.map((f) => (
          <label key={f.name} className="block text-[12.5px] text-ink-muted">
            {f.label}
            {f.kind === 'select' ? (
              <select
                value={values[f.name]}
                onChange={(e) => setValues({ ...values, [f.name]: e.target.value })}
                className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none"
              >
                {f.options.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
            ) : (
              <input
                value={values[f.name]}
                onChange={(e) => setValues({ ...values, [f.name]: e.target.value })}
                className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] text-ink outline-none"
              />
            )}
          </label>
        ))}

        {totp && (
          <label className="block text-[12.5px] text-ink-muted">
            Authenticator code
            <input
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              inputMode="numeric"
              autoComplete="one-time-code"
              className="mt-1 block w-full rounded-tile bg-surface px-3 py-2 text-[13px] tracking-[0.3em] text-ink outline-none"
            />
          </label>
        )}

        <ErrorNote message={error} />

        <div className="flex justify-end gap-2 pt-1">
          <Button onClick={onClose}>Cancel</Button>
          <Button type="submit" tone={tone} disabled={missing || busy}>
            {busy ? 'Working…' : confirmLabel}
          </Button>
        </div>
      </form>
    </div>
  );
}
