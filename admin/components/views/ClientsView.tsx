'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { hms, ringDash } from '@/lib/format';
import {
  ChevronLeftIcon,
  ChevronRightIcon,
  CopyIcon,
  PhoneIcon,
  RefreshIcon,
  SaveContactIcon,
  SpinnerIcon,
  WhatsAppIcon,
} from '../icons';
import { buildVCard, downloadVCard } from '@/lib/vcard';
import { StatTile } from '../StatTile';
import { PremiumCard } from '../PremiumCard';

export interface ClientSummary {
  user_id: number;
  name: string;
  goal: string;
  goal_declared: string | null;
  food_preference: string;
  tier: string;
  days_on_plan: number;
  weight_kg: number;
  goal_weight_kg: number | null;
  last_logged_date: string | null;
  phone_masked: string | null;
}

export interface RegistrationAnswers {
  sex_at_birth: string;
  goal_weight_kg: number | null;
  goal_declared: string | null;
  meal_count: string;
  lifestyle: string;
  budget_tier: string;
  budget_monthly_inr: number | null;
  food_dislikes: string | null;
  wake_time: string | null;
  sleep_time: string | null;
  sleep_hours: number | null;
  meal_times: {
    breakfast: string | null;
    mid_morning: string | null;
    lunch: string | null;
    evening_snack: string | null;
    dinner: string | null;
    bedtime_snack: string | null;
  };
  conditions: string[];
  allergies: string[];
  digestive_symptoms: string[];
  injuries: string[];
  medications: string | null;
  menstrual_regularity: string | null;
  pregnant_or_breastfeeding: boolean | null;
  heavy_bleeding_or_pain: boolean | null;
  hormonal_medication: boolean | null;
  screened_special_diet: boolean | null;
  screened_insulin_or_kidney: boolean | null;
  health_profile_version: number | null;
  gates: Record<string, unknown> | null;
  consents: { type: string; granted: boolean; policy_version: string; granted_at: string }[];
}

export interface ClientDetail extends ClientSummary {
  age_years: number;
  height_cm: number;
  activity: string;
  phone: string | null;
  email: string | null;
  auth_provider: string | null;
  registration: RegistrationAnswers;
  targets: Record<string, number> | null;
  today: { kcal: number; proteinG: number; carbG: number; fatG: number; entries: number };
  adherence: { days_logged: number; window_days: number; pct: number; streak: number };
  logging_grid: { slots: string[]; days: string[]; cells: number[][] };
  top_foods: { name: string; entries: number; kcal: number; pct: number }[];
  weight_series: { date: string; kg: number }[];
  recent_meals: { date: string; slot: string; name: string; kcal: number }[];
}

/// Never a raw enum on screen — root CLAUDE.md rule 4. These are the display strings for every
/// vocabulary value the roster can contain.
const GOAL_LABEL: Record<string, string> = {
  fat_loss: 'Fat loss',
  muscle_gain: 'Muscle gain',
  maintenance: 'Maintenance',
};
const PREF_LABEL: Record<string, string> = {
  veg: 'Vegetarian',
  non_veg: 'Non-vegetarian',
  eggetarian: 'Eggetarian',
  jain: 'Jain',
  vegan: 'Vegan',
};
const SLOT_LABEL: Record<string, string> = {
  breakfast: 'Breakfast',
  mid_morning: 'Mid-morning',
  lunch: 'Lunch',
  snack: 'Snack',
  evening: 'Evening',
  dinner: 'Dinner',
  bedtime: 'Bedtime',
};

/// docs/10 §4's closed list. Picked before a diary opens, and sent with the request so the audit row
/// says why rather than saying `support_ticket` every time.
const REASONS = [
  { key: 'support_ticket', label: 'Support ticket' },
  { key: 'fraud_review', label: 'Fraud review' },
  { key: 'data_subject_request', label: 'Data request' },
  { key: 'safety_review', label: 'Safety review' },
];

const BUCKET_CLASS = ['cell-empty', 'bg-[#4a4a4a]', 'bg-[#8f9a97]', 'bg-mint-bright'];

function initials(name: string): string {
  return name
    .replace(/^\[demo\]\s*/, '')
    .split(' ')
    .map((p) => p[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
}

function displayName(name: string): string {
  return name.replace(/^\[demo\]\s*/, '');
}

export function ClientsView() {
  const [clients, setClients] = useState<ClientSummary[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<ClientDetail | null>(null);
  const [reason, setReason] = useState(REASONS[0].key);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<'diary' | 'registration'>('diary');

  useEffect(() => {
    void (async () => {
      try {
        const res = await fetch('/api/clients');
        const data = await res.json();
        if (!res.ok) throw new Error(data.error ?? 'Could not load clients.');
        // Only clients with a diary can fill this screen, and the fullest record first — opening
        // on a near-empty diary makes a working dashboard look broken. "Has a diary" means any
        // log at all — days_on_plan is TENURE (whole days since the first log), so filtering on
        // it hid every client on their first day, when a log from today is the freshest diary
        // there is.
        const withData = (data as ClientSummary[])
          .filter((c) => c.last_logged_date !== null)
          // Most recently active first. Sorting on `days_on_plan` opened the oldest account, whose
          // last seven days were empty — a full-looking dashboard with a blank diary in the middle.
          .sort((a, b) => (b.last_logged_date ?? '').localeCompare(a.last_logged_date ?? ''));
        setClients(withData);
        setSelectedId(withData[0]?.user_id ?? null);
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Could not load clients.');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const loadDetail = useCallback(async () => {
    if (selectedId === null) return;
    setDetail(null);
    try {
      const res = await fetch(`/api/clients/${selectedId}?reason=${reason}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not open the record.');
      setDetail(data as ClientDetail);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not open the record.');
    }
  }, [selectedId, reason]);

  useEffect(() => {
    void loadDetail();
  }, [loadDetail]);

  const macroRings = useMemo(() => {
    if (!detail?.targets) return [];
    const t = detail.targets;
    return [
      { label: 'Protein', pct: pctOf(detail.today.proteinG, t.proteinG), r: 62, color: '#ffffff' },
      { label: 'Carbs', pct: pctOf(detail.today.carbG, t.carbG), r: 50, color: '#7fd7e3' },
      { label: 'Fat', pct: pctOf(detail.today.fatG, t.fatG), r: 38, color: '#4aa8c4' },
    ];
  }, [detail]);

  if (loading) {
    return (
      <Centered>
        <SpinnerIcon className="h-5 w-5 animate-spin" />
        <span>Loading clients…</span>
      </Centered>
    );
  }

  if (clients.length === 0) {
    return (
      <Centered>
        <span className="text-ink">No clients with a diary yet.</span>
        <span>
          Seed some:{' '}
          <code className="rounded bg-raised px-1.5 py-0.5">
            npx env-cmd -- npx ts-node scripts/seed-demo-clients.ts
          </code>
        </span>
      </Centered>
    );
  }

  return (
    <>
      {/* The roster rail — the reference's team carousel, carrying clients instead of colleagues. */}
      <div className="flex shrink-0 items-center justify-between gap-6 py-4">
        <div>
          <h1 className="text-[21px] font-semibold leading-tight tracking-[-0.01em] text-ink">
            Eatzify <span className="text-ink-muted">·</span> Clients
          </h1>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            {clients.length} with an active diary
          </p>
        </div>

        <div className="flex min-w-0 items-center gap-2.5">
          <ChevronLeftIcon className="h-4 w-4 shrink-0 text-ink-faint" aria-hidden />
          <ul className="flex items-center gap-2 overflow-x-auto no-scrollbar">
            {clients.map((c) => {
              const isActive = c.user_id === selectedId;
              return (
                <li key={c.user_id}>
                  <button
                    type="button"
                    onClick={() => setSelectedId(c.user_id)}
                    aria-pressed={isActive}
                    title={`${displayName(c.name)} — ${GOAL_LABEL[c.goal] ?? c.goal}${
                      c.phone_masked ? ` · ${c.phone_masked}` : ''
                    }`}
                    className={`flex h-10 w-10 items-center justify-center rounded-full text-[12.5px] font-semibold transition-all ${
                      isActive
                        ? 'bg-mint text-mint-ink ring-2 ring-white ring-offset-[3px] ring-offset-shell'
                        : 'bg-raised text-ink-muted hover:text-ink'
                    }`}
                  >
                    {initials(c.name)}
                  </button>
                </li>
              );
            })}
          </ul>
          <ChevronRightIcon className="h-4 w-4 shrink-0 text-ink-faint" aria-hidden />
        </div>

        <div
          role="tablist"
          aria-label="Record section"
          className="flex shrink-0 items-center gap-1 rounded-full bg-surface p-1"
        >
          {(['diary', 'registration'] as const).map((t) => (
            <button
              key={t}
              role="tab"
              aria-selected={tab === t}
              onClick={() => setTab(t)}
              className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium transition-colors ${
                tab === t ? 'bg-mint text-mint-ink' : 'text-ink-muted hover:text-ink'
              }`}
            >
              {t === 'diary' ? 'Diary' : 'Registration'}
            </button>
          ))}
        </div>

        {/* Why this diary is being opened. Chosen before the read, sent with it, stored in the log. */}
        <div className="flex shrink-0 items-center gap-2">
          <label htmlFor="reason" className="text-[11.5px] text-ink-muted">
            Reason
          </label>
          <select
            id="reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="h-[38px] rounded-full bg-raised px-3 text-[12.5px] text-ink focus:outline-none focus:ring-1 focus:ring-mint"
          >
            {REASONS.map((r) => (
              <option key={r.key} value={r.key}>
                {r.label}
              </option>
            ))}
          </select>
          <button
            onClick={() => void loadDetail()}
            aria-label="Reload record"
            className="flex h-[38px] w-[38px] items-center justify-center rounded-full bg-raised text-ink-muted hover:text-ink"
          >
            <RefreshIcon className="h-4 w-4" />
          </button>
        </div>
      </div>

      {error && !detail ? (
        <Centered>
          <span className="text-[#ffb4b4]">{error}</span>
        </Centered>
      ) : !detail ? (
        <Centered>
          <SpinnerIcon className="h-5 w-5 animate-spin" />
          <span>Opening record…</span>
        </Centered>
      ) : (
        tab === 'registration' ? (
        <RegistrationPanel detail={detail} />
      ) : (
        <div className="grid min-h-0 flex-1 grid-cols-1 gap-3 overflow-y-auto pb-1 lg:auto-rows-fr lg:grid-cols-12 lg:overflow-hidden">
          {/* Left: who they are, and the figures that describe their journey. */}
          <div className="flex min-h-0 flex-col gap-3 overflow-y-auto no-scrollbar lg:col-span-3">
            <article className="card flex flex-col items-center p-5">
              <span className="flex h-[92px] w-[92px] items-center justify-center rounded-full bg-mint text-[30px] font-semibold text-mint-ink">
                {initials(detail.name)}
              </span>
              <h2 className="mt-3.5 text-[17px] font-semibold text-ink">
                {displayName(detail.name)}
              </h2>
              <p className="mt-0.5 text-[12px] text-ink-muted">
                {GOAL_LABEL[detail.goal] ?? detail.goal} ·{' '}
                {PREF_LABEL[detail.food_preference] ?? detail.food_preference}
              </p>
              <p className="mt-2.5 rounded-full bg-raised px-3 py-1 text-[11.5px] text-ink-muted">
                {detail.age_years} yrs · {detail.height_cm} cm · {detail.tier}
              </p>
            </article>

            <ContactCard detail={detail} />

            <div className="grid grid-cols-2 gap-3">
              <StatTile value={String(detail.days_on_plan)} label="Days on plan" />
              <StatTile value={String(detail.adherence.streak)} label="Logging streak" />
            </div>

            <div className="card px-5 py-[18px]">
              <p className="text-figure font-medium text-ink">
                {detail.weight_kg.toFixed(1)}
                <span className="ml-1 text-[18px] text-ink-muted">kg</span>
              </p>
              <p className="mt-1.5 text-[12px] text-ink-muted">
                {detail.goal_weight_kg
                  ? `Goal ${detail.goal_weight_kg.toFixed(1)} kg · ${Math.abs(
                      detail.weight_kg - detail.goal_weight_kg,
                    ).toFixed(1)} to go`
                  : 'Current weight'}
              </p>
              <WeightSpark series={detail.weight_series} />
            </div>

            <PremiumCard pricePerMonth="₹499/mo" />
          </div>

          {/* Middle: today's diary, and the week of meals under it. */}
          <div className="flex min-w-0 flex-col gap-3 lg:col-span-6">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <IntakeCard detail={detail} />

              <section className="card flex min-w-0 flex-col p-4">
                <h2 className="text-[14.5px] font-medium text-ink">Macros against target</h2>
                <div className="relative mx-auto my-1 flex h-[178px] w-[178px] items-center justify-center">
                  <svg viewBox="0 0 160 160" className="h-full w-full -rotate-90">
                    {macroRings.map(({ pct, r, color, label }) => {
                      const { dash, gap } = ringDash(pct, r);
                      return (
                        <g key={label}>
                          <circle cx="80" cy="80" r={r} fill="none" stroke="#2b2b2b" strokeWidth="9" />
                          <circle
                            cx="80" cy="80" r={r} fill="none" stroke={color} strokeWidth="9"
                            strokeLinecap="round" strokeDasharray={`${dash} ${gap}`}
                          />
                        </g>
                      );
                    })}
                  </svg>
                  <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-[30px] font-semibold leading-none text-ink">
                      {detail.adherence.pct}%
                    </span>
                    <span className="mt-1 text-[12px] text-ink-muted">Adherence</span>
                  </div>
                </div>
                <ul className="mt-auto flex items-start justify-between px-1 pt-2">
                  {macroRings.map(({ pct, color, label }) => (
                    <li key={label} className="flex flex-col items-center gap-1">
                      <span className="flex items-center gap-1.5">
                        <span aria-hidden className="block h-[7px] w-[7px] rounded-full" style={{ backgroundColor: color }} />
                        <span className="text-[13px] font-medium text-ink">{pct}%</span>
                      </span>
                      <span className="text-[11.5px] text-ink-muted">{label}</span>
                    </li>
                  ))}
                </ul>
              </section>
            </div>

            <MealDiary detail={detail} />
          </div>

          {/* Right: the evidence — when they log, and what they eat. */}
          <div className="flex min-h-0 flex-col gap-3 overflow-y-auto no-scrollbar lg:col-span-3">
            <section className="card p-4">
              <div className="flex items-center gap-2">
                <h2 className="text-[14.5px] font-medium text-ink">Logging activity</h2>
                <span className="rounded-full bg-mint px-2.5 py-[3px] text-[11px] font-medium text-mint-ink">
                  {detail.adherence.days_logged}/{detail.adherence.window_days}d ·{' '}
                  {detail.adherence.pct}%
                </span>
              </div>

              <table className="mt-3 w-full border-separate border-spacing-[5px]">
                <caption className="sr-only">Meals logged per slot across the week</caption>
                <thead>
                  <tr>
                    <th />
                    {detail.logging_grid.days.map((d) => (
                      <th key={d} scope="col" className="pb-1 text-[10.5px] font-normal text-ink-muted">
                        {new Date(d).toLocaleDateString('en-GB', { weekday: 'narrow' })}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {detail.logging_grid.cells.map((row, i) => (
                    <tr key={detail.logging_grid.slots[i]}>
                      <th scope="row" className="pr-1 text-right align-middle text-[10.5px] font-normal text-ink-muted">
                        {SLOT_LABEL[detail.logging_grid.slots[i]] ?? detail.logging_grid.slots[i]}
                      </th>
                      {row.map((b, j) => (
                        <td key={j}>
                          <span
                            title={`${SLOT_LABEL[detail.logging_grid.slots[i]]} on ${detail.logging_grid.days[j]}`}
                            className={`block h-[26px] w-full rounded-[7px] ${BUCKET_CLASS[b]}`}
                          />
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>

            <section className="card p-4">
              <h2 className="text-[14.5px] font-medium text-ink">Most logged foods</h2>
              <ul className="mt-1.5">
                {detail.top_foods.map((f, i) => {
                  const { dash, gap } = ringDash(f.pct, 14);
                  return (
                    <li key={f.name} className={`flex items-center gap-3 py-[11px] ${i > 0 ? 'border-t border-line' : ''}`}>
                      <span className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-[11px] bg-raised text-[13px]">
                        🍲
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[13px] font-medium text-ink">{f.name}</span>
                        <span className="block text-[11.5px] tabular-nums text-ink-muted">
                          {f.entries} entries · {f.kcal} kcal
                        </span>
                      </span>
                      <span className="relative flex h-[38px] w-[38px] shrink-0 items-center justify-center">
                        <svg viewBox="0 0 32 32" className="absolute inset-0 h-full w-full -rotate-90">
                          <circle cx="16" cy="16" r="14" fill="none" stroke="#2e2e2e" strokeWidth="2.2" />
                          <circle cx="16" cy="16" r="14" fill="none" stroke="#ffffff" strokeWidth="2.2"
                            strokeLinecap="round" strokeDasharray={`${dash} ${gap}`} />
                        </svg>
                        <span className="text-[10px] font-medium tabular-nums text-ink">{f.pct}%</span>
                      </span>
                    </li>
                  );
                })}
              </ul>
            </section>
          </div>
        </div>
      )
      )}
    </>
  );
}

/**
 * What the person answered when they signed up.
 *
 * docs/10 §5.5 puts the eating-disorder screening answer beyond every role but `super_admin` under a
 * `safety_review` reason — so it is not in the API's response type at all, and there is nothing here
 * to render it with. "It exists to protect the user, not to inform commerce."
 */
function RegistrationPanel({ detail }: { detail: ClientDetail }) {
  const r = detail.registration;

  return (
    <div className="grid min-h-0 flex-1 gap-3 overflow-y-auto pb-1 lg:grid-cols-3">
      <section className="card p-4">
        <h2 className="text-[14.5px] font-medium text-ink">About them</h2>
        <dl className="mt-3 grid gap-x-4 gap-y-2.5 text-[12.5px] sm:grid-cols-2">
          <Row label="Age" value={`${detail.age_years} yrs`} />
          <Row label="Sex at birth" value={label(r.sex_at_birth)} />
          <Row label="Height" value={`${detail.height_cm} cm`} />
          <Row label="Weight" value={`${detail.weight_kg.toFixed(1)} kg`} />
          <Row label="Goal weight" value={r.goal_weight_kg ? `${r.goal_weight_kg} kg` : '—'} />
          <Row label="Activity" value={label(detail.activity)} />
        </dl>
      </section>

      <section className="card p-4">
        <h2 className="text-[14.5px] font-medium text-ink">What they asked for</h2>
        <dl className="mt-3 grid gap-x-4 gap-y-2.5 text-[12.5px] sm:grid-cols-2">
          <Row label="Goal (declared)" value={label(r.goal_declared)} />
          <Row label="Goal (engine plans from)" value={label(detail.goal)} />
          <Row label="Food preference" value={label(detail.food_preference)} />
          <Row label="Meals per day" value={label(r.meal_count)} />
          <Row label="Lifestyle" value={label(r.lifestyle)} />
          <Row
            label="Budget"
            value={
              r.budget_monthly_inr
                ? `${label(r.budget_tier)} · ₹${r.budget_monthly_inr.toLocaleString('en-IN')}/mo`
                : label(r.budget_tier)
            }
          />
          <Row label="Food dislikes" value={r.food_dislikes ?? '—'} />
          <Row label="Wakes" value={r.wake_time ?? '—'} />
          <Row label="Sleeps" value={r.sleep_time ?? '—'} />
          <Row label="Sleep hours" value={r.sleep_hours ? `${r.sleep_hours} h` : '—'} />
        </dl>
      </section>

      <section className="card p-4">
        <h2 className="text-[14.5px] font-medium text-ink">When they eat</h2>
        <p className="mt-0.5 text-[11.5px] text-ink-muted">
          docs/04 §7&rsquo;s meal pattern, as they described their day.
        </p>
        <dl className="mt-3 grid gap-x-4 gap-y-2.5 text-[12.5px] sm:grid-cols-2">
          <Row label="Breakfast" value={r.meal_times.breakfast ?? '—'} />
          <Row label="Mid-morning" value={r.meal_times.mid_morning ?? '—'} />
          <Row label="Lunch" value={r.meal_times.lunch ?? '—'} />
          <Row label="Evening snack" value={r.meal_times.evening_snack ?? '—'} />
          <Row label="Dinner" value={r.meal_times.dinner ?? '—'} />
          <Row label="Bedtime snack" value={r.meal_times.bedtime_snack ?? '—'} />
        </dl>
      </section>

      <section className="card p-4">
        <h2 className="text-[14.5px] font-medium text-ink">
          Health declarations
          {r.health_profile_version !== null && (
            <span className="ml-2 rounded-full bg-raised px-2 py-[2px] text-[10.5px] text-ink-muted">
              v{r.health_profile_version}
            </span>
          )}
        </h2>
        <dl className="mt-3 flex flex-col gap-2.5 text-[12.5px]">
          <Chips label="Conditions" values={r.conditions} />
          <Chips label="Allergies" values={r.allergies} />
          <Chips label="Digestive symptoms" values={r.digestive_symptoms} />
          <Chips label="Injuries" values={r.injuries} />
          <Row label="Medications" value={r.medications ?? '—'} />
          <Row label="Clinician-prescribed diet" value={yesNo(r.screened_special_diet)} />
          <Row label="Insulin or kidney medication" value={yesNo(r.screened_insulin_or_kidney)} />
          {r.menstrual_regularity !== null && (
            <Row label="Cycle" value={label(r.menstrual_regularity)} />
          )}
          {r.pregnant_or_breastfeeding !== null && (
            <Row label="Pregnant or breastfeeding" value={yesNo(r.pregnant_or_breastfeeding)} />
          )}
          {r.heavy_bleeding_or_pain !== null && (
            <Row label="Heavy bleeding or pain" value={yesNo(r.heavy_bleeding_or_pain)} />
          )}
          {r.hormonal_medication !== null && (
            <Row label="Hormonal medication" value={yesNo(r.hormonal_medication)} />
          )}
        </dl>
        <p className="mt-3 border-t border-line pt-2.5 text-[11px] text-ink-faint">
          The eating-disorder screening answer is not shown to any role here (docs/10 §5.5).
        </p>
      </section>

      <section className="card p-4">
        <h2 className="text-[14.5px] font-medium text-ink">Eligibility gates</h2>
        <p className="mt-0.5 text-[11.5px] text-ink-muted">
          What the server decided from the answers (docs/05 §4) — stored, not recomputed here.
        </p>
        {!r.gates || Object.keys(r.gates).length === 0 ? (
          <p className="mt-3 text-[12.5px] text-ink-faint">No gate fired.</p>
        ) : (
          <dl className="mt-3 grid gap-x-4 gap-y-2.5 text-[12.5px] sm:grid-cols-2">
            {Object.entries(r.gates).map(([k, v]) => (
              <Row key={k} label={label(k)} value={String(v)} />
            ))}
          </dl>
        )}
      </section>

      <section className="card p-4 lg:col-span-2">
        <h2 className="text-[14.5px] font-medium text-ink">Consents</h2>
        {r.consents.length === 0 ? (
          <p className="mt-3 text-[12.5px] text-ink-faint">Nothing recorded.</p>
        ) : (
          <ul className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {r.consents.map((c) => (
              <li
                key={`${c.type}-${c.granted_at}`}
                className="flex items-center justify-between gap-3 rounded-tile bg-raised px-3 py-2.5"
              >
                <span className="min-w-0">
                  <span className="block truncate text-[12.5px] text-ink">{label(c.type)}</span>
                  <span className="block text-[11px] text-ink-muted">
                    Policy {c.policy_version} ·{' '}
                    {new Date(c.granted_at).toLocaleDateString('en-GB', { dateStyle: 'medium' })}
                  </span>
                </span>
                <span
                  className={`shrink-0 rounded-full px-2 py-[2px] text-[10.5px] font-medium ${
                    c.granted ? 'bg-mint text-mint-ink' : 'bg-shell text-ink-muted'
                  }`}
                >
                  {c.granted ? 'Granted' : 'Declined'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

/// `lose_weight` reads as "Lose weight" — root CLAUDE.md rule 4 bans a raw enum on screen, and the
/// vocabulary is large enough that a hand-written map per value would rot.
function label(value: string | null | undefined): string {
  if (!value) return '—';
  const words = value.replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

function yesNo(value: boolean | null): string {
  if (value === null) return 'Not asked';
  return value ? 'Yes' : 'No';
}

function Row({ label: l, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-[11px] text-ink-muted">{l}</dt>
      <dd className="mt-0.5 break-words text-ink">{value}</dd>
    </div>
  );
}

function Chips({ label: l, values }: { label: string; values: string[] }) {
  return (
    <div>
      <dt className="text-[11px] text-ink-muted">{l}</dt>
      <dd className="mt-1 flex flex-wrap gap-1">
        {values.length === 0 ? (
          <span className="text-ink-faint">—</span>
        ) : (
          values.map((v) => (
            <span key={v} className="rounded-full bg-raised px-2.5 py-1 text-[11.5px] text-ink">
              {label(v)}
            </span>
          ))
        )}
      </dd>
    </div>
  );
}

/**
 * How to reach this client, and the ways to do it.
 *
 * On the detail record only — docs/13 §4 masks contact details in list views and asks for a reveal
 * behind an audited action, which is what this endpoint already is. docs/10 §5.1 bans EXPORTING
 * client contact details ("no CSV, no 'share client list'"), so this is one person at a time with
 * no bulk copy: reading one number to answer one ticket, not harvesting a list.
 *
 * The WhatsApp link is `wa.me`, which opens a chat with the number and nothing else — it sends no
 * message and shares no data with Meta beyond the number the admin is already looking at.
 */
function ContactCard({ detail }: { detail: ClientDetail }) {
  const [copied, setCopied] = useState(false);

  // wa.me wants digits only: no +, no spaces, no dashes.
  const waNumber = detail.phone?.replace(/[^0-9]/g, '') ?? '';

  async function copy() {
    if (!detail.phone) return;
    try {
      await navigator.clipboard.writeText(detail.phone);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard access can be refused; the number is on screen to read either way.
      setCopied(false);
    }
  }

  return (
    <section className="card p-4">
      <h3 className="text-[13px] font-medium text-ink">Contact</h3>

      {detail.phone ? (
        <>
          <p className="mt-2 select-all font-mono text-[15px] tabular-nums text-ink">
            {detail.phone}
          </p>
          <p className="mt-0.5 text-[11px] text-ink-muted">
            Signed up with {detail.auth_provider ?? 'unknown'}
            {detail.email ? ` · ${detail.email}` : ''}
          </p>

          <div className="mt-3 flex flex-wrap gap-2">
            <a
              href={`https://wa.me/${waNumber}`}
              target="_blank"
              rel="noreferrer"
              className="flex h-9 items-center gap-1.5 rounded-full bg-mint px-3.5 text-[12px] font-semibold text-mint-ink transition-opacity hover:opacity-90"
            >
              <WhatsAppIcon className="h-4 w-4" aria-hidden />
              WhatsApp
            </a>
            <a
              href={`tel:${detail.phone}`}
              className="flex h-9 items-center gap-1.5 rounded-full bg-raised px-3.5 text-[12px] font-medium text-ink transition-colors hover:bg-line"
            >
              <PhoneIcon className="h-4 w-4" aria-hidden />
              Call
            </a>
            <button
              type="button"
              onClick={() =>
                downloadVCard(
                  `${displayName(detail.name).replace(/\s+/g, '-').toLowerCase()}.vcf`,
                  buildVCard({
                    name: displayName(detail.name),
                    phone: detail.phone!,
                    email: detail.email,
                    note: `Eatzify client #${detail.user_id} · ${
                      GOAL_LABEL[detail.goal] ?? detail.goal
                    }`,
                  }),
                )
              }
              className="flex h-9 items-center gap-1.5 rounded-full bg-raised px-3.5 text-[12px] font-medium text-ink transition-colors hover:bg-line"
            >
              <SaveContactIcon className="h-4 w-4" aria-hidden />
              Save contact
            </button>
            <button
              type="button"
              onClick={() => void copy()}
              className="flex h-9 items-center gap-1.5 rounded-full bg-raised px-3.5 text-[12px] font-medium text-ink transition-colors hover:bg-line"
            >
              <CopyIcon className="h-4 w-4" aria-hidden />
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
        </>
      ) : (
        <p className="mt-2 text-[12.5px] text-ink-faint">No number on file.</p>
      )}

      <p className="mt-3 border-t border-line pt-2.5 text-[10.5px] text-ink-faint">
        Opening this record is recorded in the audit log.
      </p>
    </section>
  );
}

function pctOf(value: number, target: number | undefined): number {
  if (!target) return 0;
  return Math.round((value / target) * 100);
}

/// Today's intake, in the slot the reference gives a running timer. A diary IS the health app's
/// equivalent of time tracked: the thing accumulating through the day.
function IntakeCard({ detail }: { detail: ClientDetail }) {
  const target = detail.targets?.kcal ?? 0;
  const pct = pctOf(detail.today.kcal, target);

  return (
    <section className="card flex min-w-0 flex-col p-4">
      <h2 className="text-[14.5px] font-medium text-ink">Today&rsquo;s intake</h2>

      <div className="mt-3.5 rounded-tile bg-mint p-3.5 text-mint-ink">
        <p className="text-[12.5px] font-medium opacity-70">
          {target ? `Target ${target} kcal` : 'No plan yet'}
        </p>
        <p className="mt-1.5 font-mono text-timer font-semibold tabular-nums">
          {detail.today.kcal}
          <span className="ml-1 text-[16px] opacity-60">kcal</span>
        </p>
        <div className="mt-2.5 h-1.5 overflow-hidden rounded-full bg-black/15">
          <div className="h-full rounded-full bg-mint-ink/70" style={{ width: `${Math.min(100, pct)}%` }} />
        </div>
      </div>

      <ul className="mt-1 min-h-0 flex-1">
        {([
          ['Protein', detail.today.proteinG, detail.targets?.proteinG],
          ['Carbs', detail.today.carbG, detail.targets?.carbG],
          ['Fat', detail.today.fatG, detail.targets?.fatG],
        ] as const).map(([label, eaten, t], i) => (
          <li key={label} className={`flex items-center gap-3 py-3 ${i > 0 ? 'border-t border-line' : ''}`}>
            <span className="min-w-0 flex-1">
              <span className="block text-[13px] font-medium text-ink">{label}</span>
              <span className="block text-[11.5px] tabular-nums text-ink-muted">
                {eaten} / {t ?? '—'} g
              </span>
            </span>
            <span className="text-[12.5px] tabular-nums text-ink-muted">{pctOf(eaten, t)}%</span>
          </li>
        ))}
      </ul>

      <p className="pt-1 text-[11.5px] text-ink-muted">
        {detail.today.entries === 0
          ? 'Nothing logged yet today.'
          : `${detail.today.entries} entries today.`}
      </p>
    </section>
  );
}

/// The week's meals by slot — the reference's task calendar, carrying a diary.
function MealDiary({ detail }: { detail: ClientDetail }) {
  const { days, slots } = detail.logging_grid;

  return (
    <section className="card flex min-h-0 min-w-0 flex-1 flex-col p-4">
      <h2 className="text-[14.5px] font-medium text-ink">Meal diary · last 7 days</h2>

      <div className="mt-3 min-h-0 flex-1 overflow-auto">
        <table className="w-full border-separate border-spacing-x-1 border-spacing-y-1.5">
          <thead>
            <tr>
              <th className="w-[86px] text-left text-[11.5px] font-normal text-ink-muted">Slot</th>
              {days.map((d) => (
                <th key={d} className="text-[11.5px] font-normal text-ink-muted">
                  {new Date(d).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric' })}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {slots.map((slot) => (
              <tr key={slot}>
                <th scope="row" className="text-left text-[12px] font-medium text-ink-muted">
                  {SLOT_LABEL[slot] ?? slot}
                </th>
                {days.map((date) => {
                  const meal = detail.recent_meals.find(
                    (m) => m.date === date && m.slot === slot,
                  );
                  return (
                    <td key={`${slot}-${date}`} className="align-top">
                      {meal ? (
                        <div className="rounded-tile bg-raised px-2 py-1.5" title={`${meal.name} — ${meal.kcal} kcal`}>
                          <p className="truncate text-[11.5px] font-medium text-ink">{meal.name}</p>
                          <p className="text-[10.5px] tabular-nums text-ink-muted">{meal.kcal} kcal</p>
                        </div>
                      ) : (
                        <div className="rounded-tile border border-dashed border-line/70 px-2 py-1.5">
                          <p className="text-[10.5px] text-ink-faint">—</p>
                        </div>
                      )}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/// Weight over time as a sparkline. Never a judgement, never red — docs/05 §6.
function WeightSpark({ series }: { series: { date: string; kg: number }[] }) {
  if (series.length < 2) return null;

  const values = series.map((s) => s.kg);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  const points = series
    .map((s, i) => {
      const x = (i / (series.length - 1)) * 100;
      const y = 30 - ((s.kg - min) / span) * 26;
      return `${x},${y}`;
    })
    .join(' ');

  return (
    <svg viewBox="0 0 100 32" preserveAspectRatio="none" className="mt-3 h-8 w-full" aria-hidden>
      <polyline points={points} fill="none" stroke="#c2ebe1" strokeWidth="1.6"
        strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-[300px] flex-1 flex-col items-center justify-center gap-3 text-[13px] text-ink-muted">
      {children}
    </div>
  );
}
