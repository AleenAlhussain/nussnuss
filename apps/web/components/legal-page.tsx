'use client';

import type { LegalDoc } from '@/lib/legal';
import { useSession } from '@/lib/session';
import { Screen } from './glass';

export function LegalPage({ doc, testId }: { doc: Record<'en' | 'ar', LegalDoc>; testId: string }) {
  const { prefs, me } = useSession();
  const d = doc[prefs.lang];
  return (
    <Screen title={d.title} back={me ? '/settings' : '/'} tabs={!!me} testId={testId}>
      <article className="flex max-w-prose flex-col gap-6 pb-8">
        <p className="t-footnote text-text-2">{d.updated}</p>
        <p className="t-body text-text">{d.intro}</p>
        {d.sections.map((s) => (
          <section key={s.h} className="flex flex-col gap-2">
            <h2 className="t-title-3 text-text">{s.h}</h2>
            {s.p.map((p) => (
              <p key={p.slice(0, 40)} className="t-body text-text-2">
                {p}
              </p>
            ))}
          </section>
        ))}
      </article>
    </Screen>
  );
}
