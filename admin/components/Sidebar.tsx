'use client';

import { useRouter } from 'next/navigation';

import {
  BellIcon,
  BoltIcon,
  BriefcaseIcon,
  ChartIcon,
  ChatIcon,
  GearPathIcon,
  InboxIcon,
  LogoutIcon,
  NodesIcon,
  PeopleIcon,
  SearchIcon,
  SettingsIcon,
} from './icons';

/**
 * Every destination this dashboard has, in the order the work happens: people first, the queues
 * that have somebody waiting at the other end next, then the tools nobody touches most days.
 *
 * The reference design's Calendar, Payroll, Inbox, Messages and Automations are gone (D-232). They
 * were placeholders from a template for a different product, and an operations tool whose rail is
 * half fiction teaches people to distrust the half that works.
 */
const NAV = [
  { key: 'partners', label: 'Partner applications', Icon: BriefcaseIcon, enabled: true },
  { key: 'people', label: 'Clients', Icon: PeopleIcon, enabled: true },
  { key: 'search', label: 'Find someone', Icon: SearchIcon, enabled: true },
  { key: 'tickets', label: 'Support', Icon: ChatIcon, enabled: true },
  { key: 'foods', label: 'Food review', Icon: InboxIcon, enabled: true },
  { key: 'broadcast', label: 'Send a message', Icon: BellIcon, enabled: true },
  { key: 'metrics', label: 'Live metrics', Icon: ChartIcon, enabled: true },
  { key: 'audit', label: 'Audit log', Icon: NodesIcon, enabled: true },
  { key: 'rulepacks', label: 'Rule packs', Icon: BoltIcon, enabled: true },
  { key: 'scanning', label: 'Meal scanning', Icon: SettingsIcon, enabled: true },
  { key: 'security', label: 'Security', Icon: GearPathIcon, enabled: true },
] as const;

export type NavKey = (typeof NAV)[number]['key'];

/// Ends the session on the API as well as in this browser, then lands on the login page. It was a
/// button with no handler until D-234 — there was nothing to log out of, because there was no
/// login.
function LogOutButton() {
  const router = useRouter();

  async function out() {
    await fetch('/api/session', { method: 'DELETE' });
    router.push('/login');
    router.refresh();
  }

  return (
    <button
      type="button"
      onClick={() => void out()}
      aria-label="Log out"
      title="Log out"
      className="flex h-10 w-10 items-center justify-center rounded-tile text-ink-faint transition-colors hover:text-ink-muted"
    >
      <LogoutIcon className="h-[19px] w-[19px]" />
    </button>
  );
}

/**
 * The icon rail.
 *
 * The active item is marked by a bar on the SHELL's edge, outside the rail, exactly as the reference
 * does it — a filled pill behind the icon would compete with the mint accent that the rest of the
 * page reserves for live data.
 *
 * Every icon-only control carries an `aria-label` and a tooltip: a rail of unlabelled glyphs is
 * unusable with a screen reader and merely guessable without one.
 */
export function Sidebar({
  active,
  onChange,
}: {
  active: NavKey;
  onChange: (key: NavKey) => void;
}) {
  return (
    <nav
      aria-label="Main"
      className="relative flex w-[62px] shrink-0 flex-col items-center bg-rail py-5"
    >
      <div className="mb-7 flex h-9 w-9 items-center justify-center rounded-full bg-white">
        <span className="block h-4 w-4 rounded-full border-[3px] border-black" />
      </div>

      <ul className="flex flex-1 flex-col items-center gap-1">
        {NAV.map(({ key, label, Icon, enabled }) => {
          const isActive = key === active;
          return (
            <li key={key} className="relative">
              {isActive && (
                <span
                  aria-hidden
                  className="absolute -left-[13px] top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-full bg-white"
                />
              )}
              <button
                type="button"
                onClick={() => enabled && onChange(key)}
                disabled={!enabled}
                aria-label={label}
                aria-current={isActive ? 'page' : undefined}
                title={label}
                className={`group flex h-10 w-10 items-center justify-center rounded-tile transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-mint ${
                  isActive
                    ? 'bg-raised text-ink'
                    : enabled
                      ? 'text-ink-faint hover:bg-raised/60 hover:text-ink'
                      : 'cursor-not-allowed text-ink-faint/40'
                }`}
              >
                <Icon className="h-[19px] w-[19px]" />
              </button>
            </li>
          );
        })}
      </ul>

      <div className="flex flex-col items-center gap-1">
        {/* Settings goes to the one screen that IS settings for this dashboard: the authenticator
            that guards the dangerous actions. It used to be a button that did nothing. */}
        <button
          type="button"
          onClick={() => onChange('security')}
          aria-label="Security settings"
          title="Security settings"
          className="flex h-10 w-10 items-center justify-center rounded-tile text-ink-faint transition-colors hover:text-ink-muted"
        >
          <SettingsIcon className="h-[19px] w-[19px]" />
        </button>
        <LogOutButton />
      </div>
    </nav>
  );
}
