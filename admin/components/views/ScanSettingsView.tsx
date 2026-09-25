'use client';

import { useCallback, useEffect, useState } from 'react';
import { TotpPrompt } from '../TotpPrompt';
import { SpinnerIcon } from '../icons';

interface Policy {
  tier: 'FREE' | 'BASIC' | 'PRO';
  enabled: boolean;
  daily_limit: number;
  requires_ad: boolean;
  trial_days: number | null;
  updated_at: string;
}

/**
 * Who may scan a meal photo (D-238): per tier, on or off, how many a day, whether a rewarded ad comes
 * first, and — for a tier with a window — how many days after signup it lasts.
 *
 * Each scan is a paid call to the vision model, so a change here is a change in cost; saving asks for
 * the authenticator like an offer does.
 */
export function ScanSettingsView() {
  const [rows, setRows] = useState<Policy[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await fetch('/api/scan-policy');
      const body = await res.json();
      if (!res.ok) throw new Error(body?.error?.user_message ?? body?.error ?? 'Could not load.');
      setRows(body as Policy[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the scan settings.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex flex-col gap-3 overflow-y-auto">
      <div>
        <h3 className="text-[15px] font-semibold text-ink">Meal scanning</h3>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          Who can photograph a meal to log it. A daily limit counts from 04:00 IST. A trial window
          counts from the day the account was made; leave it empty for no window.
        </p>
      </div>
      {error && <p className="text-[12.5px] text-[#ffb4b4]">{error}</p>}
      {rows === null && !error && <SpinnerIcon className="h-5 w-5 animate-spin text-ink-muted" />}
      {rows?.map((row) => <TierCard key={row.tier} policy={row} onSaved={load} />)}
    </div>
  );
}

function TierCard({ policy, onSaved }: { policy: Policy; onSaved: () => Promise<void> }) {
  const [enabled, setEnabled] = useState(policy.enabled);
  const [limit, setLimit] = useState(String(policy.daily_limit));
  const [ad, setAd] = useState(policy.requires_ad);
  const [trial, setTrial] = useState(policy.trial_days === null ? '' : String(policy.trial_days));
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const limitOk = /^\d+$/.test(limit) && Number(limit) <= 100;
  const trialOk = trial === '' || (/^\d+$/.test(trial) && Number(trial) >= 1 && Number(trial) <= 365);

  async function save(totp: string) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/scan-policy', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', 'x-totp': totp },
        body: JSON.stringify({
          tier: policy.tier,
          enabled,
          daily_limit: Number(limit),
          requires_ad: ad,
          trial_days: trial === '' ? null : Number(trial),
        }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body?.error?.user_message ?? body?.error ?? 'The API refused.');
      setAsking(false);
      setDone(true);
      await onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The API refused.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card flex flex-col gap-3 p-4">
      <div className="flex items-center justify-between">
        <h4 className="text-[13px] font-semibold text-ink">{policy.tier}</h4>
        <span className="text-[11.5px] text-ink-muted">
          Last changed {new Date(policy.updated_at).toLocaleString()}
        </span>
      </div>

      <div className="flex flex-wrap items-end gap-4">
        <label className="flex items-center gap-2 text-[12.5px] text-ink">
          <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
          Scanning on
        </label>
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Scans a day
          <input
            value={limit}
            onChange={(e) => setLimit(e.target.value)}
            inputMode="numeric"
            className="w-20 rounded-lg border border-edge bg-raised px-2 py-1.5 text-[13px] text-ink"
          />
        </label>
        <label className="flex items-center gap-2 text-[12.5px] text-ink">
          <input type="checkbox" checked={ad} onChange={(e) => setAd(e.target.checked)} />
          Rewarded ad before each scan
        </label>
        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Days after signup
          <input
            value={trial}
            onChange={(e) => setTrial(e.target.value)}
            inputMode="numeric"
            placeholder="no window"
            className="w-24 rounded-lg border border-edge bg-raised px-2 py-1.5 text-[13px] text-ink"
          />
        </label>
        <button
          type="button"
          disabled={!limitOk || !trialOk || busy}
          onClick={() => {
            setDone(false);
            setAsking(true);
          }}
          className="rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
        >
          Save
        </button>
      </div>

      {!limitOk && <p className="text-[12px] text-[#ffb4b4]">Scans a day: a whole number, 0 to 100.</p>}
      {!trialOk && <p className="text-[12px] text-[#ffb4b4]">Days after signup: 1 to 365, or empty.</p>}
      {asking && (
        <TotpPrompt
          action={`Changing ${policy.tier} scanning`}
          busy={busy}
          error={error}
          onSubmit={(code) => void save(code)}
          onCancel={() => setAsking(false)}
        />
      )}
      {!asking && error && <p className="text-[12px] text-[#ffb4b4]">{error}</p>}
      {done && <p className="text-[12px] text-ink-muted">Saved. The app sees it on the next scan.</p>}
    </div>
  );
}
