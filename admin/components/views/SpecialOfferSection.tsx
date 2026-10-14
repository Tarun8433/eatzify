'use client';

import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { call, errorText } from '@/lib/client';
import { inr, stamp } from '@/lib/format';
import {
  DEFAULT_EXPIRY_DAYS,
  MAX_EXPIRY_DAYS,
  catalogueKey,
  catalogueLabel,
  expiryDays,
  rupeesToPaise,
  whatsappLink,
  type PersonalOffer,
  type PlayCatalogueOffer,
} from '@/lib/offer-form';
import { Button, ErrorNote, Pill, inputClass } from '../ui';

const TIERS = ['BASIC', 'PRO'] as const;
const DURATIONS = ['1M', '3M', '6M', '12M'] as const;
const NOTE_MAX = 200;

const STATUS_LABEL: Record<PersonalOffer['status'], string> = {
  active: 'Active',
  used: 'Used',
  expired: 'Expired',
  revoked: 'Revoked',
};

/// D-265: a special price for this one person, sent as a link. Play offers come from the live Play
/// catalogue (Play charges its own price); Cashfree offers take any amount up to the plan's normal
/// price, which the API checks again.
export function SpecialOfferSection({ userId }: { userId: number }) {
  const [offers, setOffers] = useState<PersonalOffer[]>([]);
  const [catalog, setCatalog] = useState<PlayCatalogueOffer[] | null>(null);
  const [channel, setChannel] = useState<'play' | 'cashfree'>('play');
  const [playKey, setPlayKey] = useState('');
  const [tier, setTier] = useState<(typeof TIERS)[number]>('PRO');
  const [duration, setDuration] = useState<(typeof DURATIONS)[number]>('3M');
  const [rupees, setRupees] = useState('');
  const [days, setDays] = useState(String(DEFAULT_EXPIRY_DAYS));
  const [note, setNote] = useState('');
  const [created, setCreated] = useState<PersonalOffer | null>(null);
  const [copied, setCopied] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setOffers(await call<PersonalOffer[]>(`offers?user_id=${userId}`));
    } catch (e) {
      setError(errorText(e, 'Could not load this user’s offers.'));
    }
  }, [userId]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (channel !== 'play' || catalog) return;
    call<PlayCatalogueOffer[]>('offers/play-catalog')
      .then(setCatalog)
      .catch((e) => {
        setCatalog([]);
        setError(errorText(e, 'Could not read the Google Play catalogue.'));
      });
  }, [channel, catalog]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    const expires = expiryDays(days);
    if (expires === null) return setError(`Expiry must be 1 to ${MAX_EXPIRY_DAYS} days.`);

    const common = { user_id: userId, expires_in_days: expires, note: note.trim() || undefined };
    let body: Record<string, unknown>;
    if (channel === 'play') {
      const pick = catalog?.find((o) => catalogueKey(o) === playKey);
      if (!pick) return setError('Pick a Google Play offer from the list.');
      body = {
        ...common,
        channel,
        tier: pick.tier,
        duration: pick.duration,
        play_product_id: pick.product_id,
        play_base_plan_id: pick.base_plan_id,
        play_offer_id: pick.offer_id,
      };
    } else {
      const paise = rupeesToPaise(rupees);
      if (paise === null) return setError('Enter the amount in rupees, for example 999.');
      body = { ...common, channel, tier, duration, amount_paise: paise };
    }

    setBusy(true);
    try {
      setCreated(await call<PersonalOffer>('offers', { method: 'POST', body }));
      setCopied(false);
      setRupees('');
      setNote('');
      await load();
    } catch (err) {
      setError(errorText(err, 'Could not create the offer.'));
    } finally {
      setBusy(false);
    }
  };

  const revoke = async (id: string) => {
    try {
      await call(`offers/${id}/revoke`, { method: 'POST' });
      await load();
    } catch (e) {
      setError(errorText(e, 'Could not revoke the offer.'));
    }
  };

  const copy = async (link: string) => {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
    } catch {
      setError('Could not copy — select the link and copy it by hand.');
    }
  };

  return (
    <section className="card space-y-3 p-4">
      <h3 className="text-[13px] font-medium text-ink">Special offer</h3>
      <ErrorNote message={error} />

      <form onSubmit={submit} className="space-y-3">
        <div className="flex gap-2" role="group" aria-label="Payment channel">
          <Pill active={channel === 'play'} onClick={() => setChannel('play')}>
            Google Play
          </Pill>
          <Pill active={channel === 'cashfree'} onClick={() => setChannel('cashfree')}>
            Cashfree
          </Pill>
        </div>

        {channel === 'play' ? (
          <label className="flex flex-col gap-1 text-[12.5px] text-ink-muted">
            Play offer (configured in Play Console on an auto-renewing base plan)
            <select className={inputClass} value={playKey} onChange={(e) => setPlayKey(e.target.value)}>
              <option value="">{catalog === null ? 'Loading…' : catalog.length ? 'Choose an offer' : 'No active Play offers'}</option>
              {catalog?.map((o) => (
                <option key={catalogueKey(o)} value={catalogueKey(o)}>
                  {catalogueLabel(o)}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <>
            <p className="rounded-tile bg-raised px-3 py-2 text-[12.5px] text-ink">
              On Android, a Cashfree offer can only be paid once Google Play User Choice Billing is
              enabled. Until then the app refuses it — use a Google Play offer instead.
            </p>
            <div className="flex flex-wrap gap-2">
              <label className="flex flex-col gap-1 text-[12.5px] text-ink-muted">
                Plan
                <select className={inputClass} value={tier} onChange={(e) => setTier(e.target.value as typeof tier)}>
                  {TIERS.map((t) => (
                    <option key={t} value={t}>
                      {t === 'PRO' ? 'Pro' : 'Basic'}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-[12.5px] text-ink-muted">
                Length
                <select
                  className={inputClass}
                  value={duration}
                  onChange={(e) => setDuration(e.target.value as typeof duration)}
                >
                  {DURATIONS.map((d) => (
                    <option key={d} value={d}>
                      {d}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-[12.5px] text-ink-muted">
                Price (₹)
                <input
                  className={inputClass}
                  inputMode="decimal"
                  placeholder="999"
                  value={rupees}
                  onChange={(e) => setRupees(e.target.value)}
                />
              </label>
            </div>
          </>
        )}

        <div className="flex flex-wrap gap-2">
          <label className="flex flex-col gap-1 text-[12.5px] text-ink-muted">
            Expires in (days, 1–{MAX_EXPIRY_DAYS})
            <input
              className={inputClass}
              type="number"
              min={1}
              max={MAX_EXPIRY_DAYS}
              value={days}
              onChange={(e) => setDays(e.target.value)}
            />
          </label>
          <label className="flex flex-1 flex-col gap-1 text-[12.5px] text-ink-muted">
            Note (only staff see it, optional)
            <input
              className={inputClass}
              maxLength={NOTE_MAX}
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </label>
        </div>
        <Button type="submit" tone="primary" disabled={busy}>
          {busy ? 'Creating…' : 'Create offer link'}
        </Button>
      </form>

      {created && (
        <div className="space-y-2 rounded-tile bg-raised px-3 py-3 text-[13px]">
          <p className="text-ink">Send this link to the person. It works only on their account.</p>
          <p className="break-all font-mono text-[12px] text-ink">{created.link}</p>
          <div className="flex gap-2">
            <Button onClick={() => void copy(created.link)}>{copied ? 'Copied' : 'Copy link'}</Button>
            <a
              className="rounded-full bg-surface px-4 py-1.5 text-[12.5px] font-medium text-ink hover:bg-raised"
              href={whatsappLink(created.link)}
              target="_blank"
              rel="noopener noreferrer"
            >
              Share on WhatsApp
            </a>
          </div>
        </div>
      )}

      {offers.length === 0 ? (
        <p className="text-[13px] text-ink-muted">No special offers for this user.</p>
      ) : (
        <table className="w-full border-collapse text-[13px]">
          <thead>
            <tr className="text-left text-[11.5px] uppercase tracking-wide text-ink-muted">
              {['Offer', 'Price', 'Status', 'Expires', 'Note', ''].map((h) => (
                <th key={h} className="px-2 py-1.5 font-medium">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {offers.map((o) => (
              <tr key={o.id} className="border-t border-line">
                <td className="px-2 py-1.5 text-ink">
                  {o.tier} {o.duration} · {o.channel === 'play' ? 'Play' : 'Cashfree'}
                </td>
                <td className="px-2 py-1.5 text-ink-muted">
                  {o.amount_paise !== null ? inr(o.amount_paise) : (o.play_offer_id ?? '—')}
                </td>
                <td className="px-2 py-1.5 text-ink-muted">{STATUS_LABEL[o.status]}</td>
                <td className="px-2 py-1.5 text-ink-muted">{stamp(o.expires_at)}</td>
                <td className="px-2 py-1.5 text-ink-muted">{o.note ?? '—'}</td>
                <td className="px-2 py-1.5 text-right">
                  {o.status === 'active' && (
                    <Button tone="danger" onClick={() => void revoke(o.id)}>
                      Revoke
                    </Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
