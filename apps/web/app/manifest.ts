import type { MetadataRoute } from 'next';

/** Lets phones install NussNuss from the browser, with its own icon and no browser bars. */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'NussNuss · نص نص',
    short_name: 'NussNuss',
    description: 'Split bills with friends. Free, no limits, no ads. Arabic and English.',
    start_url: '/',
    scope: '/',
    display: 'standalone',
    orientation: 'portrait',
    background_color: '#0D0A1C',
    theme_color: '#5B47E0',
    lang: 'en',
    dir: 'auto',
    categories: ['finance', 'lifestyle', 'travel'],
    // Press and hold the home-screen icon: add an expense to the group used last, or see what's new.
    shortcuts: [
      { name: 'Add expense', short_name: 'Add', url: '/?add=1', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
      { name: 'Activity', short_name: 'Activity', url: '/activity', icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }] },
    ],
    icons: [
      { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
  };
}
