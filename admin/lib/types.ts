/**
 * What the dashboard renders.
 *
 * Every type here is annotated with where its data comes from TODAY, because the answer differs per
 * widget and the difference matters: half of this screen is backed by endpoints that exist and half
 * is waiting on entities nobody has built yet (D-182). A type that does not say which is which is
 * how a demo gets mistaken for a working feature.
 */

/** LIVE — `GET /api/v1/admin/metrics/overview`. */
export interface AdminOverview {
  users: { total: number; by_role: Record<string, number>; normal: number };
  coach_applications: {
    total: number;
    by_status: Record<string, number>;
    by_discipline: Record<string, number>;
    verified_by_attribute: Record<string, number>;
    awaiting_review: number;
    oldest_awaiting_review_days: number | null;
  };
  invites: {
    total: number;
    by_status: Record<string, number>;
    acceptance_rate: number | null;
  };
  grants: {
    active: number;
    by_scope: Record<string, number>;
    active_health_conditions: number;
  };
  subscriptions: {
    by_tier: Record<string, number>;
    by_status: Record<string, number>;
  };
}

/** PENDING — needs an `employee` entity. Today: `user` + `profile` carry name and photo only. */
export interface Employee {
  id: number;
  name: string;
  role: string;
  photoUrl: string;
  daysInCompany: number;
  doneProjects: number;
  /** Integer paise/cents. Never a float — `api/CLAUDE.md` rule 3. */
  salaryMinor: number;
  salaryCurrency: string;
}

/** PENDING — needs a `time_entry` entity. */
export interface TimeEntry {
  id: string;
  project: string;
  /** Seconds. Formatted at the edge, so the number stays arithmetic until it is displayed. */
  seconds: number;
  running: boolean;
}

export interface TrackedTask {
  id: string;
  title: string;
  seconds: number;
  icon: 'gear' | 'nodes';
}

/** PENDING — needs a `working_format` field on the employee or a team policy table. */
export interface WorkingFormat {
  totalDays: number;
  officePct: number;
  hybridPct: number;
  remotePct: number;
}

/**
 * PENDING — needs a `work_activity` entity.
 *
 * `hours` is a bucket index, not a measurement: 0 = none, 1 = >2h, 2 = >4h, 3 = >8h. The reference's
 * legend defines exactly four states and the grid is only legible because there are four.
 */
export type ActivityBucket = 0 | 1 | 2 | 3;

export interface WorkActivity {
  /** Row labels, top to bottom, as the reference prints them. */
  hourLabels: string[];
  dayLabels: string[];
  /** `cells[hourIndex][dayIndex]`. */
  cells: ActivityBucket[][];
  totalHours: number;
  averagePct: number;
}

/**
 * PENDING — needs an `app_usage` entity, and a product decision before that.
 *
 * This is workplace monitoring: which applications and sites a named person used, and for how long.
 * docs/13 is explicit that Eatzify collects less, and the DPDP Act attaches consent and
 * purpose-limitation duties to exactly this kind of record. The type exists because the reference
 * calls for the widget; the entity behind it should not be built without that decision (D-182).
 */
export interface AppUsage {
  id: string;
  name: string;
  seconds: number;
  /** Share of tracked time, 0–100. */
  pct: number;
  /** Key into the brand mark set. */
  icon: 'vscode' | 'figma' | 'chrome' | 'github' | 'chatgpt';
}

/** PENDING — needs a `task` entity with scheduling. */
export interface ScheduledTask {
  id: string;
  title: string;
  subtitle: string;
  /** 0 = Sunday, matching the reference's week start. */
  dayIndex: number;
  /** Decimal hours on a 24h clock: 13.5 is 13:30. */
  startHour: number;
  endHour: number;
  attendees: string[];
  highlighted?: boolean;
}

export interface TeamMember {
  id: number;
  name: string;
  photoUrl: string;
}

export interface DashboardData {
  overview: AdminOverview | null;
  employee: Employee;
  team: { name: string; department: string; memberCount: number; members: TeamMember[] };
  timeEntry: TimeEntry;
  trackedTasks: TrackedTask[];
  workingFormat: WorkingFormat;
  workActivity: WorkActivity;
  apps: AppUsage[];
  tasks: ScheduledTask[];
  viewer: { name: string; role: string; photoUrl: string };
  weather: { tempC: number };
}
