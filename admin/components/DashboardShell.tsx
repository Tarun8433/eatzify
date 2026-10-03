'use client';

import { useEffect, useState } from 'react';
import type { DashboardData } from '@/lib/types';
import { allowedNav, homeFor, type NavKey } from '@/lib/nav';
import { call } from '@/lib/client';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';
import { ClientsView } from './views/ClientsView';
import { PartnerReview } from './views/PartnerReview';
import { MetricsView } from './views/MetricsView';
import { UserSearchView } from './views/UserSearchView';
import { TicketsView } from './views/TicketsView';
import { FoodReviewView } from './views/FoodReviewView';
import { BroadcastView } from './views/BroadcastView';
import { AuditView } from './views/AuditView';
import { RulePacksView } from './views/RulePacksView';
import { SecurityView } from './views/SecurityView';
import { ScanSettingsView } from './views/ScanSettingsView';
import { DashboardView } from './views/DashboardView';
import { UsersView } from './views/UsersView';
import { VerificationView } from './views/VerificationView';
import { StaffView } from './views/StaffView';
import { PaymentsView } from './views/PaymentsView';
import { MessagesView } from './views/MessagesView';
import { ReportsView } from './views/ReportsView';
import { AnalyticsView } from './views/AnalyticsView';
import { AnnouncementsView } from './views/AnnouncementsView';
import { OffersView } from './views/OffersView';
import { AlertBell, type Alert } from './AlertBell';
import { RefundsView } from './views/RefundsView';

/**
 * The application shell: chrome that never changes, and one view that does.
 *
 * Client-side, because everything the admin actually DOES lives here — which tab they are on, which
 * teammate they picked, what they typed into search. The data still arrives from a server component
 * above, so the first paint is rendered HTML rather than a spinner waiting on a fetch.
 *
 * Full-bleed: no page padding, no max width, no rounded shell. The design's floating card looks
 * right in a portfolio shot and wastes a band of every edge on a real monitor, which is the whole
 * point of an operations tool being the size of the screen it is on.
 */
/// One place that decides which view a nav key means, so adding a destination is one line in the
/// sidebar and one case here.
function View({
  nav,
  overview,
  permissions,
  go,
}: {
  nav: NavKey;
  overview: DashboardData['overview'];
  permissions: string[];
  go: (key: NavKey) => void;
}) {
  switch (nav) {
    case 'dashboard':
      return <DashboardView permissions={permissions} />;
    case 'users':
      return <UsersView permissions={permissions} />;
    case 'verification':
      return <VerificationView permissions={permissions} onOpenPartners={() => go('partners')} />;
    case 'staff':
      return <StaffView />;
    case 'reports':
      return <ReportsView />;
    case 'analytics':
      return <AnalyticsView />;
    case 'messages':
      return <MessagesView />;
    case 'announcements':
      return <AnnouncementsView />;
    case 'offers':
      return <OffersView />;
    case 'payments':
      return <PaymentsView permissions={permissions} />;
    case 'refunds':
      return <RefundsView permissions={permissions} />;
    case 'partners':
      return <PartnerReview />;
    case 'search':
      return <UserSearchView />;
    case 'tickets':
      return <TicketsView />;
    case 'foods':
      return <FoodReviewView />;
    case 'broadcast':
      return <BroadcastView />;
    case 'audit':
      return <AuditView />;
    case 'rulepacks':
      return <RulePacksView />;
    case 'security':
      return <SecurityView />;
    case 'scanning':
      return <ScanSettingsView />;
    case 'metrics':
      return <MetricsView overview={overview} />;
    default:
      return <DashboardView permissions={permissions} />;
  }
}

export function DashboardShell({ data, today }: { data: DashboardData; today: string }) {
  const [nav, setNav] = useState<NavKey>('dashboard');
  const [query, setQuery] = useState('');
  // What this person's role may open (D-260). Until it arrives only the dashboard is drawn.
  const [permissions, setPermissions] = useState<string[]>(['panel.access']);

  useEffect(() => {
    call<{ permissions: string[] }>('me')
      .then((me) => {
        setPermissions(me.permissions);
        setNav(homeFor(me.permissions));
      })
      .catch(() => undefined);
  }, []);
  const allowed = allowedNav(permissions);

  // The bell's counts, refreshed every minute while the dashboard is open.
  const [alerts, setAlerts] = useState<Alert[]>([]);
  useEffect(() => {
    const load = () => call<Alert[]>('alerts').then(setAlerts).catch(() => undefined);
    void load();
    const timer = setInterval(load, 60_000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="flex h-screen w-full overflow-hidden bg-shell">
      <Sidebar active={nav} onChange={setNav} allowed={allowed} />

      <div className="flex min-w-0 flex-1 flex-col px-5 pb-4">
        <TopBar
          viewer={data.viewer}
          today={today}
          bell={<AlertBell alerts={alerts} onGo={setNav} />}
          query={query}
          onQueryChange={setQuery}
        />

        {/* Clients paints its own scroll container; everything else sits in the standard one. */}
        {nav === 'people' ? (
          <ClientsView />
        ) : (
          <div className="flex min-h-0 flex-1 flex-col pt-3">
            <View nav={nav} overview={data.overview} permissions={permissions} go={setNav} />
          </div>
        )}
      </div>
    </div>
  );
}
