'use client';

import { useCallback, useEffect, useState } from 'react';
import { SpinnerIcon } from '../icons';

interface Enrolment {
  secret: string;
  otpauth_uri: string;
}

/**
 * The authenticator this account uses to authorise dangerous actions (D-229).
 *
 * Not a login factor — nothing here is asked for on the way in. It gates the two actions that are
 * worth a pause: activating a rule pack, and revealing somebody's full identity. A code demanded
 * thirty times a day is a code typed without reading it.
 *
 * ⚠ The dashboard signs in as ONE service account, so this is that account's authenticator rather
 * than each admin's own. Fine while the team fits in a room; per-admin sign-in is the upgrade.
 */
export function SecurityView() {
  const [enrolled, setEnrolled] = useState<boolean | null>(null);
  const [enrolment, setEnrolment] = useState<Enrolment | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await fetch('/api/totp');
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not read the security status.');
      setEnrolled(Boolean(data.enrolled));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not read the security status.');
      setEnrolled(null);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function start() {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/totp/enroll', { method: 'POST' });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not start the setup.');
      setEnrolment(data as Enrolment);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not start the setup.');
    } finally {
      setBusy(false);
    }
  }

  async function confirm() {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/totp/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? 'That code was not accepted.');
      }
      setEnrolment(null);
      setCode('');
      setDone(true);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'That code was not accepted.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header>
        <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Security</h2>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">
          An authenticator app, for the two actions worth a pause: activating a rule pack, and
          revealing an applicant&rsquo;s full identity.
        </p>
      </header>

      <div className="card min-h-0 flex-1 overflow-auto p-5">
        {enrolled === null && !error ? (
          <p className="flex items-center gap-2 text-[13px] text-ink-muted">
            <SpinnerIcon className="h-4 w-4 animate-spin" /> Checking…
          </p>
        ) : enrolled ? (
          <div className="flex flex-col gap-2">
            <p className="text-[14px] text-ink">
              {done ? 'Authenticator confirmed.' : 'An authenticator is set up for this account.'}
            </p>
            <p className="max-w-[46rem] text-[12.5px] text-ink-muted">
              Lost the phone? There is deliberately no self-service reset — another super admin has
              to clear the row. A second factor you can reset by yourself is not one.
            </p>
          </div>
        ) : enrolment ? (
          <div className="flex max-w-[44rem] flex-col gap-3">
            <p className="text-[13px] text-ink">
              Add this to your authenticator app, then type the code it shows.
            </p>

            {/* No QR code: that would need a library, and a pasted secret works in every app. */}
            <dl className="flex flex-col gap-2 rounded-tile bg-raised p-3 text-[12.5px]">
              <div>
                <dt className="text-ink-muted">Secret</dt>
                <dd className="mt-0.5 break-all font-mono text-[13px] text-ink">
                  {enrolment.secret}
                </dd>
              </div>
              <div>
                <dt className="text-ink-muted">Or paste this URI</dt>
                <dd className="mt-0.5 break-all font-mono text-[11.5px] text-ink-muted">
                  {enrolment.otpauth_uri}
                </dd>
              </div>
            </dl>

            <p className="text-[12.5px] text-ink-muted">
              This is the only time the secret is shown.
            </p>

            <div className="flex items-center gap-2">
              <input
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="000000"
                aria-label="Code from your authenticator app"
                className="w-[7.5rem] rounded-full bg-surface px-4 py-1.5 text-[13px] tracking-[0.3em] text-ink outline-none placeholder:text-ink-muted"
              />
              <button
                onClick={() => void confirm()}
                disabled={!/^\d{6}$/.test(code) || busy}
                className="flex items-center gap-1.5 rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
              >
                {busy && <SpinnerIcon className="h-3.5 w-3.5 animate-spin" />}
                Confirm
              </button>
            </div>
          </div>
        ) : (
          <div className="flex max-w-[44rem] flex-col items-start gap-3">
            <p className="text-[14px] text-ink">No authenticator is set up.</p>
            <p className="text-[12.5px] text-ink-muted">
              Until one is, revealing an applicant&rsquo;s identity and activating a rule pack will
              both be refused.
            </p>
            <button
              onClick={() => void start()}
              disabled={busy}
              className="flex items-center gap-1.5 rounded-full bg-mint px-4 py-1.5 text-[12.5px] font-medium text-mint-ink disabled:opacity-40"
            >
              {busy && <SpinnerIcon className="h-3.5 w-3.5 animate-spin" />}
              Set one up
            </button>
          </div>
        )}

        {error && <p className="mt-3 text-[12.5px] text-[#ffb4b4]">{error}</p>}
      </div>
    </div>
  );
}
