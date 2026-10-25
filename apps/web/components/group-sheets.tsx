'use client';

import { CURRENCIES } from '@nussnuss/core';
import { Copy, ShareFat, WhatsappLogo, X } from '@phosphor-icons/react';
import { useEffect, useState } from 'react';
import { api, type GroupDetail } from '@/lib/api';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { Sheet } from './glass';
import { useToast } from './toast';
import { Button, Chip, Field } from './ui';

const EMOJIS = ['🏝️', '🏕️', '✈️', '🏠', '🍽️', '☕', '🎉', '⚽', '🚗', '🛒', '🎓', '💼', '🌙', '🎁', '💍'];

/** Starting points: each sets the emoji (which also tunes the title suggestions) and a name. */
const TEMPLATES: { key: string; emoji: string; name?: TKey }[] = [
  { key: 'trip', emoji: '✈️' },
  { key: 'flat', emoji: '🏠', name: 'tplName_flat' },
  { key: 'dinner', emoji: '🍽️', name: 'tplName_dinner' },
  { key: 'iftar', emoji: '🌙', name: 'tplName_iftar' },
  { key: 'eid', emoji: '🎁', name: 'tplName_eid' },
  { key: 'wedding', emoji: '💍', name: 'tplName_wedding' },
  { key: 'office', emoji: '💼', name: 'tplName_office' },
];

function guessCurrency(): string {
  try {
    const region = new Intl.Locale(navigator.language).maximize().region;
    const map: Record<string, string> = { AE: 'AED', SA: 'SAR', KW: 'KWD', QA: 'QAR', BH: 'BHD', OM: 'OMR', EG: 'EGP', JO: 'JOD', SY: 'SYP', LB: 'LBP', IQ: 'IQD', MA: 'MAD', TR: 'TRY', GB: 'GBP', US: 'USD', DE: 'EUR', FR: 'EUR', IN: 'INR' };
    if (region && map[region]) return map[region];
  } catch {}
  return 'AED';
}

export function NewGroupSheet({ open, onClose, onCreated }: { open: boolean; onClose: () => void; onCreated: (g: GroupDetail) => void }) {
  const { t, prefs, me } = useSession();
  const [name, setName] = useState('');
  const [emoji, setEmoji] = useState(EMOJIS[0]);
  const [tpl, setTpl] = useState<string | null>(null);
  const [cur, setCur] = useState('AED');
  const [people, setPeople] = useState<string[]>([]);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (open) {
      setName('');
      setEmoji(EMOJIS[0]);
      setTpl(null);
      setCur(guessCurrency());
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
      const g = await api.createGroup({ name: name.trim(), emoji, currency: cur, members: all });
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
    setEmoji(k.emoji);
    setTpl(k.key);
  };

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={t('newGroup')}
      testId="new-group-sheet"
      morph
      footer={
        <div className="flex flex-col gap-2">
          {error ? <p className="text-center t-footnote text-danger" role="alert">{error}</p> : null}
          <Button block onClick={create} disabled={busy} data-testid="create-group">
            {t('create')}
          </Button>
        </div>
      }
    >
      <div className="flex flex-col gap-5">
        <div className="flex flex-col gap-2">
          <span className="t-footnote font-medium text-text-2 ps-1">{t('whatKind')}</span>
          <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="group" aria-label={t('whatKind')}>
            {TEMPLATES.map((k) => (
              <Chip key={k.key} selected={tpl === k.key} onClick={() => pickTemplate(k)} testId={`tpl-${k.key}`}>
                <span aria-hidden>{k.emoji}</span>
                {t(`tpl_${k.key}` as TKey)}
              </Chip>
            ))}
          </div>
        </div>
        <Field label={t('groupName')} placeholder={t('groupNamePh')} value={name} maxLength={60} onChange={(e) => setName(e.target.value)} data-testid="group-name" data-autofocus />
        <div role="radiogroup" aria-label="Emoji" className="grid grid-cols-5 gap-2 sm:grid-cols-8">
          {EMOJIS.map((e) => (
            <button
              key={e}
              type="button"
              role="radio"
              aria-checked={emoji === e}
              aria-label={e}
              onClick={() => setEmoji(e)}
              className={`focus-ring grid h-12 place-items-center rounded-control text-2xl ${emoji === e ? 'bg-accent-soft ring-2 ring-accent' : 'bg-surface'}`}
            >
              {e}
            </button>
          ))}
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="grp-cur" className="t-footnote font-medium text-text-2 ps-1">
            {t('currency')}
          </label>
          <select
            id="grp-cur"
            data-testid="group-currency"
            value={cur}
            onChange={(e) => setCur(e.target.value)}
            className="focus-ring h-12 rounded-control bg-surface px-3 t-body text-text ring-1 ring-separator"
          >
            {CURRENCIES.map((c) => (
              <option key={c.code} value={c.code}>
                {c.code} · {prefs.lang === 'ar' ? c.ar : c.en}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-2">
          <span className="t-footnote font-medium text-text-2 ps-1">{t('people')}</span>
          <ul className="flex flex-wrap gap-2">
            <li className="inline-flex h-11 items-center rounded-full bg-accent-soft px-4 t-subhead font-medium text-on-accent-soft">
              {me?.name} ({t('you')})
            </li>
            {people.map((p) => (
              <li key={p} className="inline-flex h-11 items-center gap-1 rounded-full bg-surface ps-4 pe-1 t-subhead font-medium text-text ring-1 ring-separator" data-testid="person-chip">
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
              onChange={(e) => {
                setDraft(e.target.value);
                if (error) setError(null);
              }}
              placeholder={t('personPh')}
              className={`focus-ring h-12 flex-1 rounded-control bg-surface px-4 t-body text-text placeholder:text-text-3 ${error === t('err_dup') ? 'ring-2 ring-danger' : 'ring-1 ring-separator'}`}
            />
            <Button type="submit" variant="secondary" data-testid="add-person">
              {t('addPerson')}
            </Button>
          </form>
        </div>
      </div>
    </Sheet>
  );
}

export function ShareSheet({ open, onClose, group }: { open: boolean; onClose: () => void; group: GroupDetail }) {
  const { t } = useSession();
  const toast = useToast();
  const [link, setLink] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setLink(null);
    api
      .invite(group.id)
      .then((r) => setLink(`${window.location.origin}/join/${r.token}`))
      .catch(() => setLink(''));
  }, [open, group.id]);

  const copy = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      toast(t('copied'));
    } catch {
      toast(link);
    }
  };
  const message = `${t('shareMessage', { name: group.name })} ${link ?? ''}`;
  const canShare = typeof navigator !== 'undefined' && !!navigator.share;

  return (
    <Sheet open={open} onClose={onClose} title={t('shareTitle')} testId="share-sheet">
      <div className="flex flex-col gap-4 pb-2">
        <p className="t-subhead text-text-2">{t('shareBody')}</p>
        <div className="rounded-control bg-surface px-4 py-3 t-footnote text-text-2 break-all num" data-testid="invite-link" dir="ltr">
          {link ?? '…'}
        </div>
        <Button block icon={<WhatsappLogo size={22} weight="fill" />} disabled={!link} onClick={() => window.open(`https://wa.me/?text=${encodeURIComponent(message)}`, '_blank', 'noopener')}>
          {t('sendWhatsApp')}
        </Button>
        {canShare ? (
          <Button
            block
            variant="secondary"
            icon={<ShareFat size={20} />}
            disabled={!link}
            data-testid="native-share"
            onClick={() => navigator.share({ title: group.name, text: t('shareMessage', { name: group.name }), url: link ?? undefined }).catch(() => {})}
          >
            {t('share')}
          </Button>
        ) : null}
        <Button block variant="secondary" icon={<Copy size={20} />} disabled={!link} onClick={copy} data-testid="copy-link">
          {t('copyLink')}
        </Button>
      </div>
    </Sheet>
  );
}
