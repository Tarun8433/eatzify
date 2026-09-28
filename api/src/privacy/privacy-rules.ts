/**
 * The dates docs/13 puts on a data-subject right, in one pure file so they can be tested without a
 * database and cited without reading a service.
 *
 * Every number here is from docs/13 §6 and §9. None of them is a preference.
 */

/// docs/13 §9: erasure has a seven-day cooling-off before it runs.
export const DELETE_COOLING_OFF_DAYS = 7;

/// docs/13 §6: "notify the user 48 hours before erasure".
export const ERASURE_NOTICE_HOURS = 48;

/// docs/13 §9: the export link expires in 24 hours.
export const EXPORT_LINK_HOURS = 24;

/**
 * docs/13 §6's retention table, in days, for the rows a sweep can act on by itself.
 *
 * The rows NOT here are the ones whose clock starts at an event rather than at "last activity" —
 * support tickets (2 years from closure) and coach chat (1 year after the assignment ends) — and
 * the ones that are kept for a statutory reason rather than a retention policy: payments and
 * invoices for 8 years (Companies Act / GST), consent records for 7 years as evidence of lawful
 * basis, and the audit log for 3 years, immutable. Deleting any of those on a schedule would break
 * a legal obligation, which is why they are listed here in words and excluded in code.
 */
export const RETENTION_DAYS = {
  /// Health profile, conditions, measurements, food logs, plans and traces.
  healthAfterInactivity: 3 * 365,
  /// docs/13 §4 and §6: the shortest useful retention, and never in a public bucket.
  mealPhotos: 90,
  /// docs/05 §4's screening answers.
  screening: 365,
  /// Support tickets, from closure.
  ticketsAfterClosure: 2 * 365,
  /// Coach chat, after the assignment ends.
  chatAfterAssignmentEnd: 365,
  /// The account itself, after an erasure request completes.
  accountAfterDeletion: 30,
} as const;

const DAY_MS = 24 * 60 * 60 * 1000;

export function addDays(from: Date, days: number): Date {
  return new Date(from.getTime() + days * DAY_MS);
}

export function addHours(from: Date, hours: number): Date {
  return new Date(from.getTime() + hours * 60 * 60 * 1000);
}

/// When an erasure asked for at [requestedAt] may actually run.
export function erasureDueAt(requestedAt: Date): Date {
  return addDays(requestedAt, DELETE_COOLING_OFF_DAYS);
}

/// Whether the 48-hour warning is owed yet — true from 48 hours before the erasure is due.
export function noticeDue(executeAfter: Date, now: Date): boolean {
  return now >= addHours(executeAfter, -ERASURE_NOTICE_HOURS);
}

/// Whether the erasure itself may run: the cooling-off has passed AND the warning has gone out.
/// Both, because a person warned two hours before deletion was not warned.
export function erasureDue(
  request: { executeAfter: Date; notifiedAt: Date | null },
  now: Date,
): boolean {
  if (now < request.executeAfter) return false;
  if (request.notifiedAt === null) return false;

  return now >= addHours(request.notifiedAt, ERASURE_NOTICE_HOURS);
}

export function exportExpiresAt(builtAt: Date): Date {
  return addHours(builtAt, EXPORT_LINK_HOURS);
}

/// The cut-off a retention sweep compares a row's date against.
export function retentionCutoff(now: Date, days: number): Date {
  return addDays(now, -days);
}
