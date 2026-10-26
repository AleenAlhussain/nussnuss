'use client';

import { Camera, CaretRight, DownloadSimple, FileText, LockSimple, Sparkle, Trash } from '@phosphor-icons/react';
import { AVATAR_EMOJI, toneFor, type CoverTone } from '@nussnuss/core';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { AccountSection } from '@/components/account';
import { Screen, Sheet } from '@/components/glass';
import { Switch } from '@/components/group-options';
import { Avatar, FitLine, ToneRow } from '@/components/identity';
import { PayToSection } from '@/components/pay-to';
import { shortDate, usePaywall } from '@/components/paywall';
import { useToast } from '@/components/toast';
import { Button, cx, ErrorText, Field, Section, Segmented } from '@/components/ui';
import { api, ApiError, saveBlob, type Overview } from '@/lib/api';
import { haptic } from '@/lib/feel';
import { money } from '@/lib/format';
import type { Lang } from '@/lib/i18n';
import { kvGet } from '@/lib/kv';
import { LOOKS, useSession, type GlassPref, type Look, type ThemePref } from '@/lib/session';

/** Swatches for the look picker: the look's background and accent, as people will see them. */
const SWATCH: Record<Look, [string, string]> = {
  default: ['var(--nn-bg)', '#5B47E0'],
  night: ['#05030D', '#9B8BFF'],
  saffron: ['#FFF8EC', '#C98A00'],
};

/** Shrinks a photo to 256 × 256 (centre crop) as JPEG, so what goes up is ~20 KB. */
async function squarePhoto(file: File): Promise<string> {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = reject;
      i.src = url;
    });
    const side = Math.min(img.naturalWidth, img.naturalHeight);
    const c = document.createElement('canvas');
    c.width = c.height = 256;
    const g = c.getContext('2d');
    if (!g) throw new Error('canvas');
    g.drawImage(img, (img.naturalWidth - side) / 2, (img.naturalHeight - side) / 2, side, side, 0, 0, 256, 256);
    return c.toDataURL('image/jpeg', 0.82);
  } finally {
    URL.revokeObjectURL(url);
  }
}

type Kind = 'initial' | 'emoji' | 'photo';

/** Photo, name and colour: chosen once, shown to friends everywhere. */
function ProfileSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t, me, setMe } = useSession();
  const toast = useToast();
  const file = useRef<HTMLInputElement>(null);
  const [name, setName] = useState('');
  const [kind, setKind] = useState<Kind>('initial');
  const [emoji, setEmoji] = useState<string>(AVATAR_EMOJI[0]);
  const [tone, setTone] = useState<CoverTone>('violet');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!open || !me) return;
    setName(me.name);
    const a = me.avatar;
    setKind(a?.kind ?? 'initial');
    setTone(a?.tone ?? toneFor(me.name));
    if (a?.kind === 'emoji') setEmoji(a.value);
    setError(null);
  }, [open, me]);
  if (!me) return null;
  const preview =
    kind === 'photo' && me.avatar?.kind === 'photo'
      ? me.avatar
      : kind === 'emoji'
        ? ({ kind: 'emoji', value: emoji, tone } as const)
        : ({ kind: 'initial', tone } as const);
  const pick = async (f: File | undefined) => {
    if (!f) return;
    setBusy(true);
    setError(null);
    try {
      const data = await squarePhoto(f);
      const m = await api.setPhoto(data);
      setMe(m);
      setKind('photo');
      haptic('success');
    } catch (e) {
      setError(e instanceof ApiError && e.status === 400 ? e.message : t('photoBad'));
    } finally {
      setBusy(false);
      if (file.current) file.current.value = '';
    }
  };
  const save = async () => {
    if (!name.trim()) return setError(t('yourNameHint'));
    setBusy(true);
    try {
      let m = me;
      if (kind === 'photo' && me.avatar?.kind === 'photo') {
        // Photo already sent; the tone still matters for places that show the initial.
        if (name.trim() !== me.name) m = await api.patchMe({ name: name.trim() });
      } else {
        if (me.avatar?.kind === 'photo') m = await api.removePhoto();
        m = await api.patchMe({ name: name.trim(), avatar: kind === 'emoji' ? { kind: 'emoji', value: emoji, tone } : { kind: 'initial', tone } });
      }
      setMe(m);
      toast(t('profileSaved'), undefined, { done: true });
      onClose();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={t('profileEdit')}
      testId="profile-sheet"
      footer={
        <div className="flex flex-col gap-2">
          <ErrorText>{error}</ErrorText>
          <Button block onClick={save} disabled={busy} data-testid="save-profile">
            {t('save')}
          </Button>
        </div>
      }
    >
      <div className="flex flex-col gap-5">
        <div className="flex flex-col items-center gap-2" data-testid="profile-preview">
          <Avatar name={name || me.name} avatar={preview} size={96} />
          <span className="t-headline text-text">{name || me.name}</span>
        </div>
        <Field label={t('yourName')} value={name} maxLength={40} onChange={(e) => setName(e.target.value)} data-testid="profile-name" />
        <Segmented<Kind>
          label={t('photo')}
          value={kind}
          testId="avatar-kind"
          onChange={(k) => {
            if (k === 'photo' && me.avatar?.kind !== 'photo') file.current?.click();
            else setKind(k);
          }}
          options={[
            { key: 'initial', label: t('avatarInitial') },
            { key: 'emoji', label: t('avatarEmoji') },
            { key: 'photo', label: t('photo') },
          ]}
        />
        <input ref={file} type="file" accept="image/jpeg,image/png,image/webp" className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => pick(e.target.files?.[0])} data-testid="photo-input" />
        {kind === 'emoji' ? (
          <div role="radiogroup" aria-label={t('avatarEmoji')} className="grid grid-cols-8 gap-1.5">
            {AVATAR_EMOJI.map((e) => (
              <button
                key={e}
                type="button"
                role="radio"
                aria-checked={emoji === e}
                aria-label={e}
                onClick={() => {
                  haptic('selection');
                  setEmoji(e);
                }}
                className={cx('focus-ring grid aspect-square place-items-center rounded-control text-2xl', emoji === e ? 'ring-2 ring-accent' : 'ring-1 ring-edge')}
                data-testid="avatar-emoji"
              >
                {e}
              </button>
            ))}
          </div>
        ) : null}
        {kind === 'photo' ? (
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" icon={<Camera size={20} />} onClick={() => file.current?.click()} disabled={busy} data-testid="choose-photo">
              {t('choosePhoto')}
            </Button>
            {me.avatar?.kind === 'photo' ? (
              <Button
                variant="danger"
                icon={<Trash size={20} />}
                disabled={busy}
                onClick={() =>
                  api
                    .removePhoto()
                    .then((m) => {
                      setMe(m);
                      setKind('initial');
                    })
                    .catch(() => setError(t('error')))
                }
                data-testid="remove-photo"
              >
                {t('removePhoto')}
              </Button>
            ) : null}
          </div>
        ) : null}
        <div className="flex flex-col gap-2">
          <span className="t-footnote font-medium text-text-2 ps-1">{t('colour')}</span>
          <ToneRow value={tone} onChange={setTone} testId="avatar-tone" />
        </div>
      </div>
    </Sheet>
  );
}

/** A small stand-in for the bars, so a glass or look change shows before you leave the page. */
function LivePreview() {
  const { t } = useSession();
  return (
    <div className="relative h-28 overflow-hidden rounded-card" aria-hidden data-testid="appearance-preview" style={{ background: 'var(--nn-bg)' }}>
      <div className="absolute inset-0 flex flex-col gap-2 p-3">
        <div className="h-5 w-2/3 rounded-full bg-accent" />
        <div className="h-4 w-1/2 rounded-full bg-highlight" />
        <div className="h-4 w-3/4 rounded-full bg-surface" />
        <div className="h-4 w-1/3 rounded-full bg-accent-soft" />
      </div>
      <div className="glass absolute inset-x-3 bottom-3 flex h-12 items-center justify-around rounded-full t-footnote font-semibold text-text">
        <span className="text-accent">{t('tabHome')}</span>
        <span className="text-text-2">{t('tabActivity')}</span>
        <span className="text-text-2">{t('tabYou')}</span>
      </div>
    </div>
  );
}

export default function YouPage() {
  const { ready, me, prefs, setPrefs, t, deleteAccount, plan, ownsLook } = useSession();
  const router = useRouter();
  const paywall = usePaywall();
  const toast = useToast();
  const [confirm, setConfirm] = useState(false);
  const [profile, setProfile] = useState(false);
  const [o, setO] = useState<Overview | null>(null);
  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (!ready || !me) return;
    kvGet<Overview>('overview').then((c) => c && setO((x) => x ?? c));
    api.overview().then(setO).catch(() => {});
  }, [ready, me, router]);
  const first = o?.totals[0];

  return (
    <Screen title={t('tabYou')} testId="settings">
      <button type="button" onClick={() => setProfile(true)} className="press focus-ring flex items-center gap-4 rounded-card bg-surface p-4 text-start" data-testid="profile-row">
        {me ? <Avatar name={me.name} avatar={me.avatar} size={60} /> : null}
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="truncate t-title-3 text-text">{me?.name}</span>
          <span className="t-subhead text-accent">{t('profileEdit')}</span>
        </span>
        <CaretRight size={18} className="text-text-3 rtl:-scale-x-100" aria-hidden />
      </button>

      {o ? (
        <Link href="/" className="focus-ring flex flex-col gap-1 rounded-card bg-surface p-4" data-testid="you-balance">
          <span className="t-footnote font-semibold text-text-2">{t('overallYou')}</span>
          {first ? (
            <>
              <span className="t-subhead text-text-2">{first.amount > 0 ? t('overallBack') : t('overallOwe')}</span>
              <div className="min-w-0">
                <FitLine className={`t-title-1 num ${first.amount > 0 ? 'text-success' : 'text-text'}`}>{money(Math.abs(first.amount), first.currency, prefs.lang)}</FitLine>
              </div>
              {o.totals.slice(1).map((m) => (
                <span key={m.currency} className="t-footnote text-text-2 num">
                  {t('andAmount', { amount: `${m.amount > 0 ? '+' : '−'}${money(Math.abs(m.amount), m.currency, prefs.lang)}` })}
                </span>
              ))}
            </>
          ) : (
            <span className="t-headline text-text">{t('overallEven')}</span>
          )}
        </Link>
      ) : null}

      <Section title={t('appearance')} footer={t('glassHint')}>
        <div className="flex flex-col gap-3 p-3">
          <LivePreview />
          <Segmented<ThemePref>
            label={t('theme')}
            value={prefs.theme}
            onChange={(v) => setPrefs({ theme: v })}
            options={(['system', 'light', 'dark'] as const).map((k) => ({ key: k, label: t(`theme_${k}`) }))}
          />
          <span className="t-footnote font-medium text-text-2 ps-1">{t('glass')}</span>
          <Segmented<GlassPref>
            label={t('glass')}
            value={prefs.glass}
            testId="settings-glass"
            onChange={(v) => setPrefs({ glass: v })}
            options={[
              { key: 'clear', label: t('glass_auto') },
              { key: 'tinted', label: t('glass_tinted') },
              { key: 'frosted', label: t('glass_solid') },
            ]}
          />
          <span className="t-footnote font-medium text-text-2 ps-1">{t('look')}</span>
          <div role="radiogroup" aria-label={t('look')} className="grid grid-cols-3 gap-2">
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
                      <span className="absolute -bottom-1 -end-1 grid h-6 w-6 place-items-center rounded-full bg-surface text-text-2 ring-1 ring-edge">
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
          <p className="t-footnote text-text-2 ps-1">{t('lookHint')}</p>
        </div>
      </Section>

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

      <ProfileSheet open={profile} onClose={() => setProfile(false)} />
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
