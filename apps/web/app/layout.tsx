import '@nussnuss/tokens/tokens.css';
import './globals.css';
import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { SessionProvider } from '@/lib/session';
import { ToastProvider } from '@/components/toast';

export const metadata: Metadata = {
  title: 'NussNuss',
  description: 'Split bills with friends. No limits, no ads. Arabic and English.',
  applicationName: 'NussNuss',
  appleWebApp: { capable: true, title: 'NussNuss', statusBarStyle: 'default' },
  icons: { icon: '/icon.svg' },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#F2F1F7' },
    { media: '(prefers-color-scheme: dark)', color: '#000000' },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <body>
        <SessionProvider>
          <ToastProvider>{children}</ToastProvider>
        </SessionProvider>
      </body>
    </html>
  );
}
