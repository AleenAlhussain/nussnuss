'use client';

import { Check, Copy, ShareFat, WhatsappLogo, X } from '@phosphor-icons/react';
import { encodeQr, qrPath, toneOfIcon, type CoverIcon, type CoverTone } from '@nussnuss/core';
import { useEffect, useMemo, useState } from 'react';
import { api, type GroupDetail } from '@/lib/api';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { timeEnd, timeStart } from '@/lib/timing';
import { CurrencyButton, CurrencyList, guessCurrency } from './currency';
import { Sheet } from './glass';
import { Avatar, COVER_ICON, CoverPicker, CoverTile } from './identity';
import { useToast } from './toast';
import { Button, Chip, ErrorText, Field } from './ui';

/** An emoji for each cover, still sent so older copies of the app show something sensible. */
const ICON_EMOJI: Record<CoverIcon, string> = {
  plane: '✈️',
  beach: '🏖️',
  mountain: '🏔️',
  car: '🚗',
  home: '🏠',
  food: '🍽️',
  coffee: '☕',
  moon: '🌙',
  party: '🎉',
  gift: '🎁',
  cart: '🛒',
  heart: '❤️',
  ball: '⚽',
  work: '💼',
  book: '📚',
  music: '🎵',
};

/** Starting points: each sets the cover (which also tunes the title suggestions) and a name. */
const TEMPLATES: { key: string; icon: CoverIcon; name?: TKey }[] = [
  { key: 'trip', icon: 'plane' },
  { key: 'flat', icon: 'home', name: 'tplName_flat' },
  { key: 'dinner', icon: 'food', name: 'tplName_dinner' },
  { key: 'iftar', icon: 'moon', name: 'tplName_iftar' },
  { key: 'eid', icon: 'gift', name: 'tplName_eid' },
  { key: 'wedding', icon: 'heart', name: 'tplName_wedding' },
  { key: 'office', icon: 'work', name: 'tplName_office' },
];

export function NewGroupSheet({ open, onClose, onCreated }: { open: boolean; onClose: () => void; onCreated: (g: GroupDetail) => void }) {
  const { t, me } = useSession();
  const [name, setName] = useState('');
  const [cover, setCover] = useState<{ icon: CoverIcon; tone: CoverTone }>({ icon: 'plane', tone: 'sky' });
  const [tpl, setTpl] = useState<string | null>(null);
  const [cur, setCur] = useState('AED');
  const [picking, setPicking] = useState(false);
  const [people, setPeople] = useState<string[]>([]);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (open) {
      setName('');
      setCover({ icon: 'plane', tone: 'sky' });
      setTpl(null);
      setCur(guessCurrency());
      setPicking(false);
      setPeople([]);
      setDraft('');
      setError(null);
    }
  }, [open]);

  const add = () => {
    const n = draft.trim().slice(0, 40);
    if (!n) return;
    const key = n.toLocaleLowerCase();
    if (people.some((p) => p.toLocaleLowerCase() === key) || me?.name.toLocaleLowerCase() === key) return setError(t('err_dup'));
    setPeople((p) => [...p, n]);
    setDraft('');
    setError(null);
  };

  const create = async () => {
    const pending = draft.trim();
    const all = pending ? [...people, pending] : people;
    if (!name.trim()) return setError(t('err_name'));
    if (!all.length) return setError(t('err_people'));
    setBusy(true);
    try {
      const g = await api.createGroup({ name: name.trim(), emoji: ICON_EMOJI[cover.icon], cover: `${cover.icon}:${cover.tone}`, currency: cur, members: all });
      onCreated(g);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const pickTemplate = (k: (typeof TEMPLATES)[number]) => {
    const prev = TEMPLATES.find((x) => x.key === tpl);
    const prevName = prev?.name ? t(prev.name) : '';
    // A name the person typed themselves is never replaced.
    if (!name.trim() || name === prevName) setName(k.name ? t(k.name) : '');
    setCover({ icon: k.icon, tone: toneOfIcon(k.icon) });
    setTpl(k.key);
  };

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={picking ? t('currency') : t('newGroup')}
      testId="new-group-sheet"
      morph
      footer={
        picking ? null : (
          <div className="flex flex-col gap-2">
            <ErrorText>{error}</ErrorText>
            <Button block onClick={create} disabled={busy} data-testid="create-group">
              {t('create')}
            </Button>
          </div>
        )
      }
    >
      {picking ? (
        <CurrencyList
          value={cur}
          onBack={() => setPicking(false)}
          onPick={(c) => {
            setCur(c);
            setPicking(false);
          }}
        />
      ) : (
        <div className="flex flex-col gap-5">
          <div className="flex flex-col gap-2">
            <span className="t-footnote font-medium text-text-2 ps-1">{t('whatKind')}</span>
            <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="group" aria-label={t('whatKind')}>
              {TEMPLATES.map((k) => {
                const I = COVER_ICON[k.icon];
                return (
                  <Chip key={k.key} selected={tpl === k.key} onClick={() => pickTemplate(k)} testId={`tpl-${k.key}`}>
                    <I size={18} weight="duotone" aria-hidden />
                    {t(`tpl_${k.key}` as TKey)}
                  </Chip>
                );
              })}
            </div>
          </div>
          <div className="flex items-end gap-3">
            <CoverTile cover={`${cover.icon}:${cover.tone}`} size={48} testId="new-cover" />
            <Field className="flex-1" label={t('groupName')} placeholder={t('groupNamePh')} value={name} maxLength={60} onChange={(e) => setName(e.target.value)} data-testid="group-name" data-autofocus />
          </div>
          <CoverPicker value={cover} onChange={setCover} />
          <CurrencyButton value={cur} onClick={() => setPicking(true)} label={t('currency')} testId="group-currency" />
          <div className="flex flex-col gap-2">
            <span className="t-footnote font-medium text-text-2 ps-1">{t('people')}</span>
            <ul className="flex flex-wrap gap-2">
              <li className="inline-flex h-11 items-center gap-2 rounded-full bg-accent-soft ps-1 pe-4 t-subhead font-medium text-on-accent-soft">
                {me ? <Avatar name={me.name} avatar={me.avatar} size={34} /> : null}
                {me?.name} ({t('you')})
              </li>
              {people.map((p) => (
                <li key={p} className="inline-flex h-11 items-center gap-2 rounded-full bg-surface ps-1 pe-1 t-subhead font-medium text-text ring-1 ring-edge" data-testid="person-chip">
                  <Avatar name={p} size={34} />
                  {p}
                  <button type="button" aria-label={`${t('delete')} ${p}`} onClick={() => setPeople((x) => x.filter((y) => y !== p))} className="tap focus-ring grid place-items-center rounded-full text-text-2">
                    <X size={16} />
                  </button>
                </li>
              ))}
            </ul>
            <form
              className="flex gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                add();
              }}
            >
              <input
                aria-label={t('personPh')}
                data-testid="person-name"
                value={draft}
                maxLength={40}
                aria-invalid={error === t('err_dup')}
                onChange={(e) => {
                  setDraft(e.target.value);
                  if (error) setError(null);
                }}
                placeholder={t('personPh')}
                className="field h-12 min-w-0 flex-1 rounded-control bg-surface px-4 t-body text-text placeholder:text-text-3"
              />
              <Button type="submit" variant="secondary" data-testid="add-person">
                {t('addPerson')}
              </Button>
            </form>
          </div>
        </div>
      )}
    </Sheet>
  );
}

/** A QR code friends can scan from your screen. Always dark on white, so every camera reads it. */
export function QrCode({ text, size = 168, label }: { text: string; size?: number; label: string }) {
  const { d, n } = useMemo(() => {
    const p = qrPath(encodeQr(text), 3);
    return { d: p.d, n: p.size };
  }, [text]);
  return (
    <svg viewBox={`0 0 ${n} ${n}`} width={size} height={size} role="img" aria-label={label} shapeRendering="crispEdges" className="rounded-control" data-testid="invite-qr" data-text={text}>
      <rect width={n} height={n} fill="#FFFFFF" />
      <path d={d} fill="#15121F" />
    </svg>
  );
}

/** Invite friends: a preview of the group, a QR code, a short link, and ways to send it. */
export function ShareSheet({ open, onClose, group }: { open: boolean; onClose: () => void; group: GroupDetail }) {
  const { t } = useSession();
  const toast = useToast();
  const [link, setLink] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    timeStart('invite');
    setLink(null);
    api
      .invite(group.id)
      .then((r) => setLink(`${window.location.origin}${r.path ?? `/join/${r.token}`}`))
      .catch(() => setLink(''));
  }, [open, group.id]);

  const copy = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      toast(t('copied'), undefined, { done: true });
      timeEnd('invite', true);
    } catch {
      toast(link);
    }
  };
  const message = `${t('shareMessage', { name: group.name })} ${link ?? ''}`;
  const canShare = typeof navigator !== 'undefined' && !!navigator.share;
  const shown = link ? link.replace(/^https?:\/\//, '') : '…';

  return (
    <Sheet open={open} onClose={onClose} title={t('shareTitle')} testId="share-sheet">
      <div className="flex flex-col gap-4 pb-2">
        <div className="flex items-center gap-3 rounded-card bg-surface p-4" data-testid="invite-preview">
          <CoverTile cover={group.cover} emoji={group.emoji} size={52} />
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="truncate t-headline text-text">{group.name}</span>
            <span className="t-footnote text-text-2">{t('joinMeta', { n: group.members.length, currency: group.currency })}</span>
          </span>
        </div>
        <p className="t-subhead text-text-2">{t('inviteBody')}</p>
        <div className="flex flex-col items-center gap-3 rounded-card bg-surface p-4">
          {link ? <QrCode text={link} label={`${t('scanToJoin')}: ${shown}`} /> : <div className="shimmer h-[168px] w-[168px] rounded-control" />}
          <span className="t-footnote font-semibold text-text-2">{t('scanToJoin')}</span>
          <div className="flex w-full items-center gap-2">
            <span className="min-w-0 flex-1 truncate rounded-control bg-surface-2 px-3 py-2.5 t-subhead font-semibold text-text num" data-testid="invite-link" dir="ltr">
              {shown}
            </span>
            <Button variant="secondary" icon={<Copy size={18} />} disabled={!link} onClick={copy} data-testid="copy-link">
              {t('copy')}
            </Button>
          </div>
        </div>
        <ul className="overflow-hidden rounded-card bg-surface" aria-label={t('people')}>
          {group.members.map((m) => (
            <li key={m.id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
              <Avatar name={m.name} avatar={m.avatar} size={36} />
              <span className="flex-1 truncate t-body text-text">{m.isMe ? `${m.name} (${t('you')})` : m.name}</span>
              <span className={`inline-flex items-center gap-1 t-footnote ${m.claimed ? 'text-success' : 'text-text-2'}`}>
                {m.claimed ? <Check size={14} weight="bold" aria-hidden /> : null}
                {m.claimed ? t('joined') : t('notJoined')}
              </span>
            </li>
          ))}
        </ul>
        {canShare ? (
          <Button
            block
            icon={<ShareFat size={20} />}
            disabled={!link}
            data-testid="native-share"
            onClick={() =>
              navigator
                .share({ title: group.name, text: t('shareMessage', { name: group.name }), url: link ?? undefined })
                .then(() => timeEnd('invite', true))
                .catch(() => {})
            }
          >
            {t('shareLink')}
          </Button>
        ) : null}
        <Button
          block
          variant={canShare ? 'secondary' : 'primary'}
          icon={<WhatsappLogo size={22} weight="fill" />}
          disabled={!link}
          onClick={() => {
            timeEnd('invite', true);
            window.open(`https://wa.me/?text=${encodeURIComponent(message)}`, '_blank', 'noopener');
          }}
        >
          {t('sendWhatsApp')}
        </Button>
        <p className="text-center t-footnote text-text-3">{t('shareBody')}</p>
      </div>
    </Sheet>
  );
}
