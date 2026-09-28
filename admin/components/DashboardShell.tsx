'use client';

import { useState } from 'react';
import type { DashboardData } from '@/lib/types';
import { longDate } from '@/lib/format';
import { Sidebar, type NavKey } from './Sidebar';
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

// 18 Sep 2024 is a Wednesday, which is what the reference shows; the same date in 2026 is a Friday.
const REFERENCE_DAY = new Date('2024-09-18T09:00:00Z');

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
function View({ nav, overview }: { nav: NavKey; overview: DashboardData['overview'] }) {
  switch (nav) {
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
    default:
      return <MetricsView overview={overview} />;
  }
}

export function DashboardShell({ data }: { data: DashboardData }) {
  const [nav, setNav] = useState<NavKey>('people');
  const [query, setQuery] = useState('');

  return (
    <div className="flex h-screen w-full overflow-hidden bg-shell">
      <Sidebar active={nav} onChange={setNav} />

      <div className="flex min-w-0 flex-1 flex-col px-5 pb-4">
        <TopBar
          viewer={data.viewer}
          tempC={data.weather.tempC}
          today={longDate(REFERENCE_DAY)}
          query={query}
          onQueryChange={setQuery}
        />

        {/* Clients paints its own scroll container; everything else sits in the standard one. */}
        {nav === 'people' ? (
          <ClientsView />
        ) : (
          <div className="flex min-h-0 flex-1 flex-col pt-3">
            <View nav={nav} overview={data.overview} />
          </div>
        )}
      </div>
    </div>
  );
}
