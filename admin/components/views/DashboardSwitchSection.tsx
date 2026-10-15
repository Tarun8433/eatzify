'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import {
  CHOICE_LABEL,
  choiceOf,
  switchSummary,
  type OverrideChoice,
  type UserDashboardSwitch,
} from '@/lib/dashboard-switch';
import { ErrorNote, Pill } from '../ui';

const CHOICES: OverrideChoice[] = ['follow', 'allow', 'deny'];

/// D-269: whether this person may switch between "My tracking" and "My clients" in the app. The
/// app picks a change up the next time it starts or the person opens their You tab.
export function DashboardSwitchSection({ userId, canEdit }: { userId: number; canEdit: boolean }) {
  const [view, setView] = useState<UserDashboardSwitch | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setView(await call<UserDashboardSwitch>(`users/${userId}/dashboard-switch`));
    } catch (e) {
      setError(errorText(e, 'Could not load the dashboard switch.'));
    }
  }, [userId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function choose(choice: OverrideChoice) {
    setBusy(true);
    setError(null);
    try {
      setView(
        await call<UserDashboardSwitch>(
          `users/${userId}/dashboard-switch`,
          choice === 'follow'
            ? { method: 'DELETE' }
            : { method: 'PUT', body: { allowed: choice === 'allow' } },
        ),
      );
    } catch (e) {
      setError(errorText(e, 'The API refused.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card p-4">
      <h3 className="mb-2 text-[13px] font-medium text-ink">Dashboard switch</h3>
      {view && <p className="mb-3 text-[12.5px] text-ink-muted">{switchSummary(view)}</p>}
      {view && canEdit && (
        <div className="flex flex-wrap gap-2" aria-disabled={busy}>
          {CHOICES.map((choice) => (
            <Pill
              key={choice}
              active={choiceOf(view.override) === choice}
              onClick={() => {
                if (!busy && choiceOf(view.override) !== choice) void choose(choice);
              }}
            >
              {CHOICE_LABEL[choice]}
            </Pill>
          ))}
        </div>
      )}
      <ErrorNote message={error} />
    </section>
  );
}
