'use client';

import { useCallback, useEffect, useState } from 'react';
import { RefreshIcon, SpinnerIcon } from '../icons';
import { TotpPrompt } from '../TotpPrompt';

interface RulePackState {
  active: string;
  available: string[];
  history: {
    version: string;
    activated_by_user_id: number;
    reviewed_by_user_id: number;
    note: string | null;
    created_at: string;
  }[];
}

function when(iso: string): string {
  return new Date(iso).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' });
}

/**
 * docs/09 §9's rule-pack activation (D-229).
 *
 * This is the switch that decides which numbers every plan in the country is generated from, so it
 * asks for three things: a version already on the server, the user id of the person who REVIEWED
 * the pack (somebody other than you), and a code from an authenticator app.
 *
 * The history below is append-only — a rollback is a new row naming the older version, never an
 * edit — which makes this table the record of every change to the numbers.
 */
export function RulePacksView() {
  const [state, setState] = useState<RulePackState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [version, setVersion] = useState('');
  const [reviewedBy, setReviewedBy] = useState('');
  const [note, setNote] = useState('');
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [codeError, setCodeError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/rule-packs');
      const data = await res.json();
      if (res.status === 403) {
        // Correct, not broken: docs/09 §9 makes this super_admin's alone, and the dashboard signs
        // in as one account. Saying which role is missing beats "the API refused the request".
        throw new Error(
          'This screen needs a super admin. The account the dashboard signs in with is an admin, which is one level below.',
        );
      }
      if (!res.ok) throw new Error(data.error ?? 'Could not read the rule packs.');
      setState(data as RulePackState);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not read the rule packs.');
      setState(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function activate(code: string) {
    setBusy(true);
    setCodeError(null);
    try {
      const res = await fetch('/api/rule-packs/activate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Totp': code },
        body: JSON.stringify({
          version,
          reviewed_by: reviewedBy.trim(),
          ...(note.trim() ? { note: note.trim() } : {}),
        }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'The API refused that.');

      setState(data as RulePackState);
      setAsking(false);
      setDone(`Pack ${version} is live.`);
      setVersion('');
      setNote('');
    } catch (e) {
      setCodeError(e instanceof Error ? e.message : 'The API refused that.');
    } finally {
      setBusy(false);
    }
  }

  const ready = version !== '' && /^\d+$/.test(reviewedBy.trim());

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Rule packs</h2>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Which set of clinical constants every new plan is built from. Super admin only.
          </p>
        </div>
        <button
          onClick={() => void load()}
          aria-label="Refresh"
          className="flex h-[34px] w-[34px] items-center justify-center rounded-full bg-surface text-ink-muted transition-colors hover:bg-raised hover:text-ink"
        >
          <RefreshIcon className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </header>

      {error && <p className="rounded-tile bg-[#3a1f1f] px-4 py-3 text-[13px] text-[#ffb4b4]">{error}</p>}

      {state && (
        <>
          <div className="card flex max-w-[52rem] flex-col gap-4 p-5">
            <p className="text-[14px] text-ink">
              Live now: <span className="font-mono">{state.active}</span>
            </p>

            <div className="flex flex-wrap items-end gap-3">
              <label className="flex min-w-[10rem] flex-col gap-1 text-[12px] text-ink-muted">
                Activate version
                <select
                  value={version}
                  onChange={(e) => setVersion(e.target.value)}
                  className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none"
                >
                  <option value="">Choose…</option>
                  {state.available
                    .filter((v) => v !== state.active)
                    .map((v) => (
                      <option key={v} value={v}>
                        {v}
                      </option>
                    ))}
                </select>
              </label>

              <label className="flex min-w-[10rem] flex-col gap-1 text-[12px] text-ink-muted">
                Reviewed by (user id)
                <input
                  value={reviewedBy}
                  onChange={(e) => setReviewedBy(e.target.value.replace(/\D/g, ''))}
                  inputMode="numeric"
                  placeholder="2"
                  className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
                />
              </label>

              <label className="flex min-w-[16rem] flex-1 flex-col gap-1 text-[12px] text-ink-muted">
                What was checked
                <input
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="protein floor re-checked against ICMR 2020"
                  className="rounded-full bg-raised px-4 py-1.5 text-[13px] text-ink outline-none placeholder:text-ink-muted"
                />
              </label>

              <button
                onClick={() => {
                  setCodeError(null);
                  setAsking(true);
                }}
                disabled={!ready || asking}
                className="rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
              >
                Activate
              </button>
            </div>

            <p className="text-[12px] text-ink-muted">
              The reviewer has to be somebody other than you, and an admin. The database enforces
              both — the numbers in a pack are what the safety floors are made of.
            </p>

            {asking && (
              <TotpPrompt
                action={`Activating pack ${version}`}
                busy={busy}
                error={codeError}
                onSubmit={(code) => void activate(code)}
                onCancel={() => setAsking(false)}
              />
            )}

            {done && (
              <p role="status" className="text-[12.5px] text-ink">
                {done}
              </p>
            )}
          </div>

          <div className="card min-h-0 p-2">
            {state.history.length === 0 ? (
              <p className="px-3 py-6 text-center text-[13px] text-ink-muted">
                Nothing has been activated yet — the server is serving what its environment names.
              </p>
            ) : (
              <table className="w-full border-collapse text-[13px]">
                <thead>
                  <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
                    <th className="px-3 py-2 font-medium">Version</th>
                    <th className="px-3 py-2 font-medium">When</th>
                    <th className="px-3 py-2 font-medium">Activated by</th>
                    <th className="px-3 py-2 font-medium">Reviewed by</th>
                    <th className="px-3 py-2 font-medium">Note</th>
                  </tr>
                </thead>
                <tbody>
                  {state.history.map((row, i) => (
                    <tr key={`${row.version}-${row.created_at}-${i}`} className="border-t border-line">
                      <td className="px-3 py-2 font-mono text-ink">{row.version}</td>
                      <td className="px-3 py-2 text-ink-muted">{when(row.created_at)}</td>
                      <td className="px-3 py-2 text-ink-muted">#{row.activated_by_user_id}</td>
                      <td className="px-3 py-2 text-ink-muted">#{row.reviewed_by_user_id}</td>
                      <td className="px-3 py-2 text-ink-muted">{row.note ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}
    </div>
  );
}
