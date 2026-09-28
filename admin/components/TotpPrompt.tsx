'use client';

import { useState } from 'react';
import { SpinnerIcon } from './icons';

/**
 * The six digits in front of a dangerous action (D-229).
 *
 * Inline, where the action is, rather than a modal: the person already decided to do the thing, and
 * a dialog that covers the screen makes them forget which applicant they had open.
 *
 * The code is never held anywhere but this component's state, and it is good for exactly one
 * action — the API refuses a second use of the same code.
 */
export function TotpPrompt({
  action,
  busy,
  error,
  onSubmit,
  onCancel,
}: {
  /** What the code is about to authorise, in the sentence the person reads. */
  action: string;
  busy: boolean;
  error: string | null;
  onSubmit: (code: string) => void;
  onCancel: () => void;
}) {
  const [code, setCode] = useState('');
  const ready = /^\d{6}$/.test(code);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (ready && !busy) onSubmit(code);
      }}
      className="flex flex-col gap-2 rounded-tile bg-raised p-3"
    >
      <label className="text-[12.5px] text-ink-muted" htmlFor="totp-code">
        {action} needs a code from your authenticator app.
      </label>

      <div className="flex items-center gap-2">
        <input
          id="totp-code"
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          inputMode="numeric"
          autoComplete="one-time-code"
          placeholder="000000"
          autoFocus
          className="w-[7.5rem] rounded-full bg-surface px-4 py-1.5 text-[13px] tracking-[0.3em] text-ink outline-none placeholder:text-ink-muted"
        />

        <button
          type="submit"
          disabled={!ready || busy}
          className="flex items-center gap-1.5 rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
        >
          {busy && <SpinnerIcon className="h-3.5 w-3.5 animate-spin" />}
          Confirm
        </button>

        <button
          type="button"
          onClick={onCancel}
          className="rounded-full px-3 py-1.5 text-[12.5px] text-ink-muted hover:text-ink"
        >
          Cancel
        </button>
      </div>

      {/* The API's own words — including "set one up first" when nobody has enrolled. */}
      {error && <p className="text-[12.5px] text-[#ffb4b4]">{error}</p>}
    </form>
  );
}
