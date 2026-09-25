import type { ReactElement, SVGProps } from 'react';

/**
 * The icon set, hand-written.
 *
 * A library would be a dependency and a bundle for what amounts to twenty short paths, and the
 * reference's icons are a consistent 1.5px outline set that no off-the-shelf pack matches exactly.
 * These inherit `currentColor` and size from the `className`, so one component styles them all.
 */
// `ReactElement`, not `JSX.Element`: React 19 removed the global JSX namespace.
type Icon = (props: SVGProps<SVGSVGElement>) => ReactElement;

const base = {
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.6,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  viewBox: '0 0 24 24',
};

export const BriefcaseIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="7" width="18" height="13" rx="2.5" />
    <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7" />
  </svg>
);

export const PeopleIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <circle cx="9" cy="8" r="3.2" />
    <path d="M3 19.5c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5" />
    <path d="M16 5.5a3 3 0 0 1 0 5.8M17.5 19.5c0-2.3-.8-4-2-5.1" />
  </svg>
);

export const CalendarIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="5" width="18" height="16" rx="2.5" />
    <path d="M3 10h18M8 3v4M16 3v4" />
  </svg>
);

export const DollarIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="4" width="18" height="16" rx="4" />
    <path d="M12 8v8M14 10c0-.9-.9-1.5-2-1.5s-2 .6-2 1.5.9 1.3 2 1.5 2 .6 2 1.5-.9 1.5-2 1.5-2-.6-2-1.5" />
  </svg>
);

export const ChartIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="4" width="18" height="16" rx="4" />
    <path d="M7 14.5 10.5 11l2.5 2.5L17 9" />
  </svg>
);

export const InboxIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="5" width="18" height="14" rx="3" />
    <path d="M3 13h5l1.5 2.5h5L16 13h5" />
  </svg>
);

export const ChatIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M20 12.5c0 3.8-3.6 6.9-8 6.9a9 9 0 0 1-2.4-.3L5 21l1-3.4A6.6 6.6 0 0 1 4 12.5c0-3.8 3.6-6.9 8-6.9s8 3.1 8 6.9Z" />
  </svg>
);

export const BoltIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M13 3 5.5 13.2h5.2L10 21l7.6-10.2h-5.3L13 3Z" />
  </svg>
);

export const SettingsIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 14.2a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5v.2a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3h.1a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8v.1a1.6 1.6 0 0 0 1.5 1h.2a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1Z" />
  </svg>
);

export const LogoutIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M15 4h2.5A2.5 2.5 0 0 1 20 6.5v11a2.5 2.5 0 0 1-2.5 2.5H15" />
    <path d="M10 8l-4 4 4 4M6 12h10" />
  </svg>
);

export const SearchIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <circle cx="11" cy="11" r="6.5" />
    <path d="m16 16 4 4" />
  </svg>
);

export const FilterIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M4 8h10M18 8h2M4 16h4M12 16h8" />
    <circle cx="16" cy="8" r="2" />
    <circle cx="10" cy="16" r="2" />
  </svg>
);

export const BellIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M18 15.5V11a6 6 0 1 0-12 0v4.5L4.5 17.5h15L18 15.5Z" />
    <path d="M10 20.5a2.2 2.2 0 0 0 4 0" />
  </svg>
);

export const ChevronLeftIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="m14 6-6 6 6 6" />
  </svg>
);

export const ChevronRightIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="m10 6 6 6-6 6" />
  </svg>
);

export const ChevronDownIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="m6 9.5 6 6 6-6" />
  </svg>
);

export const PlusIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M12 5v14M5 12h14" />
  </svg>
);

export const PhoneIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M7 3.5c.8 0 1.4.5 1.6 1.2l.7 2.4a1.7 1.7 0 0 1-.5 1.8l-1 .9a12 12 0 0 0 4.4 4.4l.9-1a1.7 1.7 0 0 1 1.8-.5l2.4.7c.7.2 1.2.9 1.2 1.6V18a2.5 2.5 0 0 1-2.7 2.5A16.5 16.5 0 0 1 3.5 6.2 2.5 2.5 0 0 1 6 3.5h1Z" />
  </svg>
);

export const MailIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="5" width="18" height="14" rx="3" />
    <path d="m4 8 7.1 4.7a1.6 1.6 0 0 0 1.8 0L20 8" />
  </svg>
);

export const PlayIcon: Icon = (p) => (
  <svg {...p} viewBox="0 0 24 24" fill="currentColor">
    <path d="M9 6.5v11a.8.8 0 0 0 1.2.7l8.4-5.5a.8.8 0 0 0 0-1.4l-8.4-5.5A.8.8 0 0 0 9 6.5Z" />
  </svg>
);

export const DownloadIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 8v7m0 0-2.8-2.8M12 15l2.8-2.8" />
  </svg>
);

export const ArrowRightIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M5 12h13m0 0-5-5m5 5-5 5" />
  </svg>
);

export const SunIcon: Icon = (p) => (
  <svg {...p} viewBox="0 0 24 24" fill="none">
    <circle cx="12" cy="12" r="4.2" fill="#f5c542" />
    <g stroke="#f5c542" strokeWidth="1.7" strokeLinecap="round">
      <path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4" />
    </g>
  </svg>
);

/// The task glyphs in the time-tracking list — two different shapes so the rows are distinguishable
/// at a glance rather than being one repeated icon.
export const NodesIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <circle cx="6" cy="12" r="2.2" />
    <circle cx="17" cy="6.5" r="2.2" />
    <circle cx="17" cy="17.5" r="2.2" />
    <path d="m8.1 11 6.8-3.4M8.1 13l6.8 3.4" />
  </svg>
);

export const GearPathIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="3.4" />
    <path d="M12 4.5v2M12 17.5v2M4.5 12h2M17.5 12h2M6.7 6.7l1.4 1.4M15.9 15.9l1.4 1.4M17.3 6.7l-1.4 1.4M8.1 15.9l-1.4 1.4" />
  </svg>
);

/// Added for the interactive surfaces: confirm, dismiss, reload, and the busy state that replaces a
/// button's own icon while a request is in flight.
export const CheckIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="m5 12.5 4.5 4.5L19 7.5" />
  </svg>
);

export const CloseIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M6 6l12 12M18 6 6 18" />
  </svg>
);

export const RefreshIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M20 11a8 8 0 1 0-.7 4.5" />
    <path d="M20 5v6h-6" />
  </svg>
);

export const SpinnerIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <path d="M12 3a9 9 0 1 0 9 9" />
  </svg>
);

export const GridIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3.5" y="3.5" width="7" height="7" rx="2" />
    <rect x="13.5" y="3.5" width="7" height="7" rx="2" />
    <rect x="3.5" y="13.5" width="7" height="7" rx="2" />
    <rect x="13.5" y="13.5" width="7" height="7" rx="2" />
  </svg>
);

/// WhatsApp's mark, drawn rather than fetched — one glyph is not worth a request, a CORS surface
/// and a dependency on someone else's CDN staying put.
export const WhatsAppIcon: Icon = (p) => (
  <svg {...p} viewBox="0 0 24 24" fill="currentColor">
    <path d="M12.04 2a9.9 9.9 0 0 0-8.5 14.9L2 22l5.25-1.38A9.9 9.9 0 1 0 12.04 2Zm0 1.8a8.1 8.1 0 1 1-4.1 15.08l-.3-.17-3.12.82.83-3.04-.19-.31A8.1 8.1 0 0 1 12.04 3.8Zm4.66 10.2c-.25-.13-1.47-.73-1.7-.81-.23-.09-.4-.13-.56.12-.17.25-.65.8-.8.97-.14.16-.29.18-.54.06a6.6 6.6 0 0 1-3.3-2.88c-.25-.43.25-.4.71-1.33.08-.16.04-.3-.02-.42-.06-.13-.56-1.35-.77-1.84-.2-.48-.4-.42-.56-.42h-.47c-.16 0-.42.06-.64.3-.22.25-.84.82-.84 2s.86 2.32.98 2.48c.13.17 1.7 2.6 4.12 3.64 1.53.66 2.13.72 2.9.6.46-.06 1.47-.6 1.68-1.18.2-.58.2-1.08.14-1.18-.06-.11-.23-.17-.48-.29Z" />
  </svg>
);

export const CopyIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="9" y="9" width="11" height="11" rx="2.5" />
    <path d="M6 15H5.5A1.5 1.5 0 0 1 4 13.5v-8A1.5 1.5 0 0 1 5.5 4h8A1.5 1.5 0 0 1 15 5.5V6" />
  </svg>
);

/// Save to the address book — a contact card with a plus.
export const SaveContactIcon: Icon = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="4.5" width="18" height="15" rx="3" />
    <circle cx="9.5" cy="10.5" r="2.2" />
    <path d="M6 16.5c0-1.7 1.6-2.8 3.5-2.8s3.5 1.1 3.5 2.8" />
    <path d="M16.5 9.5v4M14.5 11.5h4" />
  </svg>
);
