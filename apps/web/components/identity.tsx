'use client';

import {
  Airplane,
  Basket,
  Bed,
  BookOpen,
  Briefcase,
  Car,
  Coffee,
  Confetti,
  ForkKnife,
  Gift,
  Heart,
  House,
  Island,
  MoonStars,
  Mountains,
  MusicNotes,
  Receipt,
  ShoppingBag,
  ShoppingCart,
  SoccerBall,
  Tag,
  Ticket,
  type Icon,
} from '@phosphor-icons/react';
import { COVER_ICONS, COVER_TONES, groupCover, initialOf, toneFor, type Avatar as AvatarT, type CoverIcon, type CoverTone } from '@nussnuss/core';
import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { avatarSrc } from '@/lib/api';
import { haptic } from '@/lib/feel';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

/** One icon family for the whole interface (Phosphor). Covers use its duotone weight for the two-tone look. */
export const COVER_ICON: Record<CoverIcon, Icon> = {
  plane: Airplane,
  beach: Island,
  mountain: Mountains,
  car: Car,
  home: House,
  food: ForkKnife,
  coffee: Coffee,
  moon: MoonStars,
  party: Confetti,
  gift: Gift,
  cart: ShoppingCart,
  heart: Heart,
  ball: SoccerBall,
  work: Briefcase,
  book: BookOpen,
  music: MusicNotes,
};

/** Categories get their own icon and tone, so a list of expenses can be scanned by shape and colour. */
export const CATEGORY_LOOK: Record<string, { icon: Icon; tone: CoverTone }> = {
  food: { icon: ForkKnife, tone: 'coral' },
  groceries: { icon: Basket, tone: 'mint' },
  transport: { icon: Car, tone: 'sky' },
  stay: { icon: Bed, tone: 'violet' },
  fun: { icon: Ticket, tone: 'rose' },
  bills: { icon: Receipt, tone: 'slate' },
  shopping: { icon: ShoppingBag, tone: 'saffron' },
  other: { icon: Tag, tone: 'slate' },
};

export const toneStyle = (tone: CoverTone): CSSProperties => ({ background: `var(--nn-cover-${tone}-bg)`, color: `var(--nn-cover-${tone}-fg)` });

/** A group's cover: its drawn icon on a soft tile in its tone. */
export function CoverTile({
  cover,
  emoji,
  size = 56,
  className,
  testId = 'cover',
}: {
  cover?: string | null;
  emoji?: string;
  size?: number;
  className?: string;
  testId?: string;
}) {
  const c = groupCover({ cover, emoji });
  const I = COVER_ICON[c.icon];
  return (
    <span
      aria-hidden
      data-testid={testId}
      data-cover={`${c.icon}:${c.tone}`}
      className={cx('inline-grid shrink-0 place-items-center', className)}
      style={{ ...toneStyle(c.tone), width: size, height: size, borderRadius: Math.round(size * 0.3) }}
    >
      <I size={Math.round(size * 0.52)} weight="duotone" />
    </span>
  );
}

export function CategoryTile({ category, size = 44 }: { category: string; size?: number }) {
  const look = CATEGORY_LOOK[category] ?? CATEGORY_LOOK.other;
  const I = look.icon;
  return (
    <span aria-hidden className="inline-grid shrink-0 place-items-center" style={{ ...toneStyle(look.tone), width: size, height: size, borderRadius: Math.round(size * 0.3) }} data-category={category}>
      <I size={Math.round(size * 0.5)} weight="fill" />
    </span>
  );
}

/** A person: their photo, their emoji or their initial, on the tone they chose (or one picked from the name). */
export function Avatar({ name, avatar, size = 36, className }: { name: string; avatar?: AvatarT | null; size?: number; className?: string; index?: number }) {
  const a: AvatarT = avatar ?? { kind: 'initial', tone: toneFor(name) };
  const [broken, setBroken] = useState(false);
  const style: CSSProperties = { ...toneStyle(a.tone), width: size, height: size };
  if (a.kind === 'photo' && !broken) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img src={avatarSrc(a.url)} alt="" aria-hidden width={size} height={size} onError={() => setBroken(true)} className={cx('shrink-0 rounded-full object-cover', className)} style={style} data-avatar="photo" />
    );
  }
  return (
    <span aria-hidden className={cx('inline-grid shrink-0 select-none place-items-center rounded-full font-semibold', className)} style={{ ...style, fontSize: a.kind === 'emoji' ? size * 0.56 : size * 0.42, lineHeight: 1 }} data-avatar={a.kind === 'photo' ? 'initial' : a.kind}>
      {a.kind === 'emoji' ? a.value : initialOf(name)}
    </span>
  );
}

/** Up to four faces overlapping, for a group card or a preview. */
export function AvatarStack({ people, size = 24, max = 4 }: { people: { name: string; avatar?: AvatarT | null }[]; size?: number; max?: number }) {
  return (
    <span className="inline-flex items-center" aria-hidden>
      {people.slice(0, max).map((p, i) => (
        <span key={`${p.name}-${i}`} className="rounded-full ring-2 ring-surface" style={{ marginInlineStart: i ? -size * 0.3 : 0 }}>
          <Avatar name={p.name} avatar={p.avatar} size={size} />
        </span>
      ))}
    </span>
  );
}

/**
 * One line of text that shrinks to fit its box instead of wrapping (amounts: "AED 833.33" never breaks),
 * but never below `min` px. Only when even that is too wide does it wrap. It sizes itself in the DOM (not in
 * React state), refitting when the box gets wider or narrower or the text changes, so it can never loop.
 */
export function FitLine({ children, className, min = 17, testId, label }: { children: ReactNode; className?: string; min?: number; testId?: string; label?: string }) {
  const el = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const node = el.current;
    const box = node?.parentElement;
    if (!node || !box) return;
    let lastWidth = -1;
    const fit = () => {
      const room = box.clientWidth;
      node.style.fontSize = '';
      node.style.whiteSpace = 'nowrap';
      const need = node.scrollWidth;
      if (!room || need <= room + 1) {
        delete node.dataset.fit;
        return;
      }
      const natural = parseFloat(getComputedStyle(node).fontSize);
      const scaled = Math.max(min, Math.floor(natural * (room / need) * 100) / 100);
      node.style.fontSize = `${scaled}px`;
      node.dataset.fit = 'shrunk';
      if (scaled === min && node.scrollWidth > room + 1) node.style.whiteSpace = 'normal';
    };
    fit();
    lastWidth = box.clientWidth;
    const ro = new ResizeObserver(() => {
      if (box.clientWidth === lastWidth) return;
      lastWidth = box.clientWidth;
      fit();
    });
    ro.observe(box);
    const mo = new MutationObserver(fit);
    mo.observe(node, { subtree: true, childList: true, characterData: true });
    return () => {
      ro.disconnect();
      mo.disconnect();
    };
  }, [min]);
  return (
    <span ref={el} aria-label={label} className={cx('inline-block max-w-full whitespace-nowrap', className)} data-testid={testId}>
      {children}
    </span>
  );
}

/** Picks a cover: the icon grid, then the tone row. */
export function CoverPicker({ value, onChange }: { value: { icon: CoverIcon; tone: CoverTone }; onChange: (v: { icon: CoverIcon; tone: CoverTone }) => void }) {
  const { t } = useSession();
  return (
    <div className="flex flex-col gap-3" data-testid="cover-picker">
      <div role="radiogroup" aria-label={t('cover')} className="grid grid-cols-8 gap-1.5">
        {COVER_ICONS.map((icon) => {
          const I = COVER_ICON[icon];
          const on = value.icon === icon;
          return (
            <button
              key={icon}
              type="button"
              role="radio"
              aria-checked={on}
              aria-label={t(`icon_${icon}` as TKey)}
              data-testid={`cover-${icon}`}
              onClick={() => {
                haptic('selection');
                onChange({ ...value, icon });
              }}
              className={cx('focus-ring grid aspect-square place-items-center rounded-control transition-colors', on ? 'ring-2 ring-accent' : 'ring-1 ring-edge')}
              style={on ? toneStyle(value.tone) : undefined}
            >
              <I size={22} weight={on ? 'duotone' : 'regular'} className={on ? undefined : 'text-text-2'} />
            </button>
          );
        })}
      </div>
      <ToneRow value={value.tone} onChange={(tone) => onChange({ ...value, tone })} testId="cover-tone" />
    </div>
  );
}

export function ToneRow({ value, onChange, testId }: { value: CoverTone; onChange: (t: CoverTone) => void; testId?: string }) {
  const { t } = useSession();
  return (
    <div role="radiogroup" aria-label={t('colour')} className="flex flex-wrap gap-2" data-testid={testId}>
      {COVER_TONES.map((tone) => {
        const on = value === tone;
        return (
          <button
            key={tone}
            type="button"
            role="radio"
            aria-checked={on}
            aria-label={t(`tone_${tone}` as TKey)}
            data-testid={testId ? `${testId}-${tone}` : undefined}
            onClick={() => {
              haptic('selection');
              onChange(tone);
            }}
            className={cx('tap focus-ring grid place-items-center rounded-full', on ? 'ring-2 ring-accent ring-offset-2 ring-offset-surface' : '')}
          >
            <span className="h-8 w-8 rounded-full ring-1 ring-edge" style={{ background: `var(--nn-cover-${tone}-fg)` }} />
          </button>
        );
      })}
    </div>
  );
}

/** How much of a round is paid, as a ring (money circles). */
export function ProgressRing({ value, total, size = 40, label }: { value: number; total: number; size?: number; label?: string }) {
  const r = (size - 6) / 2;
  const c = 2 * Math.PI * r;
  const part = total ? Math.min(1, value / total) : 0;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role={label ? 'img' : undefined} aria-label={label} aria-hidden={label ? undefined : true} data-testid="progress-ring" data-value={`${value}/${total}`}>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--nn-surface-2)" strokeWidth={5} />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={part >= 1 ? 'var(--nn-success)' : 'var(--nn-accent)'}
        strokeWidth={5}
        strokeLinecap="round"
        strokeDasharray={`${c * part} ${c}`}
        transform={`rotate(-90 ${size / 2} ${size / 2})`}
        style={{ transition: 'stroke-dasharray 450ms cubic-bezier(0.32, 0.72, 0, 1)' }}
      />
      <text x="50%" y="50%" dominantBaseline="central" textAnchor="middle" fontSize={size * 0.3} fontWeight={700} fill="var(--nn-text)">
        {value}/{total}
      </text>
    </svg>
  );
}
