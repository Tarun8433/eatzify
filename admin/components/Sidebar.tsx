"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { NavKey } from "@/lib/nav";

import {
  BellIcon,
  BoltIcon,
  BriefcaseIcon,
  CalendarIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  ChartIcon,
  CheckIcon,
  DollarIcon,
  DownloadIcon,
  GridIcon,
  RefreshIcon,
  ChatIcon,
  GearPathIcon,
  InboxIcon,
  LogoutIcon,
  NodesIcon,
  PeopleIcon,
  PlusIcon,
  SearchIcon,
  SettingsIcon,
  UserCogIcon,
} from "./icons";

/**
 * Every destination this dashboard has, in the order the work happens: people first, the queues
 * that have somebody waiting at the other end next, then the tools nobody touches most days.
 *
 * The reference design's Calendar, Payroll, Inbox, Messages and Automations are gone (D-232). They
 * were placeholders from a template for a different product, and an operations tool whose rail is
 * half fiction teaches people to distrust the half that works.
 */
const NAV = [
  { key: "dashboard", label: "Dashboard", Icon: GridIcon, enabled: true },
  { key: "users", label: "Users", Icon: PeopleIcon, enabled: true },
  {
    key: "verification",
    label: "Verification",
    Icon: CheckIcon,
    enabled: true,
  },
  { key: "payments", label: "Payments", Icon: DollarIcon, enabled: true },
  {
    key: "refunds",
    label: "Refund requests",
    Icon: RefreshIcon,
    enabled: true,
  },
  {
    key: "partners",
    label: "Partner applications",
    Icon: BriefcaseIcon,
    enabled: true,
  },
  { key: "people", label: "Clients", Icon: CalendarIcon, enabled: true },
  { key: "search", label: "Find someone", Icon: SearchIcon, enabled: true },
  { key: "tickets", label: "Support", Icon: ChatIcon, enabled: true },
  { key: "foods", label: "Food review", Icon: InboxIcon, enabled: true },
  { key: "recipes", label: "Recipes", Icon: PlusIcon, enabled: true },
  { key: "messages", label: "Messages", Icon: BellIcon, enabled: true },
  {
    key: "broadcast",
    label: "Message by health condition",
    Icon: ChatIcon,
    enabled: true,
  },
  {
    key: "announcements",
    label: "Announcements",
    Icon: InboxIcon,
    enabled: true,
  },
  { key: "offers", label: "Offers", Icon: PlusIcon, enabled: true },
  { key: "metrics", label: "Live metrics", Icon: ChartIcon, enabled: true },
  { key: "reports", label: "Reports", Icon: DownloadIcon, enabled: true },
  { key: "analytics", label: "Analytics", Icon: ChartIcon, enabled: true },
  { key: "audit", label: "Audit log", Icon: NodesIcon, enabled: true },
  { key: "staff", label: "Admins & roles", Icon: UserCogIcon, enabled: true },
  { key: "rulepacks", label: "Rule packs", Icon: BoltIcon, enabled: true },
  {
    key: "scanning",
    label: "Meal scanning",
    Icon: SettingsIcon,
    enabled: true,
  },
  { key: "security", label: "Security", Icon: GearPathIcon, enabled: true },
] as const;

export type { NavKey };

/// Ends the session on the API as well as in this browser, then lands on the login page. It was a
/// button with no handler until D-234 — there was nothing to log out of, because there was no
/// login.
function LogOutButton({ expanded }: { expanded: boolean }) {
  const router = useRouter();

  async function out() {
    await fetch("/api/session", { method: "DELETE" });
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      type="button"
      onClick={() => void out()}
      aria-label="Log out"
      title={expanded ? undefined : "Log out"}
      className={`${itemShape(expanded)} text-ink-faint transition-colors hover:text-ink-muted`}
    >
      <LogoutIcon className="h-[19px] w-[19px] shrink-0" />
      {expanded && <span className="truncate text-[13px]">Log out</span>}
    </button>
  );
}

/// Whether the rail shows names beside the icons, remembered in this browser. Names by default.
const EXPANDED_KEY = "admin.sidebar.expanded";

function readExpanded(): boolean {
  try {
    return window.localStorage.getItem(EXPANDED_KEY) !== "false";
  } catch {
    return true;
  }
}

function writeExpanded(expanded: boolean) {
  try {
    window.localStorage.setItem(EXPANDED_KEY, String(expanded));
  } catch {
    // A private window or blocked storage: the choice lasts for this page only.
  }
}

/// One shape for every rail button: a square when collapsed, a full-width row with its name when
/// expanded.
function itemShape(expanded: boolean): string {
  return expanded
    ? "flex h-10 w-full items-center gap-3 rounded-tile px-3 text-left"
    : "flex h-10 w-10 items-center justify-center rounded-tile";
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
  allowed,
}: {
  active: NavKey;
  onChange: (key: NavKey) => void;
  /// What this person's role may open (`GET /admin/me`); the rest is not drawn at all.
  allowed: readonly NavKey[];
}) {
  const [expanded, setExpanded] = useState(true);
  useEffect(() => setExpanded(readExpanded()), []);
  const toggle = () => {
    setExpanded(!expanded);
    writeExpanded(!expanded);
  };

  return (
    <nav
      aria-label="Main"
      className={`relative flex shrink-0 flex-col bg-rail py-5 transition-[width] duration-200 ${
        expanded ? "w-[220px] items-stretch px-3" : "w-[62px] items-center"
      }`}
    >
      <div
        className={`mb-5 flex items-center ${expanded ? "justify-between px-1" : "flex-col gap-3"}`}
      >
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white">
          <span className="block h-4 w-4 rounded-full border-[3px] border-black" />
        </div>
        <button
          type="button"
          onClick={toggle}
          aria-label={expanded ? "Show icons only" : "Show names"}
          aria-expanded={expanded}
          title={expanded ? "Show icons only" : "Show names"}
          className="flex h-8 w-8 items-center justify-center rounded-tile text-ink-faint transition-colors hover:bg-raised/60 hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-mint"
        >
          {expanded ? (
            <ChevronLeftIcon className="h-[17px] w-[17px]" />
          ) : (
            <ChevronRightIcon className="h-[17px] w-[17px]" />
          )}
        </button>
      </div>

      <ul
        className={`flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto ${
          expanded ? "items-stretch" : "items-center"
        }`}
      >
        {NAV.filter(({ key }) => allowed.includes(key)).map(
          ({ key, label, Icon, enabled }) => {
            const isActive = key === active;
            return (
              <li key={key} className="relative">
                {isActive && (
                  <span
                    aria-hidden
                    className={`absolute top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-full bg-white ${
                      expanded ? "-left-[12px]" : "-left-[13px]"
                    }`}
                  />
                )}
                <button
                  type="button"
                  onClick={() => enabled && onChange(key)}
                  disabled={!enabled}
                  aria-label={label}
                  aria-current={isActive ? "page" : undefined}
                  title={expanded ? undefined : label}
                  className={`group ${itemShape(expanded)} transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-mint ${
                    isActive
                      ? "bg-raised text-ink"
                      : enabled
                        ? "text-ink-faint hover:bg-raised/60 hover:text-ink"
                        : "cursor-not-allowed text-ink-faint/40"
                  }`}
                >
                  <Icon className="h-[19px] w-[19px] shrink-0" />
                  {expanded && (
                    <span className="truncate text-[13px]">{label}</span>
                  )}
                </button>
              </li>
            );
          },
        )}
      </ul>

      <div
        className={`mt-3 flex flex-col gap-1 ${expanded ? "items-stretch" : "items-center"}`}
      >
        {/* Settings goes to the one screen that IS settings for this dashboard: the authenticator
            that guards the dangerous actions. It used to be a button that did nothing. */}
        <button
          type="button"
          onClick={() => onChange("security")}
          aria-label="Security settings"
          title={expanded ? undefined : "Security settings"}
          className={`${itemShape(expanded)} text-ink-faint transition-colors hover:text-ink-muted`}
        >
          <SettingsIcon className="h-[19px] w-[19px] shrink-0" />
          {expanded && (
            <span className="truncate text-[13px]">Security settings</span>
          )}
        </button>
        <LogOutButton expanded={expanded} />
      </div>
    </nav>
  );
}
