'use client';

import { useCallback, useEffect, useState } from 'react';
import { TotpPrompt } from '../TotpPrompt';
import {
  CheckIcon,
  CloseIcon,
  RefreshIcon,
  SpinnerIcon,
  WhatsAppIcon,
} from '../icons';

interface ApplicationRow {
  id: string;
  user_id: number;
  name: string | null;
  phone_masked: string | null;
  status: 'draft' | 'submitted' | 'verified' | 'rejected';
  discipline: string | null;
  submitted_at: string | null;
  waiting_days: number | null;
  has_id_document: boolean;
  has_qualification_document: boolean;
  verified_attributes: string[];
  reviewed_at: string | null;
  reviewed_by_user_id: number | null;
}

const STATUSES = ['submitted', 'verified', 'rejected', 'draft'] as const;

interface ApplicantIdentity {
  user_id: number;
  name: string | null;
  email: string | null;
  phone: string | null;
  auth_provider: string | null;
  discipline: string | null;
  status: string;
  agreement_version: string | null;
  agreement_accepted_at: string | null;
  submitted_at: string | null;
  id_document_file_id: string | null;
  qualification_document_file_id: string | null;
  verified_attributes: string[];
  rejection_reason: string | null;
  reviewed_at: string | null;
  reviewed_by_user_id: number | null;
}

const DISCIPLINE_LABEL: Record<string, string> = {
  trainer: 'Trainer',
  nutritionist: 'Nutritionist',
  doctor: 'Doctor',
  other: 'Other',
};

function label(value: string | null | undefined): string {
  if (!value) return '—';
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function when(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' }) : '—';
}

/// What a reviewer can say they SAW. A closed list, because "we saw a degree certificate" is a
/// claim Eatzify can make and "this person is qualified" is not (doc 00 §8) — and because free text
/// makes `verified_by_attribute` in the metrics unanswerable.
const ATTRIBUTES = [
  'government_id',
  'dietetics_degree',
  'medical_licence',
  'training_certification',
  'practice_registration',
];

export function PartnerReview() {
  const [status, setStatus] = useState<(typeof STATUSES)[number]>('submitted');
  const [rows, setRows] = useState<ApplicationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [openId, setOpenId] = useState<number | null>(null);
  const [toast, setToast] = useState<{ kind: 'ok' | 'bad'; text: string } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/applications?status=${status}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Could not load applications.');
      setRows(data as ApplicationRow[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load applications.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [status]);

  useEffect(() => {
    void load();
  }, [load]);

  // The toast clears itself. A banner that stays until the next action turns into furniture and
  // stops being read.
  useEffect(() => {
    if (!toast) return;
    const id = setTimeout(() => setToast(null), 4000);
    return () => clearTimeout(id);
  }, [toast]);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-[19px] font-semibold tracking-[-0.01em] text-ink">
            Partner applications
          </h2>
          <p className="mt-0.5 text-[12.5px] text-ink-muted">
            Verifying records what was checked — never that the person is qualified.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div
            role="tablist"
            aria-label="Filter by status"
            className="flex items-center gap-1 rounded-full bg-surface p-1"
          >
            {STATUSES.map((s) => (
              <button
                key={s}
                role="tab"
                aria-selected={s === status}
                onClick={() => setStatus(s)}
                className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium capitalize transition-colors ${
                  s === status
                    ? 'bg-mint text-mint-ink'
                    : 'text-ink-muted hover:bg-raised hover:text-ink'
                }`}
              >
                {s}
              </button>
            ))}
          </div>

          <button
            onClick={() => void load()}
            aria-label="Refresh"
            className="flex h-[34px] w-[34px] items-center justify-center rounded-full bg-surface text-ink-muted transition-colors hover:bg-raised hover:text-ink"
          >
            <RefreshIcon className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </header>

      {toast && (
        <div
          role="status"
          className={`rounded-tile px-4 py-3 text-[13px] ${
            toast.kind === 'ok' ? 'bg-mint text-mint-ink' : 'bg-[#3a1f1f] text-[#ffb4b4]'
          }`}
        >
          {toast.text}
        </div>
      )}

      <div className="card min-h-0 flex-1 overflow-auto p-2">
        {loading && rows.length === 0 ? (
          <Centered>
            <SpinnerIcon className="h-5 w-5 animate-spin text-ink-muted" />
            <span>Loading applications…</span>
          </Centered>
        ) : error ? (
          <Centered>
            <span className="text-[#ffb4b4]">{error}</span>
            <button
              onClick={() => void load()}
              className="rounded-full bg-raised px-4 py-1.5 text-[12.5px] text-ink hover:bg-line"
            >
              Try again
            </button>
          </Centered>
        ) : rows.length === 0 ? (
          <Centered>
            <span>
              Nothing {status === 'submitted' ? 'waiting for review' : `marked ${status}`}.
            </span>
          </Centered>
        ) : (
          <ul className="flex flex-col gap-1.5">
            {rows.map((row) => (
              <ApplicationCard
                key={row.id}
                row={row}
                open={openId === row.user_id}
                onToggle={() => setOpenId(openId === row.user_id ? null : row.user_id)}
                onDecided={(text) => {
                  setToast({ kind: 'ok', text });
                  setOpenId(null);
                  void load();
                }}
                onFailed={(text) => setToast({ kind: 'bad', text })}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full min-h-[260px] flex-col items-center justify-center gap-3 text-[13px] text-ink-muted">
      {children}
    </div>
  );
}

function ApplicationCard({
  row,
  open,
  onToggle,
  onDecided,
  onFailed,
}: {
  row: ApplicationRow;
  open: boolean;
  onToggle: () => void;
  onDecided: (text: string) => void;
  onFailed: (text: string) => void;
}) {
  const [checked, setChecked] = useState<string[]>([]);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState<'verify' | 'reject' | null>(null);

  const decidable = row.status === 'submitted';

  async function decide(decision: 'verify' | 'reject') {
    setBusy(decision);
    try {
      const res = await fetch(`/api/applications/${row.user_id}/decide`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          decision,
          verified_attributes: checked,
          reason,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'The decision was refused.');
      onDecided(
        decision === 'verify'
          ? `User ${row.user_id} verified — ${checked.length} attribute(s) recorded.`
          : `User ${row.user_id} rejected. They will see your reason.`,
      );
    } catch (e) {
      onFailed(e instanceof Error ? e.message : 'The decision was refused.');
    } finally {
      setBusy(null);
    }
  }

  return (
    <li className="rounded-tile bg-raised">
      <button
        onClick={onToggle}
        aria-expanded={open}
        className="flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-line/60"
      >
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-shell text-[12.5px] font-semibold text-ink">
          {row.user_id}
        </span>

        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <span className="text-[13.5px] font-medium text-ink">
              {row.name ?? `User ${row.user_id}`}
            </span>
            <span className="text-[12px] text-ink-muted">
              {DISCIPLINE_LABEL[row.discipline ?? ''] ?? 'Not declared'}
            </span>
            <StatusChip status={row.status} />
          </span>
          <span className="mt-0.5 block text-[11.5px] text-ink-muted">
            {row.phone_masked ? `${row.phone_masked} · ` : ''}
            {row.waiting_days !== null
              ? `Waiting ${row.waiting_days} day${row.waiting_days === 1 ? '' : 's'}`
              : 'Not submitted'}
            {' · '}
            ID {row.has_id_document ? '✓' : '✗'} · Qualification{' '}
            {row.has_qualification_document ? '✓' : '✗'}
          </span>
        </span>

        {row.verified_attributes.length > 0 && (
          <span className="hidden shrink-0 text-[11.5px] text-ink-muted sm:block">
            {row.verified_attributes.length} checked
          </span>
        )}
      </button>

      {open && (
        <div className="border-t border-line px-4 py-4">
          <ApplicantPanel userId={row.user_id} />

          {decidable ? (
            <div className="grid gap-4 lg:grid-cols-2">
              <fieldset>
                <legend className="text-[12.5px] font-medium text-ink">
                  What did you actually check?
                </legend>
                <p className="mt-1 text-[11.5px] text-ink-muted">
                  At least one is required. This is stored as the verification claim.
                </p>
                <div className="mt-2.5 flex flex-wrap gap-1.5">
                  {ATTRIBUTES.map((attr) => {
                    const on = checked.includes(attr);
                    return (
                      <button
                        key={attr}
                        type="button"
                        aria-pressed={on}
                        onClick={() =>
                          setChecked(
                            on ? checked.filter((a) => a !== attr) : [...checked, attr],
                          )
                        }
                        className={`rounded-full px-3 py-1.5 text-[11.5px] transition-colors ${
                          on
                            ? 'bg-mint text-mint-ink'
                            : 'bg-shell text-ink-muted hover:text-ink'
                        }`}
                      >
                        {attr.replace(/_/g, ' ')}
                      </button>
                    );
                  })}
                </div>

                <button
                  onClick={() => void decide('verify')}
                  disabled={busy !== null || checked.length === 0}
                  className="mt-3.5 flex h-10 w-full items-center justify-center gap-2 rounded-full bg-mint text-[13px] font-semibold text-mint-ink transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  {busy === 'verify' ? (
                    <SpinnerIcon className="h-4 w-4 animate-spin" />
                  ) : (
                    <CheckIcon className="h-4 w-4" />
                  )}
                  Verify partner
                </button>
              </fieldset>

              <div>
                <label
                  htmlFor={`reason-${row.user_id}`}
                  className="text-[12.5px] font-medium text-ink"
                >
                  Or reject, with a reason
                </label>
                <p className="mt-1 text-[11.5px] text-ink-muted">
                  The applicant is shown this text, so write it for them.
                </p>
                <textarea
                  id={`reason-${row.user_id}`}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  rows={3}
                  placeholder="e.g. The qualification document was unreadable."
                  className="mt-2.5 w-full resize-none rounded-tile bg-shell px-3 py-2.5 text-[12.5px] text-ink placeholder:text-ink-faint focus:outline-none focus:ring-1 focus:ring-line"
                />
                <button
                  onClick={() => void decide('reject')}
                  disabled={busy !== null || reason.trim().length === 0}
                  className="mt-2.5 flex h-10 w-full items-center justify-center gap-2 rounded-full bg-shell text-[13px] font-semibold text-[#ffb4b4] transition-colors hover:bg-[#3a1f1f] disabled:cursor-not-allowed disabled:opacity-40"
                >
                  {busy === 'reject' ? (
                    <SpinnerIcon className="h-4 w-4 animate-spin" />
                  ) : (
                    <CloseIcon className="h-4 w-4" />
                  )}
                  Reject application
                </button>
              </div>
            </div>
          ) : (
            <dl className="grid gap-2 text-[12.5px] sm:grid-cols-2">
              <Field
                label="Status"
                value={row.status.charAt(0).toUpperCase() + row.status.slice(1)}
              />
              <Field label="Reviewed by" value={row.reviewed_by_user_id ?? '—'} />
              <Field
                label="Reviewed at"
                value={row.reviewed_at ? new Date(row.reviewed_at).toLocaleString() : '—'}
              />
              <Field
                label="Verified attributes"
                value={
                  row.verified_attributes.length
                    ? row.verified_attributes.join(', ').replace(/_/g, ' ')
                    : '—'
                }
              />
            </dl>
          )}
        </div>
      )}
    </li>
  );
}

/**
 * Who the applicant is, fetched on demand.
 *
 * Deliberately NOT part of the queue payload. The list is masked (docs/13 §4) and this is the
 * audited reveal — so it loads when a row is opened, and opening a row is the action the audit log
 * records. An admin cannot verify a person whose name they never see, and the doc asks for a reveal,
 * not a blackout.
 */
function ApplicantPanel({ userId }: { userId: number }) {
  const [data, setData] = useState<ApplicantIdentity | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // D-229: the full phone number is one of the three things behind a second factor, so the panel
  // no longer loads itself when a row opens — it asks for a code first. Opening a row to check a
  // submission date should not spend a reveal.
  async function reveal(code: string) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/applications/${userId}/applicant`, {
        headers: { 'X-Totp': code },
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? 'Could not load the applicant.');
      setData(body as ApplicantIdentity);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the applicant.');
    } finally {
      setBusy(false);
    }
  }

  if (!data) {
    return (
      <div className="mb-4">
        <TotpPrompt
          action="Seeing who this is"
          busy={busy}
          error={error}
          onSubmit={(code) => void reveal(code)}
          onCancel={() => setError(null)}
        />
      </div>
    );
  }

  return (
    <div className="mb-4 rounded-tile bg-shell p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-[15px] font-semibold text-ink">{data.name ?? 'No name on file'}</p>
          <p className="mt-0.5 text-[12px] text-ink-muted">
            Applied as {DISCIPLINE_LABEL[data.discipline ?? ''] ?? 'not declared'} · user{' '}
            {data.user_id}
          </p>
        </div>
        <span className="rounded-full bg-raised px-2.5 py-1 text-[10.5px] text-ink-muted">
          Viewing this is recorded in the audit log
        </span>
      </div>

      <dl className="mt-3.5 grid gap-x-6 gap-y-2.5 text-[12.5px] sm:grid-cols-2 lg:grid-cols-3">
        <Field
          label="Email"
          value={
            data.email ??
            (data.auth_provider === 'phone' ? 'Not collected (phone sign-up)' : '—')
          }
        />
        <div>
          <dt className="text-[11.5px] text-ink-muted">Phone</dt>
          <dd className="mt-0.5 flex flex-wrap items-center gap-2">
            <span className="select-all font-mono tabular-nums text-ink">
              {data.phone ?? '—'}
            </span>
            {data.phone && (
              <a
                href={`https://wa.me/${data.phone.replace(/[^0-9]/g, '')}`}
                target="_blank"
                rel="noreferrer"
                // The one way to reach an applicant whose email was never collected — a phone
                // sign-up has no other channel, and "your document was unreadable" is a
                // conversation, not a rejection reason.
                className="flex h-7 items-center gap-1.5 rounded-full bg-mint px-2.5 text-[11px] font-semibold text-mint-ink transition-opacity hover:opacity-90"
              >
                <WhatsAppIcon className="h-3.5 w-3.5" aria-hidden />
                WhatsApp
              </a>
            )}
          </dd>
        </div>
        <Field label="Declared discipline" value={DISCIPLINE_LABEL[data.discipline ?? ''] ?? 'Not declared'} />
        <Field label="Signed up with" value={label(data.auth_provider)} />
        <Field label="Agreement" value={data.agreement_version ?? '—'} />
        <Field label="Agreed on" value={when(data.agreement_accepted_at)} />
        <Field label="Submitted" value={when(data.submitted_at)} />
        <Field
          label="Verified as"
          value={
            data.verified_attributes.length
              ? data.verified_attributes.join(', ').replace(/_/g, ' ')
              : '—'
          }
        />
      </dl>

      <DocumentViewer userId={data.user_id} identity={data} />

      {data.rejection_reason && (
        <p className="mt-3 rounded-tile bg-[#3a1f1f] px-3 py-2 text-[12px] text-[#ffb4b4]">
          Previously rejected: {data.rejection_reason}
        </p>
      )}
    </div>
  );
}

/**
 * One labelled value.
 *
 * No `capitalize` here. It was on this element and it mangled every value that is not prose —
 * `dr.neha.bhatia@demo.eatzify.test` rendered as `Dr.Neha.Bhatia@Demo.Eatzify.Test` and agreement
 * `v1` as `V1`. An email address and a version string are identifiers: they are shown exactly as
 * stored or they are shown wrong. Callers that DO want title case pass an already-formatted string.
 */
/**
 * The two uploaded documents, shown rather than described.
 *
 * "On file" tells a reviewer nothing they can verify against. docs/12 §6 defines level 2 as
 * "ID + qualification document on file", where on file means a human looked — so the human has to
 * be able to look.
 *
 * The image is fetched through this app's own route, which streams it from the API under the
 * server-held token. There is no URL a reviewer could paste to anyone, and the API records every
 * open in the audit log.
 */
function DocumentViewer({
  userId,
  identity,
}: {
  userId: number;
  identity: ApplicantIdentity;
}) {
  const docs = [
    { kind: 'id' as const, label: 'Photo ID', present: !!identity.id_document_file_id },
    {
      kind: 'qualification' as const,
      label: 'Qualification',
      present: !!identity.qualification_document_file_id,
    },
  ];

  return (
    <div className="mt-4 grid gap-3 sm:grid-cols-2">
      {docs.map((d) => (
        <DocumentTile key={d.kind} userId={userId} kind={d.kind} label={d.label} present={d.present} />
      ))}
    </div>
  );
}

function DocumentTile({
  userId,
  kind,
  label,
  present,
}: {
  userId: number;
  kind: 'id' | 'qualification';
  label: string;
  present: boolean;
}) {
  const [failed, setFailed] = useState(false);
  const src = `/api/applications/${userId}/document/${kind}`;

  return (
    <figure className="overflow-hidden rounded-tile bg-raised">
      <figcaption className="flex items-center justify-between gap-2 px-3 py-2">
        <span className="text-[12.5px] font-medium text-ink">{label}</span>
        {present && !failed && (
          <a
            href={src}
            target="_blank"
            rel="noreferrer"
            className="rounded-full bg-shell px-2.5 py-1 text-[11px] text-ink-muted transition-colors hover:text-ink"
          >
            Open full size
          </a>
        )}
      </figcaption>

      <div className="flex min-h-[170px] items-center justify-center bg-shell">
        {!present ? (
          <span className="px-3 py-8 text-center text-[12px] text-ink-faint">
            Not provided by the applicant.
          </span>
        ) : failed ? (
          <span className="px-3 py-8 text-center text-[12px] text-[#ffb4b4]">
            The file is recorded but could not be loaded.
          </span>
        ) : (
          // eslint-disable-next-line @next/next/no-img-element -- the bytes are proxied and
          // deliberately not cached; next/image would try to optimise and cache them.
          <img
            src={src}
            alt={`${label} submitted by user ${userId}`}
            onError={() => setFailed(true)}
            className="max-h-[300px] w-full object-contain"
          />
        )}
      </div>
    </figure>
  );
}

function Field({ label, value }: { label: string; value: string | number }) {
  return (
    <div>
      <dt className="text-[11.5px] text-ink-muted">{label}</dt>
      <dd className="mt-0.5 break-words text-ink">{value}</dd>
    </div>
  );
}

function StatusChip({ status }: { status: ApplicationRow['status'] }) {
  const tone =
    status === 'verified'
      ? 'bg-mint text-mint-ink'
      : status === 'rejected'
        ? 'bg-[#3a1f1f] text-[#ffb4b4]'
        : status === 'submitted'
          ? 'bg-shell text-ink'
          : 'bg-shell text-ink-muted';

  return (
    <span className={`rounded-full px-2 py-[2px] text-[10.5px] font-medium capitalize ${tone}`}>
      {status}
    </span>
  );
}
