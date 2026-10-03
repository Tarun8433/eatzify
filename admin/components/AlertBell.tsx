'use client';

import { useState } from 'react';
import type { NavKey } from '@/lib/nav';
import { BellIcon } from './icons';

export type Alert = { kind: string; count: number; nav: string };

const ALERT_LABEL: Record<string, string> = {
  coach_applications: 'Coach applications waiting',
  refund_requests: 'Refund requests waiting',
  tickets_waiting: 'Support tickets waiting on us',
  emails_unconfirmed_24h: 'Emails unconfirmed for over a day',
  failed_payments_last_hour: 'Failed payments in the last hour',
};

/// The bell (admin panel plan, Phase C): what is waiting on this person's role, counted live by
/// `GET /admin/alerts`. Each line opens the screen that deals with it.
export function AlertBell({ alerts, onGo }: { alerts: Alert[]; onGo: (nav: NavKey) => void }) {
  const [open, setOpen] = useState(false);
  const total = alerts.reduce((n, a) => n + a.count, 0);

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label={total ? `Notifications: ${total} waiting` : 'Notifications'}
        aria-expanded={open}
        className="relative flex h-[42px] w-[42px] items-center justify-center rounded-full bg-raised text-ink transition-colors hover:bg-line"
      >
        <BellIcon className="h-[18px] w-[18px]" />
        {total > 0 && (
          <span className="absolute -right-0.5 -top-0.5 min-w-[18px] rounded-full bg-mint px-1 text-center text-[11px] font-semibold leading-[18px] text-mint-ink">
            {total > 99 ? '99+' : total}
          </span>
        )}
      </button>
      {open && (
        <div className="card absolute right-0 top-[50px] z-40 w-[300px] p-2">
          {alerts.length === 0 ? (
            <p className="px-3 py-3 text-[13px] text-ink-muted">Nothing waiting.</p>
          ) : (
            alerts.map((a) => (
              <button
                key={a.kind}
                type="button"
                onClick={() => {
                  setOpen(false);
                  onGo(a.nav as NavKey);
                }}
                className="flex w-full items-center justify-between rounded-tile px-3 py-2 text-left text-[13px] text-ink hover:bg-raised"
              >
                <span>{ALERT_LABEL[a.kind] ?? a.kind}</span>
                <span className="font-semibold">{a.count}</span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
