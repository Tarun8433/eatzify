import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';

// Self-hosted by `next/font` at build time, so the page does not depend on a Google Fonts request
// it cannot control — and there is no flash of fallback text on first paint.
const inter = Inter({
  subsets: ['latin'],
  variable: '--font-sans',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Eatzify Admin',
  description: 'Clients, diaries, partner review and live metrics.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="font-sans antialiased">{children}</body>
    </html>
  );
}
