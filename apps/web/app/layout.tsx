import '@nussnuss/tokens/tokens.css';
import './globals.css';
import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { SessionProvider } from '@/lib/session';
import { ToastProvider } from '@/components/toast';
import { AppAgent } from '@/components/app-agent';
import { PaywallProvider } from '@/components/paywall';

export const metadata: Metadata = {
  title: 'NussNuss',
  description: 'Split bills with friends. No limits, no ads. Arabic and English.',
  applicationName: 'NussNuss',
  appleWebApp: { capable: true, title: 'NussNuss', statusBarStyle: 'default' },
  icons: { icon: '/icon.svg', apple: '/icons/apple-touch-icon.png' },
  manifest: '/manifest.webmanifest',
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#F2F1F7' },
    { media: '(prefers-color-scheme: dark)', color: '#0D0A1C' },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <body>
        <SessionProvider>
          <ToastProvider>
            <PaywallProvider>
              {children}
              <AppAgent />
            </PaywallProvider>
          </ToastProvider>
        </SessionProvider>
      </body>
    </html>
  );
}
