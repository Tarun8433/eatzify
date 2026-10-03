'use client';

import { useCallback, useEffect, useState } from 'react';
import { call, errorText } from '@/lib/client';
import { inr, stamp } from '@/lib/format';
import { Button, ConfirmDialog, ErrorNote, Loadable, ViewHeader, type ConfirmField } from '../ui';

type Offer = {
  code: string;
  percent_off: number;
  max_uses: number;
  used_count: number;
  expires_at: string | null;
  active: boolean;
  title: string | null;
  description: string | null;
  banner_url: string | null;
  starts_at: string | null;
  eligibility: 'all' | 'new_users';
  tier: 'BASIC' | 'PRO' | null;
};
type Stats = { code: string; paid_orders: number; revenue_paise: string; discount_paise: string };

const SHARED_FIELDS: ConfirmField[] = [
  { kind: 'text', name: 'title', label: 'Title (shown on the offer card)', optional: true },
  { kind: 'text', name: 'description', label: 'Description', optional: true },
  { kind: 'text', name: 'banner_url', label: 'Banner image link', optional: true },
  {
    kind: 'select',
    name: 'eligibility',
    label: 'Who may use it',
    options: [
      { value: 'all', label: 'Anyone' },
      { value: 'new_users', label: 'Only people who have never paid' },
    ],
  },
  {
    kind: 'select',
    name: 'tier',
    label: 'Plans',
    options: [
      { value: '', label: 'Any plan' },
      { value: 'BASIC', label: 'Basic only' },
      { value: 'PRO', label: 'Pro only' },
    ],
  },
  { kind: 'text', name: 'starts_at', label: 'Starts (YYYY-MM-DD, empty: now)', optional: true },
  { kind: 'text', name: 'expires_at', label: 'Ends (YYYY-MM-DD, empty: no end)', optional: true },
  { kind: 'text', name: 'max_uses', label: 'Usage limit' },
];

function day(v: string): string | null {
  return v.trim() ? new Date(`${v.trim()}T00:00:00+05:30`).toISOString() : null;
}

/// The edit form opens on the offer as it is, so saving changes only what was changed.
function withCurrent(o: Offer): ConfirmField[] {
  const current: Record<string, string> = {
    title: o.title ?? '',
    description: o.description ?? '',
    banner_url: o.banner_url ?? '',
    eligibility: o.eligibility,
    tier: o.tier ?? '',
    starts_at: o.starts_at?.slice(0, 10) ?? '',
    expires_at: o.expires_at?.slice(0, 10) ?? '',
    max_uses: String(o.max_uses),
  };
  return SHARED_FIELDS.map((f) => ({ ...f, initial: current[f.name] }));
}

/// Admin panel plan, Phase C: offer codes with what they say, who may use them, and how they did.
/// Every change asks for the authenticator code and is audited.
export function OffersView() {
  const [offers, setOffers] = useState<Offer[]>([]);
  const [stats, setStats] = useState<Map<string, Stats>>(new Map());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<{ kind: 'new' | 'edit' | 'disable'; offer?: Offer } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [list, s] = await Promise.all([call<Offer[]>('coupons'), call<Stats[]>('coupons/stats')]);
      setOffers(list);
      setStats(new Map(s.map((x) => [x.code, x])));
    } catch (e) {
      setError(errorText(e, 'Could not load offers.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto pb-4">
      <ViewHeader title="Offers" subtitle="Codes people enter at checkout. Prices themselves are set under Tier price.">
        <Button tone="primary" onClick={() => setDialog({ kind: 'new' })}>New offer</Button>
      </ViewHeader>
      <ErrorNote message={error} />

      <Loadable loading={loading} empty={offers.length === 0} emptyText="No offers yet.">
        <section className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {offers.map((o) => {
            const s = stats.get(o.code);
            return (
              <article key={o.code} className={`card space-y-2 p-4 ${o.active ? '' : 'opacity-60'}`}>
                <div className="flex items-baseline justify-between gap-2">
                  <h3 className="text-[15px] font-semibold text-ink">{o.title || o.code}</h3>
                  <span className="font-mono text-[12px] text-ink-muted">{o.code}</span>
                </div>
                {o.description && <p className="text-[13px] text-ink-muted">{o.description}</p>}
                <p className="text-[13px] text-ink">
                  {o.percent_off}% off
                  {o.tier ? ` · ${o.tier} only` : ''}
                  {o.eligibility === 'new_users' ? ' · new users only' : ''}
                </p>
                <p className="text-[12px] text-ink-muted">
                  {o.starts_at ? stamp(o.starts_at) : 'Now'} → {o.expires_at ? stamp(o.expires_at) : 'no end'}
                  {' · '}
                  {o.active ? 'Active' : 'Disabled'}
                </p>
                <p className="text-[12px] text-ink-muted">
                  Used {o.used_count}/{o.max_uses} · {s?.paid_orders ?? 0} paid · {inr(s?.revenue_paise ?? 0)} revenue ·{' '}
                  {inr(s?.discount_paise ?? 0)} given
                </p>
                <div className="flex gap-2 pt-1">
                  <Button onClick={() => setDialog({ kind: 'edit', offer: o })}>Edit</Button>
                  {o.active && (
                    <Button tone="danger" onClick={() => setDialog({ kind: 'disable', offer: o })}>Disable</Button>
                  )}
                </div>
              </article>
            );
          })}
        </section>
      </Loadable>

      {dialog?.kind === 'new' && (
        <ConfirmDialog
          title="New offer"
          fields={[
            { kind: 'text', name: 'code', label: 'Code (3–24 letters, digits, - or _)' },
            { kind: 'text', name: 'percent_off', label: 'Percent off (1–90)' },
            ...SHARED_FIELDS,
          ]}
          totp
          confirmLabel="Create"
          onClose={() => setDialog(null)}
          onConfirm={async (v, totp) => {
            await call('coupons', {
              method: 'POST',
              totp,
              body: {
                code: v.code,
                percent_off: Number(v.percent_off),
                max_uses: Number(v.max_uses),
                expires_at: day(v.expires_at),
                starts_at: day(v.starts_at),
                title: v.title || null,
                description: v.description || null,
                banner_url: v.banner_url || null,
                eligibility: v.eligibility,
                tier: v.tier || null,
              },
            });
            await load();
          }}
        />
      )}
      {dialog?.kind === 'edit' && dialog.offer && (
        <ConfirmDialog
          title={`Edit ${dialog.offer.code}`}
          body="The code and the percentage stay as they are: changing them would rewrite what people were sold."
          fields={withCurrent(dialog.offer)}
          totp
          confirmLabel="Save"
          onClose={() => setDialog(null)}
          onConfirm={async (v, totp) => {
            await call(`coupons/${dialog.offer!.code}`, {
              method: 'PATCH',
              totp,
              body: {
                title: v.title || null,
                description: v.description || null,
                banner_url: v.banner_url || null,
                eligibility: v.eligibility,
                tier: v.tier || null,
                starts_at: day(v.starts_at),
                expires_at: day(v.expires_at),
                ...(v.max_uses ? { max_uses: Number(v.max_uses) } : {}),
              },
            });
            await load();
          }}
        />
      )}
      {dialog?.kind === 'disable' && dialog.offer && (
        <ConfirmDialog
          title={`Disable ${dialog.offer.code}`}
          body="Nobody can use it from now on. It stays listed with its usage."
          totp
          tone="danger"
          confirmLabel="Disable"
          onClose={() => setDialog(null)}
          onConfirm={async (_v, totp) => {
            await call(`coupons/${dialog.offer!.code}/deactivate`, { method: 'POST', totp });
            await load();
          }}
        />
      )}
    </div>
  );
}
