'use client';

import { Minus, Plus, Trash } from '@phosphor-icons/react';
import {
  CATEGORIES,
  formatNumber,
  minorToInput,
  normalizeDigits,
  owedInExpenseCurrency,
  parseAmount,
  parseAmountExpression,
  validateSplit,
  type SplitItem,
  type SplitMode,
} from '@nussnuss/core';
import { motion } from 'motion/react';
import { useEffect, useMemo, useState } from 'react';
import type { Expense, ExpenseInput, GroupDetail } from '@/lib/api';
import { haptic, spring } from '@/lib/feel';
import { money } from '@/lib/format';
import { catKey, modeKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { Sheet } from './glass';
import { Keypad } from './keypad';
import { Avatar, Button, Chip, cx, Segmented } from './ui';

const TONES = ['#4F3BD6', '#B0265A', '#0B5FA5', '#9A5B00', '#0F7B4A', '#6B4E9E', '#B93A0E', '#2F6F73'];
const MODES: SplitMode[] = ['equal', 'exact', 'percent', 'shares'];

function parsePercent(s: string) {
  const n = Number(normalizeDigits(s).replace(',', '.'));
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0;
}

export function ExpenseSheet({
  open,
  onClose,
  group,
  editing,
  lastPayer,
  onSave,
  onDelete,
}: {
  open: boolean;
  onClose: () => void;
  group: GroupDetail;
  editing?: Expense | null;
  lastPayer?: string;
  onSave: (input: ExpenseInput) => Promise<void>;
  onDelete?: (e: Expense) => void;
}) {
  const { t, prefs } = useSession();
  const lang = prefs.lang;
  const cur = group.currency;
  const people = group.members;

  const [amountText, setAmountText] = useState('');
  const [title, setTitle] = useState('');
  const [category, setCategory] = useState('other');
  const [paidBy, setPaidBy] = useState(group.me);
  const [mode, setMode] = useState<SplitMode>('equal');
  const [included, setIncluded] = useState<Record<string, boolean>>({});
  const [values, setValues] = useState<Record<string, string>>({});
  const [tried, setTried] = useState(false);
  const [busy, setBusy] = useState(false);

  // Reset every time the sheet opens, from the expense being edited or from smart defaults.
  useEffect(() => {
    if (!open) return;
    setTried(false);
    setBusy(false);
    if (editing) {
      setAmountText(minorToInput(editing.amount, editing.currency));
      setTitle(editing.title);
      setCategory(editing.category);
      setPaidBy(editing.paidBy);
      setMode(editing.mode);
      const byId = Object.fromEntries(editing.items.map((i) => [i.memberId, i.value]));
      setIncluded(Object.fromEntries(people.map((p) => [p.id, (byId[p.id] ?? 0) > 0])));
      setValues(
        Object.fromEntries(
          people.map((p) => {
            const v = byId[p.id] ?? 0;
            if (editing.mode === 'exact') return [p.id, v ? minorToInput(v, editing.currency) : ''];
            if (editing.mode === 'percent') return [p.id, v ? String(v / 100) : ''];
            return [p.id, String(v || (editing.mode === 'shares' ? 0 : ''))];
          }),
        ),
      );
    } else {
      setAmountText('');
      setTitle('');
      setCategory('other');
      setPaidBy(lastPayer && people.some((p) => p.id === lastPayer) ? lastPayer : group.me);
      setMode('equal');
      setIncluded(Object.fromEntries(people.map((p) => [p.id, true])));
      setValues(Object.fromEntries(people.map((p) => [p.id, ''])));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, editing?.id]);

  const amount = parseAmountExpression(amountText, cur) ?? 0;

  const items: SplitItem[] = useMemo(
    () =>
      people.map((p) => {
        if (mode === 'equal') return { memberId: p.id, value: included[p.id] ? 1 : 0 };
        if (mode === 'exact') return { memberId: p.id, value: parseAmount(values[p.id] ?? '', cur) ?? 0 };
        if (mode === 'percent') return { memberId: p.id, value: parsePercent(values[p.id] ?? '') };
        const n = Number(normalizeDigits(values[p.id] ?? ''));
        return { memberId: p.id, value: Number.isInteger(n) && n > 0 ? Math.min(n, 99) : 0 };
      }),
    [people, mode, included, values, cur],
  );

  const err = validateSplit(amount, mode, items, paidBy, people.map((p) => p.id));
  const owed = !err ? owedInExpenseCurrency({ amount, mode, items }) : null;
  const sumExact = mode === 'exact' ? items.reduce((a, b) => a + b.value, 0) : 0;
  const sumPct = mode === 'percent' ? items.reduce((a, b) => a + b.value, 0) : 0;
  const remaining =
    mode === 'exact' && amount ? t('left', { amount: money(amount - sumExact, cur, lang) }) : mode === 'percent' ? t('percentLeft', { n: (10000 - sumPct) / 100 }) : null;

  const message = !tried ? null : !amount ? t('err_amount') : !title.trim() ? t('err_title') : err ? t('err_split') : null;

  const setShares = (id: string, delta: number) => {
    haptic('selection');
    setValues((v) => {
      const n = Math.max(0, Math.min(99, (Number(v[id]) || 0) + delta));
      return { ...v, [id]: String(n) };
    });
  };

  const save = async () => {
    setTried(true);
    if (!amount || !title.trim() || err) {
      haptic('warning');
      return;
    }
    setBusy(true);
    try {
      await onSave({ title: title.trim(), amount, paidBy, mode, items: items.filter((i) => i.value > 0), category });
      haptic('success');
    } finally {
      setBusy(false);
    }
  };

  // The share bar: each person's part of the bill, drawn to scale and updated live.
  const bar = people.map((p, i) => ({ id: p.id, part: owed?.[p.id] ?? 0, tone: TONES[i % TONES.length] })).filter((b) => b.part > 0);

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={editing ? t('editExpense') : t('addExpense')}
      testId="expense-sheet"
      footer={
        <div className="flex flex-col gap-2">
          {message ? (
            <p className="text-center t-footnote text-danger" role="alert" data-testid="expense-error">
              {message}
            </p>
          ) : null}
          <div className="flex gap-2">
            {editing && onDelete ? (
              <Button variant="danger" aria-label={t('delete')} onClick={() => onDelete(editing)} className="w-12 px-0" data-testid="delete-expense">
                <Trash size={20} />
              </Button>
            ) : null}
            <Button block onClick={save} disabled={busy} data-testid="save-expense">
              {t('save')}
            </Button>
          </div>
        </div>
      }
    >
      <div className="flex flex-col gap-5">
        <Keypad value={amountText} onChange={setAmountText} currency={cur} lang={lang} label={t('amount')} />

        <div className="flex flex-col gap-1.5">
          <label htmlFor="exp-title" className="t-footnote font-medium text-text-2 ps-1">
            {t('whatFor')}
          </label>
          <input
            id="exp-title"
            data-testid="title"
            value={title}
            maxLength={80}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={t('whatForPh')}
            className="focus-ring h-12 rounded-control bg-surface px-4 t-body text-text ring-1 ring-separator placeholder:text-text-3"
          />
        </div>

        <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="group" aria-label={t('category')}>
          {CATEGORIES.map((c) => (
            <Chip key={c} selected={category === c} onClick={() => setCategory(c)} testId={`cat-${c}`}>
              {t(catKey(c))}
            </Chip>
          ))}
        </div>

        <div className="flex flex-col gap-2">
          <span className="t-footnote font-medium text-text-2 ps-1">{t('paidBy')}</span>
          <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="radiogroup" aria-label={t('paidBy')}>
            {people.map((p, i) => (
              <button
                key={p.id}
                type="button"
                role="radio"
                aria-checked={paidBy === p.id}
                data-testid="payer"
                onClick={() => {
                  haptic('selection');
                  setPaidBy(p.id);
                }}
                className={cx(
                  'focus-ring flex h-11 shrink-0 items-center gap-2 rounded-full pe-4 ps-1 t-subhead font-medium',
                  paidBy === p.id ? 'bg-accent text-on-accent' : 'bg-surface text-text ring-1 ring-separator',
                )}
              >
                <Avatar name={p.name} index={i} size={34} />
                {p.isMe ? t('you') : p.name}
              </button>
            ))}
          </div>
        </div>

        <div className="flex flex-col gap-3">
          <div className="flex items-baseline justify-between ps-1">
            <span className="t-footnote font-medium text-text-2">{t('split')}</span>
            {remaining ? (
              <span className={cx('t-footnote num', (mode === 'exact' ? amount - sumExact : 10000 - sumPct) === 0 ? 'text-success' : 'text-text-2')} data-testid="remaining">
                {remaining}
              </span>
            ) : null}
          </div>
          <Segmented<SplitMode>
            label={t('split')}
            value={mode}
            testId="mode"
            onChange={(m) => {
              setMode(m);
              setValues(Object.fromEntries(people.map((p) => [p.id, m === 'shares' ? '1' : ''])));
            }}
            options={MODES.map((m) => ({ key: m, label: t(modeKey(m)) }))}
          />

          <div className="flex h-2.5 overflow-hidden rounded-full bg-surface-2" aria-hidden dir="ltr">
            {bar.map((b) => (
              <motion.span key={b.id} layout transition={spring} style={{ flexGrow: b.part, background: b.tone }} className="h-full" />
            ))}
          </div>

          <ul className="overflow-hidden rounded-card bg-surface">
            {people.map((p, i) => {
              const share = owed?.[p.id];
              return (
                <li key={p.id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
                  <Avatar name={p.name} index={i} size={32} />
                  <span className="flex-1 truncate t-body text-text">{p.isMe ? `${p.name} (${t('you')})` : p.name}</span>
                  {mode !== 'exact' && share !== undefined && share > 0 ? (
                    <span className="t-subhead text-text-2 num">{money(share, cur, lang)}</span>
                  ) : null}
                  {mode === 'equal' ? (
                    <input
                      type="checkbox"
                      aria-label={p.name}
                      data-testid="include"
                      checked={!!included[p.id]}
                      onChange={() => {
                        haptic('selection');
                        setIncluded((s) => ({ ...s, [p.id]: !s[p.id] }));
                      }}
                      className="focus-ring h-6 w-6 accent-[var(--nn-accent)]"
                    />
                  ) : mode === 'shares' ? (
                    <span className="flex items-center gap-1">
                      <button type="button" aria-label={`${p.name} −`} onClick={() => setShares(p.id, -1)} className="tap focus-ring grid place-items-center rounded-full bg-surface-2 text-text">
                        <Minus size={18} />
                      </button>
                      <span className="w-6 text-center t-headline num" data-testid="share-count">
                        {values[p.id] || '0'}
                      </span>
                      <button type="button" aria-label={`${p.name} +`} onClick={() => setShares(p.id, 1)} className="tap focus-ring grid place-items-center rounded-full bg-surface-2 text-text">
                        <Plus size={18} />
                      </button>
                    </span>
                  ) : (
                    <input
                      inputMode="decimal"
                      aria-label={`${p.name} ${t(modeKey(mode))}`}
                      data-testid="split-value"
                      value={values[p.id] ?? ''}
                      onChange={(e) => setValues((v) => ({ ...v, [p.id]: e.target.value }))}
                      placeholder={mode === 'percent' ? '%' : formatNumber(0, cur)}
                      className="focus-ring h-11 w-24 rounded-control bg-surface-2 px-3 text-center t-body text-text num"
                    />
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </Sheet>
  );
}
