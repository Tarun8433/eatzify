import type { Config } from 'tailwindcss';

/**
 * Tokens read off the reference. Named by ROLE, not by colour — `surface` rather than `grey900` —
 * so a later palette change is one edit here instead of a hunt through every component.
 *
 * The palette is two families and nothing else: a near-black stack for the shell and its cards, and
 * one mint accent that earns attention by being the only saturated thing on the page. Everything
 * highlighted in the reference — the running timer, the premium card, today's column, a filled
 * activity cell — is that same mint. Adding a second accent would break what makes it readable.
 */
const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        /// The page behind the shell — the pale sage the reference floats the app on.
        canvas: '#dde8e3',
        /// The application shell itself.
        shell: '#0b0b0b',
        /// The rail of icons down the left, a shade off the shell so it reads as a separate plane.
        rail: '#121212',
        /// A card on the shell.
        surface: '#1b1b1b',
        /// A raised element inside a card — a row, a chip, the search field.
        raised: '#262626',
        /// A hairline. Borders in this design are barely there; the separation is tonal.
        line: '#2e2e2e',
        ink: {
          /// Headline and figures.
          DEFAULT: '#ffffff',
          /// Labels and captions.
          muted: '#8c8c8c',
          /// Dimmest — axis ticks, disabled.
          faint: '#5c5c5c',
        },
        mint: {
          /// The accent surface: timer card, premium card, today.
          DEFAULT: '#c2ebe1',
          /// A filled activity cell — brighter, because it sits on near-black at small size.
          bright: '#d9f3ec',
          /// The far end of the donut gradient.
          deep: '#7fd7e3',
          /// Text ON mint.
          ink: '#0b2b26',
        },
      },
      borderRadius: {
        /// The shell's own corner.
        shell: '22px',
        /// A card. The reference is consistent about this, which is most of why it reads as a set.
        card: '18px',
        /// A row or chip inside a card.
        tile: '12px',
      },
      fontFamily: {
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
      },
      fontSize: {
        /// The figures the cards are built around — 362, 418, $4,850.
        figure: ['42px', { lineHeight: '1', letterSpacing: '-0.02em' }],
        /// The running timer, which is the largest thing in its card.
        timer: ['32px', { lineHeight: '1', letterSpacing: '-0.01em' }],
      },
    },
  },
  plugins: [],
};

export default config;
