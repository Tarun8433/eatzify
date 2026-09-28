'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

/**
 * The way in (D-234).
 *
 * The same account that signs in to the API — this dashboard has no users of its own, and one more
 * password to keep would be one more password to leak. docs/10 §1 lets `admin` and `super_admin`
 * through; anybody else is told so here rather than shown a dashboard where every panel 403s.
 */
export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    try {
      const res = await fetch('/api/session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      if (!res.ok) {
        const data = (await res.json().catch(() => ({}))) as { error?: string };
        throw new Error(data.error ?? 'Could not sign in.');
      }

      // `refresh` as well as `push`: the shell is a server component and has to be re-rendered
      // with the cookie in place, or it paints the signed-out redirect again.
      router.push('/');
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not sign in.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex h-screen w-full items-center justify-center bg-shell px-5">
      <form onSubmit={submit} className="card flex w-full max-w-[24rem] flex-col gap-4 p-6">
        <div>
          <h1 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">Eatzify admin</h1>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Sign in with your Eatzify account.
          </p>
        </div>

        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Email
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username"
            required
            className="rounded-full bg-raised px-4 py-2 text-[13px] text-ink outline-none"
          />
        </label>

        <label className="flex flex-col gap-1 text-[12px] text-ink-muted">
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
            className="rounded-full bg-raised px-4 py-2 text-[13px] text-ink outline-none"
          />
        </label>

        <button
          type="submit"
          disabled={busy}
          className="rounded-full bg-mint px-4 py-2 text-[13px] font-medium text-mint-ink disabled:opacity-40"
        >
          {busy ? 'Signing in…' : 'Sign in'}
        </button>

        {error && <p className="text-[12.5px] text-[#ffb4b4]">{error}</p>}
      </form>
    </main>
  );
}
