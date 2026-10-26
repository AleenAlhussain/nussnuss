'use client';

import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

/** Settings became the You tab; old links and bookmarks land there. */
export default function SettingsMoved() {
  const router = useRouter();
  useEffect(() => router.replace('/you'), [router]);
  return null;
}
