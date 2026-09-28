import type { ActivityBucket, AdminOverview, DashboardData } from './types';
import { adminFetch } from './api';
import { readSession } from './session';

/**
 * The live half.
 *
 * Returns null rather than throwing when the API is down or the token is missing: an admin dashboard
 * that renders nothing because one panel could not load is worse than one that renders the panels it
 * has. The widgets that depend on this show their own empty state.
 */
export async function fetchOverview(): Promise<AdminOverview | null> {
  try {
    const res = await adminFetch('/admin/metrics/overview');
    if (!res.ok) return null;
    return (await res.json()) as AdminOverview;
  } catch {
    return null;
  }
}

/**
 * The pending half, as representative data.
 *
 * Every field here corresponds to an entity that does not exist yet (D-182). It is shaped exactly
 * like the real thing will be, so wiring it up later is swapping this function out rather than
 * touching a component — and it is in ONE file, deliberately, so "what is still fake?" has a
 * one-word answer instead of a search.
 */
function placeholder(): Omit<DashboardData, 'overview'> {
  const photo = (id: string, w = 160) =>
    `https://images.unsplash.com/${id}?auto=format&fit=crop&w=${w}&q=80`;

  // Sunday-first, matching the reference's column order.
  const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const hourLabels = ['2pm', '1pm', '12am', '11am', '10am', '9am', '8am'];

  // Read off the reference cell by cell rather than generated, so the grid has the same texture —
  // a random fill reads as noise and this one clearly shows a working week.
  const cells: ActivityBucket[][] = [
    [0, 0, 0, 2, 2, 0, 0],
    [3, 3, 3, 2, 3, 3, 0],
    [3, 2, 3, 3, 3, 0, 3],
    [3, 3, 3, 2, 3, 3, 3],
    [3, 3, 2, 3, 3, 3, 3],
    [3, 3, 3, 3, 0, 0, 3],
    [0, 3, 3, 0, 0, 2, 2],
  ];

  return {
    employee: {
      id: 1,
      name: 'Milena Page',
      role: 'Frontend Developer',
      photoUrl: photo('photo-1544005313-94ddf0286df2', 640),
      daysInCompany: 362,
      doneProjects: 12,
      salaryMinor: 485000,
      salaryCurrency: 'USD',
    },
    team: {
      name: 'Capture IT',
      department: 'Developers',
      memberCount: 15,
      // 640, not 160: the selected member's photo fills a 560 px card, and Next/Image scales the
      // same source down for the 40 px avatars rather than the other way around.
      members: [
        { id: 1, name: 'Ava Mitchell', photoUrl: photo('photo-1494790108377-be9c29b29330', 640) },
        { id: 2, name: 'Mia Fenwick', photoUrl: photo('photo-1438761681033-6461ffad8d80', 640) },
        { id: 3, name: 'Milena Page', photoUrl: photo('photo-1544005313-94ddf0286df2', 640) },
        { id: 4, name: 'Zoe Harding', photoUrl: photo('photo-1534528741775-53994a69daeb', 640) },
        { id: 5, name: 'Leo Vasquez', photoUrl: photo('photo-1500648767791-00dcc994a43e', 640) },
      ],
    },
    timeEntry: { id: 't1', project: 'Banking app', seconds: 13072, running: true },
    trackedTasks: [
      { id: 'k1', title: 'Build responsive layout', seconds: 7207, icon: 'gear' },
      { id: 'k2', title: 'Debug API integration', seconds: 4377, icon: 'nodes' },
      { id: 'k3', title: 'Build responsive layout', seconds: 3600, icon: 'gear' },
    ],
    workingFormat: { totalDays: 418, officePct: 55, hybridPct: 35, remotePct: 10 },
    workActivity: { hourLabels, dayLabels, cells, totalHours: 120, averagePct: 79 },
    apps: [
      { id: 'a1', name: 'VS Code', seconds: 151207, pct: 35, icon: 'vscode' },
      { id: 'a2', name: 'Figma', seconds: 108000, pct: 25, icon: 'figma' },
      { id: 'a3', name: 'Chrome DevTools', seconds: 77767, pct: 18, icon: 'chrome' },
      { id: 'a4', name: 'GitHub', seconds: 51845, pct: 12, icon: 'github' },
      { id: 'a5', name: 'ChatGPT', seconds: 43441, pct: 10, icon: 'chatgpt' },
    ],
    tasks: [
      {
        id: 's1',
        title: 'Team Sync',
        subtitle: 'Check-in with team.',
        dayIndex: 1,
        startHour: 13,
        endHour: 14,
        attendees: [
          photo('photo-1494790108377-be9c29b29330', 64),
          photo('photo-1438761681033-6461ffad8d80', 64),
          photo('photo-1500648767791-00dcc994a43e', 64),
          photo('photo-1534528741775-53994a69daeb', 64),
          photo('photo-1544005313-94ddf0286df2', 64),
        ],
      },
      {
        id: 's2',
        title: 'Component Review',
        subtitle: 'Refactor shared components.',
        dayIndex: 3,
        startHour: 14.6,
        endHour: 15.6,
        attendees: [
          photo('photo-1500648767791-00dcc994a43e', 64),
          photo('photo-1534528741775-53994a69daeb', 64),
        ],
        highlighted: true,
      },
      {
        id: 's3',
        title: 'Bug Reproduction',
        subtitle: 'Find and log UI bugs.',
        dayIndex: 5,
        startHour: 16.1,
        endHour: 17.1,
        attendees: [photo('photo-1544005313-94ddf0286df2', 64)],
      },
    ],
    viewer: {
      name: 'Eatzify Admin',
      role: 'Operations',
      photoUrl: photo('photo-1500648767791-00dcc994a43e', 96),
    },
    weather: { tempC: 27 },
  };
}

/// docs/10 §1's two admin roles, in words. The top bar saying who you are is not decoration on an
/// audited surface: every read from this dashboard now lands in the log under THIS name (D-234).
const ROLE_LABEL: Record<number, string> = { 1: 'Admin', 8: 'Super admin' };

export async function getDashboardData(): Promise<DashboardData> {
  const [overview, session] = await Promise.all([fetchOverview(), readSession()]);
  const rest = placeholder();

  return {
    overview,
    ...rest,
    viewer: session
      ? {
          ...rest.viewer,
          name: session.viewer.name,
          role: ROLE_LABEL[session.viewer.roleId] ?? 'Admin',
        }
      : rest.viewer,
  };
}
