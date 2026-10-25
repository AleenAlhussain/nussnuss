'use client';

import { LegalPage } from '@/components/legal-page';
import { privacy } from '@/lib/legal';

export default function Privacy() {
  return <LegalPage doc={privacy} testId="privacy" />;
}
