'use client';

import { LegalPage } from '@/components/legal-page';
import { terms } from '@/lib/legal';

export default function Terms() {
  return <LegalPage doc={terms} testId="terms" />;
}
