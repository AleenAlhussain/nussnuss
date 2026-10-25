'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Screen, Sheet } from '@/components/glass';
import { Button, Section, Segmented } from '@/components/ui';
import type { Lang } from '@/lib/i18n';
import { useSession, type GlassPref, type ThemePref } from '@/lib/session';

export default function SettingsPage() {
  const { ready, me, prefs, setPrefs, t, deleteAccount } = useSession();
  const router = useRouter();
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    if (ready && !me) router.replace('/');
  }, [ready, me, router]);

  return (
    <Screen title={t('settings')} testId="settings">
      <Section title={t('language')}>
        <div className="p-3">
          <Segmented<Lang>
            label={t('language')}
            value={prefs.lang}
            testId="settings-lang"
            onChange={(l) => setPrefs({ lang: l })}
            options={[
              { key: 'en', label: 'English' },
              { key: 'ar', label: 'العربية' },
            ]}
          />
        </div>
      </Section>
      <Section title={t('theme')}>
        <div className="p-3">
          <Segmented<ThemePref>
            label={t('theme')}
            value={prefs.theme}
            onChange={(v) => setPrefs({ theme: v })}
            options={(['system', 'light', 'dark'] as const).map((k) => ({ key: k, label: t(`theme_${k}`) }))}
          />
        </div>
      </Section>
      <Section title={t('glass')} footer={t('glassHint')}>
        <div className="p-3">
          <Segmented<GlassPref>
            label={t('glass')}
            value={prefs.glass}
            testId="settings-glass"
            onChange={(v) => setPrefs({ glass: v })}
            options={(['auto', 'frosted'] as const).map((k) => ({ key: k, label: t(`glass_${k}`) }))}
          />
        </div>
      </Section>
      <Section footer={t('deleteAccountBody')}>
        <button type="button" onClick={() => setConfirm(true)} className="focus-ring flex min-h-12 w-full items-center px-4 t-body text-danger" data-testid="delete-account">
          {t('deleteAccount')}
        </button>
      </Section>
      <p className="text-center t-footnote text-text-3">{me?.name} · NussNuss 2.0</p>

      <Sheet open={confirm} onClose={() => setConfirm(false)} title={t('deleteAccount')}>
        <div className="flex flex-col gap-4 pb-2">
          <p className="t-subhead text-text-2">{t('deleteAccountBody')}</p>
          <Button
            block
            variant="danger"
            data-testid="confirm-delete"
            onClick={async () => {
              await deleteAccount();
              router.replace('/');
            }}
          >
            {t('deleteAccountConfirm')}
          </Button>
          <Button block variant="plain" onClick={() => setConfirm(false)}>
            {t('cancel')}
          </Button>
        </div>
      </Sheet>
    </Screen>
  );
}
