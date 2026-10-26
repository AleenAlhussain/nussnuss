'use client';

import { ArrowRight, BellRinging, Check, CheckCircle, Copy, ArrowSquareOut, ShareFat } from '@phosphor-icons/react';
import { payAction, type PayTo, type Transfer } from '@nussnuss/core';
import { AnimatePresence, motion, useMotionValue, useTransform } from 'motion/react';
import { useEffect, useState } from 'react';
import { saveBlob, type GroupDetail } from '@/lib/api';
import { haptic, spring } from '@/lib/feel';
import { money } from '@/lib/format';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { SettledMoment } from './coin';
import { summaryCard } from './summary-card';
import { useToast } from './toast';
import { FitLine } from './identity';
import { Avatar, Button } from './ui';

/** Shares text with the phone's share sheet where there is one, otherwise straight to WhatsApp. */
export async function shareText(text: string) {
  if (typeof navigator !== 'undefined' && navigator.share && /Android|iPhone|iPad/.test(navigator.userAgent)) {
    try {
      await navigator.share({ text });
      return;
    } catch (e) {
      if ((e as Error).name === 'AbortError') return;
    }
  }
  window.open(`https://wa.me/?text=${encodeURIComponent(text)}`, '_blank', 'noopener');
}

export const methodName = (p: PayTo, t: (k: TKey) => string) => p.label || t(`pay_${p.kind}` as TKey);

function TransferCard({ group, tr, onPay, nudge }: { group: GroupDetail; tr: Transfer; onPay: (t: Transfer) => void; nudge?: boolean }) {
  const { t, prefs } = useSession();
  const toast = useToast();
  const rtl = prefs.lang === 'ar';
  const x = useMotionValue(0);
  const reveal = useTransform(x, rtl ? [-140, 0] : [0, 140], rtl ? [1, 0] : [0, 1]);
  // Past the point where letting go marks it paid, the tick pops and you feel a light tick.
  const [armed, setArmed] = useState(false);
  const member = (id: string) => group.members.find((p) => p.id === id);
  const name = (id: string) => {
    const m = member(id);
    return m ? (m.isMe ? t('you') : m.name) : '?';
  };
  const amount = money(tr.amount, group.currency, prefs.lang);
  const owesMe = tr.to === group.me;
  const iOwe = tr.from === group.me;
  const ways = iOwe ? (member(tr.to)?.payTo ?? []) : [];

  const payWith = async (p: PayTo) => {
    haptic('light');
    const a = payAction(p, tr.amount, group.currency);
    if ('open' in a) {
      window.open(a.open, '_blank', 'noopener');
      return;
    }
    try {
      await navigator.clipboard.writeText(a.copy);
      toast(t('payCopied', { method: methodName(p, t) }));
    } catch {
      toast(a.copy);
    }
  };

  return (
    <motion.li layout exit={{ opacity: 0, height: 0, marginTop: 0 }} transition={spring} className="relative list-none overflow-hidden rounded-card" data-testid="transfer">
      <motion.div aria-hidden style={{ opacity: reveal }} className="absolute inset-0 flex items-center gap-2 bg-success px-6 t-headline text-white">
        <motion.span animate={{ scale: armed ? 1.25 : 1 }} transition={{ type: 'spring', duration: 0.15, bounce: 0.4 }} className="inline-flex" data-armed={armed || undefined} data-testid="swipe-tick">
          <CheckCircle size={26} weight={armed ? 'fill' : 'bold'} />
        </motion.span>
        {t('markPaid')}
      </motion.div>
      <motion.div
        drag="x"
        dragConstraints={{ left: 0, right: 0 }}
        dragElastic={rtl ? { left: 0.7, right: 0 } : { left: 0, right: 0.7 }}
        style={{ x }}
        onDrag={(_, info) => {
          const far = rtl ? info.offset.x < -110 : info.offset.x > 110;
          if (far !== armed) {
            setArmed(far);
            if (far) haptic('selection');
          }
        }}
        onDragEnd={(_, info) => {
          setArmed(false);
          const far = rtl ? info.offset.x < -110 : info.offset.x > 110;
          if (far) {
            haptic('success');
            onPay(tr);
          }
        }}
        className={`relative flex flex-col gap-3 bg-surface p-4 ${nudge ? 'nudge' : ''}`}
        data-testid="transfer-card"
      >
        {/* Names on the first line, the amount on its own line: long amounts never squeeze the names. */}
        <div className="flex items-center gap-3">
          <Avatar name={member(tr.from)?.name ?? '?'} avatar={member(tr.from)?.avatar} />
          <ArrowRight size={16} className="shrink-0 text-text-3 rtl:-scale-x-100" aria-hidden />
          <Avatar name={member(tr.to)?.name ?? '?'} avatar={member(tr.to)?.avatar} />
          <p className="min-w-0 flex-1 t-body text-text" data-testid="transfer-names">
            {iOwe ? (
              t('youPayTo', { name: name(tr.to) })
            ) : owesMe ? (
              t('paysYou', { name: name(tr.from) })
            ) : (
              <>
                <span className="font-semibold">{name(tr.from)}</span> {t('pays')} <span className="font-semibold">{name(tr.to)}</span>
              </>
            )}
          </p>
        </div>
        <div className="min-w-0">
          <FitLine className="t-title-2 text-text num" testId="transfer-amount">
            {amount}
          </FitLine>
        </div>
        {ways.length ? (
          <div className="flex flex-col gap-2" data-testid="pay-with">
            <div className="flex flex-wrap gap-2">
              {ways.map((p, i) => {
                const a = payAction(p, tr.amount, group.currency);
                return (
                  <button
                    key={`${p.kind}-${i}`}
                    type="button"
                    onClick={() => payWith(p)}
                    className="tap focus-ring inline-flex items-center gap-2 rounded-full bg-accent px-4 t-subhead font-semibold text-on-accent press"
                  >
                    {'open' in a ? <ArrowSquareOut size={18} /> : <Copy size={18} />}
                    {t('payWith', { method: methodName(p, t) })}
                  </button>
                );
              })}
            </div>
            <p className="t-footnote text-text-2">{t('payThenMark')}</p>
          </div>
        ) : null}
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => {
              haptic('success');
              onPay(tr);
            }}
            data-testid="mark-paid"
            aria-describedby="swipe-hint"
            className="tap focus-ring flex flex-1 items-center justify-center gap-2 rounded-full bg-accent-soft t-subhead font-semibold text-on-accent-soft press"
          >
            <Check size={18} weight="bold" />
            {t('markPaid')}
          </button>
          {owesMe ? (
            <button
              type="button"
              onClick={() => {
                haptic('light');
                shareText(t('remindMessage', { name: member(tr.from)?.name ?? '', amount, group: group.name }));
              }}
              data-testid="remind"
              aria-label={t('remindName', { name: name(tr.from) })}
              className="tap focus-ring flex items-center justify-center gap-2 rounded-full bg-surface-2 px-4 t-subhead font-semibold text-text press"
            >
              <BellRinging size={18} />
              {t('remind')}
            </button>
          ) : null}
        </div>
      </motion.div>
    </motion.li>
  );
}

const HINT_KEY = 'nn:swipe-hint-seen';

export function SettlePlan({ group, onPay }: { group: GroupDetail; onPay: (t: Transfer) => void }) {
  const { t, prefs } = useSession();
  const toast = useToast();
  const lang = prefs.lang;
  const [sharing, setSharing] = useState(false);
  // "Swipe right to mark as paid" shows the first time only, with a small nudge of the first card.
  const [hint, setHint] = useState(false);
  useEffect(() => {
    if (!group.transfers.length) return;
    try {
      if (!localStorage.getItem(HINT_KEY)) {
        setHint(true);
        localStorage.setItem(HINT_KEY, '1');
      }
    } catch {}
  }, [group.transfers.length]);

  const shareSummary = async () => {
    setSharing(true);
    try {
      const blob = await summaryCard(group, lang, t);
      const file = new File([blob], `nussnuss-${group.name.replace(/[^\p{L}\p{N}]+/gu, '-').toLowerCase() || 'group'}.png`, { type: 'image/png' });
      if (navigator.canShare?.({ files: [file] })) {
        try {
          await navigator.share({ files: [file], text: t('summaryMade') });
          return;
        } catch (e) {
          if ((e as Error).name === 'AbortError') return;
        }
      }
      saveBlob(blob, file.name);
      toast(t('summarySaved'));
    } catch {
      toast(t('error'));
    } finally {
      setSharing(false);
    }
  };

  return (
    <div className="flex flex-col gap-6">
      {group.transfers.length === 0 ? (
        <SettledMoment title={t('allSettled')} body={t('allSettledBody')} />
      ) : (
        <div className="flex flex-col gap-2">
          {/* Screen readers always hear the hint; it shows on screen only the first time. */}
          <p id="swipe-hint" className={hint ? 't-footnote text-text-2 ps-1' : 'sr-only'} data-testid="swipe-hint" data-shown={hint ? 'true' : undefined}>
            {t('swipeHint')}
          </p>
          <ul className="flex flex-col gap-3">
            <AnimatePresence initial={false}>
              {group.transfers.map((tr, i) => (
                <TransferCard key={`${tr.from}-${tr.to}`} group={group} tr={tr} onPay={onPay} nudge={hint && i === 0} />
              ))}
            </AnimatePresence>
          </ul>
        </div>
      )}
      {group.expenses.length ? (
        <Button variant="secondary" block icon={<ShareFat size={20} />} onClick={shareSummary} disabled={sharing} data-testid="share-summary">
          {t('shareSummary')}
        </Button>
      ) : null}
      <ul className="overflow-hidden rounded-card bg-surface" aria-label="Balances">
        {group.members.map((m) => {
          const b = group.balances[m.id] ?? 0;
          return (
            <li key={m.id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
              <Avatar name={m.name} avatar={m.avatar} size={32} />
              <span className="flex-1 truncate t-body text-text">{m.isMe ? `${m.name} (${t('you')})` : m.name}</span>
              {/* Owing is not an error: plain text, never red. */}
              <span className={`t-subhead font-semibold num whitespace-nowrap ${b > 0 ? 'text-success' : b < 0 ? 'text-text' : 'text-text-2'}`} data-testid={`balance-${m.name}`}>
                {b > 0 ? t('getsBack', { amount: money(b, group.currency, lang) }) : b < 0 ? t('owes', { amount: money(-b, group.currency, lang) }) : t('even')}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
