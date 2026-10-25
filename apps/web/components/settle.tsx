'use client';

import { ArrowRight, Check } from '@phosphor-icons/react';
import type { Transfer } from '@nussnuss/core';
import { AnimatePresence, motion, useMotionValue, useTransform } from 'motion/react';
import type { GroupDetail } from '@/lib/api';
import { haptic, spring } from '@/lib/feel';
import { money } from '@/lib/format';
import { useSession } from '@/lib/session';
import { SettledMoment } from './coin';
import { Avatar } from './ui';

function TransferCard({ group, tr, onPay }: { group: GroupDetail; tr: Transfer; onPay: (t: Transfer) => void }) {
  const { t, prefs } = useSession();
  const rtl = prefs.lang === 'ar';
  const x = useMotionValue(0);
  const reveal = useTransform(x, rtl ? [-140, 0] : [0, 140], rtl ? [1, 0] : [0, 1]);
  const idx = (id: string) => group.members.findIndex((m) => m.id === id);
  const name = (id: string) => {
    const m = group.members.find((p) => p.id === id);
    return m ? (m.isMe ? t('you') : m.name) : '?';
  };

  return (
    <motion.li layout exit={{ opacity: 0, height: 0, marginTop: 0 }} transition={spring} className="relative list-none overflow-hidden rounded-card" data-testid="transfer">
      <motion.div aria-hidden style={{ opacity: reveal }} className="absolute inset-0 flex items-center gap-2 bg-success px-6 t-headline text-white">
        <Check size={22} weight="bold" />
        {t('markPaid')}
      </motion.div>
      <motion.div
        drag="x"
        dragConstraints={{ left: 0, right: 0 }}
        dragElastic={rtl ? { left: 0.7, right: 0 } : { left: 0, right: 0.7 }}
        style={{ x }}
        onDragEnd={(_, info) => {
          const far = rtl ? info.offset.x < -110 : info.offset.x > 110;
          if (far) {
            haptic('success');
            onPay(tr);
          }
        }}
        className="relative flex flex-col gap-3 bg-surface p-4"
      >
        <div className="flex items-center gap-3">
          <Avatar name={name(tr.from)} index={idx(tr.from)} />
          <ArrowRight size={16} className="text-text-3 rtl:-scale-x-100" aria-hidden />
          <Avatar name={name(tr.to)} index={idx(tr.to)} />
          <p className="min-w-0 flex-1 t-body text-text">
            <span className="font-semibold">{name(tr.from)}</span> {t('pays')} <span className="font-semibold">{name(tr.to)}</span>
          </p>
          <span className="t-headline text-text num">{money(tr.amount, group.currency, prefs.lang)}</span>
        </div>
        <button
          type="button"
          onClick={() => {
            haptic('success');
            onPay(tr);
          }}
          data-testid="mark-paid"
          aria-describedby="swipe-hint"
          className="tap focus-ring flex items-center justify-center gap-2 rounded-full bg-accent-soft t-subhead font-semibold text-on-accent-soft active:scale-[0.98]"
        >
          <Check size={18} weight="bold" />
          {t('markPaid')}
        </button>
      </motion.div>
    </motion.li>
  );
}

export function SettlePlan({ group, onPay }: { group: GroupDetail; onPay: (t: Transfer) => void }) {
  const { t, prefs } = useSession();
  const lang = prefs.lang;
  return (
    <div className="flex flex-col gap-6">
      {group.transfers.length === 0 ? (
        <SettledMoment title={t('allSettled')} body={t('allSettledBody')} />
      ) : (
        <div className="flex flex-col gap-2">
          <p id="swipe-hint" className="t-footnote text-text-2 ps-1">
            {t('swipeHint')}
          </p>
          <ul className="flex flex-col gap-3">
            <AnimatePresence initial={false}>
              {group.transfers.map((tr) => (
                <TransferCard key={`${tr.from}-${tr.to}`} group={group} tr={tr} onPay={onPay} />
              ))}
            </AnimatePresence>
          </ul>
        </div>
      )}
      <ul className="overflow-hidden rounded-card bg-surface" aria-label="Balances">
        {group.members.map((m, i) => {
          const b = group.balances[m.id] ?? 0;
          return (
            <li key={m.id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
              <Avatar name={m.name} index={i} size={32} />
              <span className="flex-1 truncate t-body text-text">{m.isMe ? `${m.name} (${t('you')})` : m.name}</span>
              <span className={`t-subhead font-semibold num ${b > 0 ? 'text-success' : b < 0 ? 'text-danger' : 'text-text-2'}`} data-testid={`balance-${m.name}`}>
                {b > 0 ? t('getsBack', { amount: money(b, group.currency, lang) }) : b < 0 ? t('owes', { amount: money(-b, group.currency, lang) }) : t('even')}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
