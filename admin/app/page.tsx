import { DashboardShell } from '@/components/DashboardShell';
import { getDashboardData } from '@/lib/data';

/**
 * Server component: fetch once, render HTML, hand it to the shell.
 *
 * Full-bleed. The reference floats the app in a pale margin, which photographs well and throws away
 * a band of every edge on a real monitor. Nothing here sets a page padding or a max width — the
 * shell is the viewport.
 */
export default async function DashboardPage() {
  const data = await getDashboardData();
  return <DashboardShell data={data} />;
}
