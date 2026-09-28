import type { AppUsage } from '@/lib/types';
import { hms, ringDash } from '@/lib/format';

/**
 * Brand marks, drawn rather than fetched.
 *
 * Five remote images for five 22px logos would be five requests, five CORS surfaces and five things
 * that break when a CDN moves. These are simplified marks in the product's own colour — recognisable
 * at the size they are actually rendered.
 */
function AppMark({ icon }: { icon: AppUsage['icon'] }) {
  switch (icon) {
    case 'vscode':
      return (
        <svg viewBox="0 0 24 24" className="h-[19px] w-[19px]" aria-hidden>
          <path d="M17.8 2.2 9.6 10 5.4 6.8 3 8l3.6 4L3 16l2.4 1.2 4.2-3.2 8.2 7.8L22 20V4l-4.2-1.8Zm.6 5.1v9.4L13 12l5.4-4.7Z" fill="#3aa0e3" />
        </svg>
      );
    case 'figma':
      return (
        <svg viewBox="0 0 24 24" className="h-[19px] w-[19px]" aria-hidden>
          <path d="M8.8 2h3.2v4H8.8a2 2 0 1 1 0-4Z" fill="#f24e1e" />
          <path d="M12 2h3.2a2 2 0 1 1 0 4H12V2Z" fill="#ff7262" />
          <path d="M12 6h3.2a2 2 0 1 1 0 4H12V6Z" fill="#a259ff" />
          <path d="M8.8 6H12v4H8.8a2 2 0 1 1 0-4Z" fill="#1abcfe" />
          <path d="M8.8 10H12v2a2 2 0 1 1-3.2-2Z" fill="#0acf83" />
        </svg>
      );
    case 'chrome':
      return (
        <svg viewBox="0 0 24 24" className="h-[19px] w-[19px]" aria-hidden>
          <circle cx="12" cy="12" r="10" fill="#fff" />
          <path d="M12 2a10 10 0 0 1 8.7 5H12a5 5 0 0 0-4.5 2.8L3.9 5.6A10 10 0 0 1 12 2Z" fill="#ea4335" />
          <path d="M3.9 5.6 7.5 9.8A5 5 0 0 0 9.8 16l-3.5 5.1A10 10 0 0 1 3.9 5.6Z" fill="#34a853" />
          <path d="M20.7 7A10 10 0 0 1 6.3 21.1L9.8 16a5 5 0 0 0 6.8-2.6 5 5 0 0 0 .1-3.6l4-2.8Z" fill="#fbbc05" />
          <circle cx="12" cy="12" r="4" fill="#4285f4" />
        </svg>
      );
    case 'github':
      return (
        <svg viewBox="0 0 24 24" className="h-[19px] w-[19px]" aria-hidden>
          <path
            fill="#fff"
            d="M12 2a10 10 0 0 0-3.2 19.5c.5.1.7-.2.7-.5v-1.7c-2.8.6-3.4-1.3-3.4-1.3-.4-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.6-1.4-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.7 1a9.4 9.4 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .5 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.4 4.7-4.6 5 .4.3.7 1 .7 1.9v2.8c0 .3.2.6.7.5A10 10 0 0 0 12 2Z"
          />
        </svg>
      );
    case 'chatgpt':
      return (
        <svg viewBox="0 0 24 24" className="h-[19px] w-[19px]" aria-hidden>
          <circle cx="12" cy="12" r="10" fill="#fff" />
          <path
            fill="#0b0b0b"
            d="M12 5.5a3.4 3.4 0 0 1 3 1.8 3.4 3.4 0 0 1 2.3 5 3.4 3.4 0 0 1-3 5 3.4 3.4 0 0 1-5.9 0 3.4 3.4 0 0 1-3-5 3.4 3.4 0 0 1 2.3-5 3.4 3.4 0 0 1 4.3-1.8Zm0 2.1-3 1.7v3.4l3 1.7 3-1.7V9.3l-3-1.7Z"
          />
        </svg>
      );
  }
}

/**
 * Which applications the employee used and for how long.
 *
 * This widget displays workplace monitoring data. The entity behind it does not exist and should not
 * be built without a consent and purpose-limitation decision first — see the note on `AppUsage` in
 * `lib/types.ts` and D-182.
 */
export function AppsUrls({ apps }: { apps: AppUsage[] }) {
  return (
    <section className="card p-4" aria-labelledby="apps-urls-heading">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h2 id="apps-urls-heading" className="text-[14.5px] font-medium text-ink">
            Apps &amp; URLs
          </h2>
          <span className="rounded-full bg-raised px-2 py-[2px] text-[11px] text-ink-muted">
            {apps.length * 3}
          </span>
        </div>
        <button type="button" className="card-menu" aria-label="Apps and URLs options">
          •••
        </button>
      </div>

      <ul className="mt-1.5">
        {apps.map((app, i) => {
          const { dash, gap } = ringDash(app.pct, 14);
          return (
            <li
              key={app.id}
              className={`flex items-center gap-3 py-[11px] ${i > 0 ? 'border-t border-line' : ''}`}
            >
              <span className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-[11px] bg-raised">
                <AppMark icon={app.icon} />
              </span>

              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] font-medium text-ink">{app.name}</span>
                <span className="block text-[11.5px] tabular-nums text-ink-muted">
                  {hms(app.seconds)}
                </span>
              </span>

              {/* The percentage sits inside its own ring — the figure and its bar in one mark. */}
              <span className="relative flex h-[38px] w-[38px] shrink-0 items-center justify-center">
                <svg viewBox="0 0 32 32" className="absolute inset-0 h-full w-full -rotate-90">
                  <circle cx="16" cy="16" r="14" fill="none" stroke="#2e2e2e" strokeWidth="2.2" />
                  <circle
                    cx="16"
                    cy="16"
                    r="14"
                    fill="none"
                    stroke="#ffffff"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    strokeDasharray={`${dash} ${gap}`}
                  />
                </svg>
                <span className="text-[10px] font-medium tabular-nums text-ink">{app.pct}%</span>
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
