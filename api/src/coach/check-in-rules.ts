/// docs/02 FR-5.2 ("clients with a due or overdue check-in, sorted by risk") and FR-5.3's alerts,
/// as arithmetic — no database, so the cadence and the sorting can be argued with in a test.

/// A check-in falls due once a week, on the Monday of that week.
///
/// docs/02 names the queue but not the cadence. Weekly is what a nutritionist's review actually is,
/// and a FIXED weekday beats "seven days after the last one": every client in a coach's queue then
/// falls due on the same day, which is what makes a queue workable rather than a trickle.
export const CHECK_IN_WEEKDAY = 1;

/// docs/02 FR-5.3: "no log ≥3 days".
export const NO_LOG_ALERT_DAYS = 3;

/// A plan ending within this many days is worth chasing before it lapses.
export const EXPIRING_SOON_DAYS = 30;

export const CHECK_IN_STATUSES = ['due', 'completed', 'missed'] as const;
export type CheckInStatus = (typeof CHECK_IN_STATUSES)[number];

/// The Monday on or before [diaryDate] (`yyyy-MM-dd` in, `yyyy-MM-dd` out).
///
/// Takes the diary date rather than an instant on purpose: which day it is belongs to the server's
/// 04:00 IST boundary (api/CLAUDE.md rule 4), and this must never be a second opinion about that.
export function weekOf(diaryDate: string): string {
  const date = new Date(`${diaryDate}T00:00:00Z`);
  // getUTCDay: 0 is Sunday, so Sunday is six days after its Monday.
  const back = (date.getUTCDay() + 7 - CHECK_IN_WEEKDAY) % 7;
  date.setUTCDate(date.getUTCDate() - back);
  return date.toISOString().slice(0, 10);
}

/// Whole days from [from] to [to], both `yyyy-MM-dd`. Negative when [to] is earlier.
export function daysBetweenDates(from: string, to: string): number {
  return Math.round(
    (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) /
      86_400_000,
  );
}

/// Whether a check-in due in [dueWeek] has been left behind by [thisWeek].
export function isOverdue(dueWeek: string, thisWeek: string): boolean {
  return daysBetweenDates(dueWeek, thisWeek) > 0;
}

export type QueueItem = {
  status: CheckInStatus;
  due_on: string;
  days_since_last_log: number | null;
};

/**
 * docs/02 FR-5.2's "sorted by risk".
 *
 * Risk here is "who is furthest from being looked after": anything already missed comes first,
 * then the oldest due date, then the longest without a log. Never sorted by weight lost or by a
 * streak — docs/05 §6 forbids ranking people against each other on weight, and a queue sorted that
 * way is exactly that ranking.
 */
export function byRisk<T extends QueueItem>(items: readonly T[]): T[] {
  const rank = (item: QueueItem) => (item.status === 'missed' ? 0 : 1);

  return [...items].sort(
    (a, b) =>
      rank(a) - rank(b) ||
      a.due_on.localeCompare(b.due_on) ||
      (b.days_since_last_log ?? -1) - (a.days_since_last_log ?? -1),
  );
}

export type AlertKind =
  'no_logs' | 'off_trend' | 'plan_expiring' | 'checkin_missed';

/// docs/02 FR-5.3's four signals, decided from figures the coach may already see.
///
/// A null is never a signal: "no weight reading" is not "off trend", and a client whose grant hides
/// their weight simply produces no weight alert (docs/10).
export function alertsFor(client: {
  daysSinceLastLog: number | null;
  goal: string | null;
  weightChange30d: number | null;
  planEndsInDays: number | null;
  missedCheckIn: boolean;
}): AlertKind[] {
  const alerts: AlertKind[] = [];

  if ((client.daysSinceLastLog ?? 0) >= NO_LOG_ALERT_DAYS)
    alerts.push('no_logs');

  if (client.weightChange30d !== null && client.goal !== null) {
    // Moving the wrong way for what they asked for. Not a judgement and never shown to the client
    // as one — it is a prompt for the coach to ask what is going on (docs/05 §6).
    const wrongWay =
      (client.goal === 'fat_loss' && client.weightChange30d > 0) ||
      (client.goal === 'muscle_gain' && client.weightChange30d < 0);
    if (wrongWay) alerts.push('off_trend');
  }

  if (
    client.planEndsInDays !== null &&
    client.planEndsInDays >= 0 &&
    client.planEndsInDays <= EXPIRING_SOON_DAYS
  ) {
    alerts.push('plan_expiring');
  }

  if (client.missedCheckIn) alerts.push('checkin_missed');

  return alerts;
}
