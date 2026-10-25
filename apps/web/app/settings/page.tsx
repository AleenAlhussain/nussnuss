'use client';

import { CaretRight, DownloadSimple, FileText, LockSimple, Sparkle } from '@phosphor-icons/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { AccountSection } from '@/components/account';
import { Screen, Sheet } from '@/components/glass';
import { Switch } from '@/components/group-options';
import { PayToSection } from '@/components/pay-to';
import { shortDate, usePaywall } from '@/components/paywall';
import { useToast } from '@/components/toast';
import { Button, cx, Section, Segmented } from '@/components/ui';
import { api, saveBlob } from '@/lib/api';
import { haptic } from '@/lib/feel';
import type { Lang } from '@/lib/i18n';
import { LOOKS, useSession, type GlassPref, type Look, type ThemePref } from '@/lib/session';

/** Swatches for the look picker: the look's background and accent, as people will see them. */
const SWATCH: Record<Look, [string, string]> = {
  default: ['var(--nn-bg)', '#5B47E0'],
  night: ['#05030D', '#9B8BFF'],
  saffron: ['#FFF8EC', '#C98A00'],
};

export default function SettingsPage() {
  const { ready, me, prefs, setPrefs, t, deleteAccount, plan, ownsLook } = useSession();
  const router = useRouter();
  const paywall = usePaywall();
  const toast = useToast();
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    if (ready && !me) router.replace('/');
  }, [ready, me, router]);

  return (
    <Screen title={t('settings')} testId="settings">
      <Section title={t('yourPlan')}>
        <button type="button" onClick={() => paywall.open()} className="focus-ring flex min-h-14 w-full items-center gap-3 px-4 py-2 text-start" data-testid="plan-row">
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-row bg-highlight text-on-highlight" aria-hidden>
            <Sparkle size={20} weight="fill" />
          </span>
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="t-body text-text">{t('plus')}</span>
            <span className="t-footnote text-text-2">{plan?.plus && plan.plusUntil ? t('plusOnUntil', { date: shortDate(plan.plusUntil, prefs.lang) }) : t('planFree')}</span>
          </span>
          <span className="t-subhead font-semibold text-accent">{t('seePlus')}</span>
        </button>
      </Section>

      <AccountSection />
      <PayToSection />

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
      <Section title={t('look')} footer={t('lookHint')}>
        <div role="radiogroup" aria-label={t('look')} className="grid grid-cols-3 gap-2 p-3">
          {LOOKS.map((l) => {
            const owned = ownsLook(l);
            const on = prefs.look === l;
            return (
              <button
                key={l}
                type="button"
                role="radio"
                aria-checked={on}
                data-testid={`look-${l}`}
                onClick={() => {
                  if (!owned) return paywall.open();
                  haptic('selection');
                  setPrefs({ look: l });
                }}
                className={cx('focus-ring flex flex-col items-center gap-2 rounded-card p-3 transition-colors', on ? 'bg-accent-soft ring-2 ring-accent' : 'bg-surface-2')}
              >
                <span className="relative grid h-12 w-12 place-items-center rounded-full ring-1 ring-separator" style={{ background: SWATCH[l][0] }} aria-hidden>
                  <span className="h-6 w-6 rounded-full" style={{ background: SWATCH[l][1] }} />
                  {!owned ? (
                    <span className="absolute -bottom-1 -end-1 grid h-6 w-6 place-items-center rounded-full bg-surface text-text-2 ring-1 ring-separator">
                      <LockSimple size={14} weight="bold" />
                    </span>
                  ) : null}
                </span>
                <span className="t-footnote font-semibold text-text">{t(`look_${l}`)}</span>
                {!owned ? <span className="t-caption text-text-2">{t('needsPlus')}</span> : null}
              </button>
            );
          })}
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
      <Section footer={t('soundsHint')}>
        <div className="flex min-h-14 items-center gap-3 px-4">
          <span className="flex-1 t-body text-text">{t('sounds')}</span>
          <Switch on={prefs.sounds} onChange={(v) => setPrefs({ sounds: v })} label={t('sounds')} testId="sounds" />
        </div>
      </Section>

      <Section title={t('about')}>
        {(
          [
            ['/privacy', t('privacy')],
            ['/terms', t('terms')],
          ] as const
        ).map(([href, label]) => (
          <Link key={href} href={href} className="focus-ring flex min-h-12 items-center gap-3 border-b border-separator/60 px-4 t-body text-text last:border-0">
            <FileText size={20} className="text-text-2" aria-hidden />
            <span className="flex-1">{label}</span>
            <CaretRight size={18} className="text-text-3 rtl:-scale-x-100" aria-hidden />
          </Link>
        ))}
        <button
          type="button"
          onClick={() =>
            api
              .exportMine()
              .then((b) => saveBlob(b, 'nussnuss-my-data.json'))
              .catch(() => toast(t('error')))
          }
          className="focus-ring flex min-h-12 w-full items-center gap-3 px-4 t-body text-text"
          data-testid="export-data"
        >
          <DownloadSimple size={20} className="text-text-2" aria-hidden />
          {t('exportData')}
        </button>
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
