'use client';

import { ArrowCounterClockwise, CaretDown, Minus, Plus, Trash, X } from '@phosphor-icons/react';
import {
  CATEGORIES,
  CURRENCIES,
  formatNumber,
  itemizedSplit,
  minorToInput,
  normalizeDigits,
  owedInExpenseCurrency,
  parseAmount,
  parseAmountExpression,
  suggestTitles,
  validateSplit,
  type SplitItem,
  type SplitMode,
} from '@nussnuss/core';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { api, ApiError, newId, type Expense, type ExpenseInput, type GroupDetail, type Plan } from '@/lib/api';
import { haptic, shake, spring } from '@/lib/feel';
import { money } from '@/lib/format';
import { catKey, modeKey, type TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { Sheet } from './glass';
import { Keypad } from './keypad';
import { usePaywall } from './paywall';
import { Avatar, Button, Chip, cx, ErrorText, Segmented } from './ui';

const TONES = ['#4F3BD6', '#B0265A', '#0B5FA5', '#9A5B00', '#0F7B4A', '#6B4E9E', '#B93A0E', '#2F6F73'];
type Mode = SplitMode | 'items';
const MODES: Mode[] = ['equal', 'exact', 'percent', 'shares', 'items'];
export type Every = 'none' | 'week' | 'month';

interface Line {
  key: string;
  name: string;
  price: string;
  members: string[];
}

function parsePercent(s: string) {
  const n = Number(normalizeDigits(s).replace(',', '.'));
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0;
}

function parseRate(s: string) {
  const n = Number(normalizeDigits(s).replace(',', '.'));
  return Number.isFinite(n) && n > 0 && n < 1e7 ? n : 0;
}

/** Plus features are open in a group when I have Plus, I bought its Trip Pass, or anyone in it did. */
export function groupHasPlus(g: GroupDetail, plan: Plan | null) {
  const now = Date.now();
  return !!plan?.plus || !!plan?.tripPasses.some((p) => p.groupId === g.id && Date.parse(p.until) > now) || (!!g.tripPassUntil && Date.parse(g.tripPassUntil) > now);
}

/**
 * Adding an expense in three taps: type the amount, keep (or tap) the suggested title, save.
 * Who paid defaults to you, the split to everyone equally; Details opens the rest only when needed.
 */
export function ExpenseSheet({
  open,
  onClose,
  group,
  editing,
  lastPayer,
  onSave,
  onDelete,
  onRepeat,
}: {
  open: boolean;
  onClose: () => void;
  group: GroupDetail;
  editing?: Expense | null;
  lastPayer?: string;
  onSave: (input: ExpenseInput, every: Every) => Promise<void>;
  onDelete?: (e: Expense) => void;
  onRepeat?: (e: Expense) => void;
}) {
  const { t, prefs, plan } = useSession();
  const paywall = usePaywall();
  const lang = prefs.lang;
  const people = group.members;
  const ids = useMemo(() => people.map((p) => p.id), [people]);
  const plus = groupHasPlus(group, plan);

  const [amountText, setAmountText] = useState('');
  const [title, setTitle] = useState('');
  const [category, setCategory] = useState<string | null>(null);
  const [paidBy, setPaidBy] = useState(group.me);
  const [mode, setMode] = useState<Mode>('equal');
  const [included, setIncluded] = useState<Record<string, boolean>>({});
  const [values, setValues] = useState<Record<string, string>>({});
  const [lines, setLines] = useState<Line[]>([]);
  const [cur, setCur] = useState(group.currency);
  const [rateText, setRateText] = useState('');
  const [rateLive, setRateLive] = useState(false);
  const [every, setEvery] = useState<Every>('none');
  const [details, setDetails] = useState(false);
  const [tried, setTried] = useState(false);
  // Counts failed saves: each one shakes the message (and the amount, when it is missing).
  const [miss, setMiss] = useState(0);
  const pad = useRef<HTMLDivElement>(null);
  const [busy, setBusy] = useState(false);
  const rateFor = useRef('');

  const suggestions = useMemo(
    () =>
      suggestTitles({
        recent: group.expenses.map((e) => ({ title: e.title, category: e.category })),
        hour: new Date().getHours(),
        emoji: group.emoji,
        label: (k) => t(`sug_${k}` as TKey),
      }).map((s) => ({ label: s.title ?? t(`sug_${s.key}` as TKey), category: s.category })),
    // Suggestions are worked out once per opening, so chips don't shuffle while typing.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [open, group.id, lang],
  );

  useEffect(() => {
    if (!open) return;
    setTried(false);
    setBusy(false);
    setLines([]);
    setRateLive(false);
    setEvery('none');
    if (editing) {
      setAmountText(minorToInput(editing.amount, editing.currency));
      setTitle(editing.title);
      setCategory(editing.category);
      setPaidBy(editing.paidBy);
      setMode(editing.mode);
      setCur(editing.currency);
      setRateText(editing.currency === group.currency ? '' : String(editing.rate));
      setDetails(true);
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
      setCategory(null);
      setPaidBy(lastPayer && people.some((p) => p.id === lastPayer) ? lastPayer : group.me);
      setMode('equal');
      setCur(group.currency);
      setRateText('');
      setDetails(false);
      setIncluded(Object.fromEntries(people.map((p) => [p.id, true])));
      setValues(Object.fromEntries(people.map((p) => [p.id, ''])));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, editing?.id]);

  // Live exchange rate (Plus): filled in when another currency is picked, still editable.
  useEffect(() => {
    if (!open || cur === group.currency || !plus || rateFor.current === cur) return;
    rateFor.current = cur;
    api
      .rate(cur, group.currency, group.id)
      .then((r) => {
        setRateText(String(Number(r.rate.toPrecision(6))));
        setRateLive(true);
      })
      .catch(() => {});
  }, [open, cur, group.currency, group.id, plus]);

  const amount = parseAmountExpression(amountText, cur) ?? 0;
  const rate = cur === group.currency ? 1 : parseRate(rateText);
  const shownTitle = title.trim() || suggestions[0]?.label || t('cat_other');

  const categoryFor = (name: string) => {
    const k = name.trim().toLocaleLowerCase();
    const recent = group.expenses.find((e) => e.title.trim().toLocaleLowerCase() === k);
    if (recent) return recent.category;
    return suggestions.find((s) => s.label.toLocaleLowerCase() === k)?.category ?? 'other';
  };
  const cat = category ?? categoryFor(shownTitle);

  const receipt = useMemo(() => {
    if (mode !== 'items') return null;
    return itemizedSplit(
      amount,
      lines.map((l) => ({ price: parseAmount(l.price, cur) ?? 0, members: l.members })),
      ids,
    );
  }, [mode, lines, amount, cur, ids]);

  const items: SplitItem[] = useMemo(
    () =>
      mode === 'items'
        ? (receipt?.items ?? [])
        : people.map((p) => {
            if (mode === 'equal') return { memberId: p.id, value: included[p.id] ? 1 : 0 };
            if (mode === 'exact') return { memberId: p.id, value: parseAmount(values[p.id] ?? '', cur) ?? 0 };
            if (mode === 'percent') return { memberId: p.id, value: parsePercent(values[p.id] ?? '') };
            const n = Number(normalizeDigits(values[p.id] ?? ''));
            return { memberId: p.id, value: Number.isInteger(n) && n > 0 ? Math.min(n, 99) : 0 };
          }),
    [people, mode, included, values, cur, receipt],
  );
  const apiMode: SplitMode = mode === 'items' ? 'exact' : mode;

  const err = mode === 'items' ? (receipt ? null : 'items') : validateSplit(amount, mode, items, paidBy, ids);
  const owed = !err && amount ? owedInExpenseCurrency({ amount, mode: apiMode, items }) : null;
  const sumExact = mode === 'exact' ? items.reduce((a, b) => a + b.value, 0) : 0;
  const sumPct = mode === 'percent' ? items.reduce((a, b) => a + b.value, 0) : 0;
  const remaining =
    mode === 'exact' && amount ? t('left', { amount: money(amount - sumExact, cur, lang) }) : mode === 'percent' ? t('percentLeft', { n: (10000 - sumPct) / 100 }) : null;
  const linesTotal = lines.reduce((a, l) => a + (parseAmount(l.price, cur) ?? 0), 0);

  const message = !tried
    ? null
    : !amount
      ? t('err_amount')
      : !rate
        ? t('err_rate')
        : err
          ? mode === 'items' && linesTotal > amount
            ? t('itemsOver')
            : t('err_split')
          : null;

  // Details, folded into one line: who paid, how it is split, the category, and anything unusual.
  const payer = people.find((p) => p.id === paidBy);
  const includedCount = people.filter((p) => included[p.id]).length;
  const summary = [
    paidBy === group.me ? t('youPaid') : t('paidByName', { name: payer?.name ?? '?' }),
    mode === 'equal' ? (includedCount === people.length ? t('splitEqualAll') : t('splitEqualN', { n: includedCount })) : t(modeKey(mode as SplitMode)),
    t(catKey(cat)),
    ...(cur !== group.currency ? [cur] : []),
    ...(every !== 'none' ? [t(`every_${every}`)] : []),
  ].join(' · ');

  const setShares = (id: string, delta: number) => {
    haptic('selection');
    setValues((v) => {
      const n = Math.max(0, Math.min(99, (Number(v[id]) || 0) + delta));
      return { ...v, [id]: String(n) };
    });
  };

  const save = async () => {
    setTried(true);
    if (!amount || !rate || err) {
      setMiss((n) => n + 1);
      if (!amount) shake(pad.current);
      if (err || !rate) setDetails(true);
      return;
    }
    setBusy(true);
    try {
      await onSave(
        {
          title: shownTitle.slice(0, 80),
          amount,
          currency: cur,
          rate,
          paidBy,
          mode: apiMode,
          items: items.filter((i) => i.value > 0),
          category: cat,
        },
        every,
      );
      haptic('success');
    } finally {
      setBusy(false);
    }
  };

  const pickEvery = (e: Every) => {
    if (e !== 'none' && !plus) {
      paywall.open({ groupId: group.id });
      return;
    }
    setEvery(e);
  };

  const pickMode = (m: Mode) => {
    if (m === 'items' && !plus) {
      paywall.open({ groupId: group.id });
      return;
    }
    setMode(m);
    setValues(Object.fromEntries(people.map((p) => [p.id, m === 'shares' ? '1' : ''])));
    if (m === 'items' && !lines.length) setLines([{ key: newId(), name: '', price: '', members: [...ids] }]);
  };

  const bar = people.map((p, i) => ({ id: p.id, part: owed?.[p.id] ?? 0, tone: TONES[i % TONES.length] })).filter((b) => b.part > 0);
  const last = !editing ? group.expenses[0] : undefined;

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={editing ? t('editExpense') : t('addExpense')}
      testId="expense-sheet"
      morph={!editing}
      footer={
        <div className="flex flex-col gap-2">
          <ErrorText nonce={miss} testId="expense-error">
            {message}
          </ErrorText>
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
        {last && onRepeat ? (
          <button
            type="button"
            onClick={() => onRepeat(last)}
            data-testid="repeat-last"
            className="focus-ring -mb-2 inline-flex h-11 max-w-full items-center gap-2 self-center rounded-full bg-surface px-4 t-subhead font-medium text-text-2 ring-1 ring-separator"
          >
            <ArrowCounterClockwise size={18} aria-hidden />
            <span className="truncate">{t('repeatLast', { title: last.title })}</span>
          </button>
        ) : null}

        <div ref={pad} data-testid="amount-pad">
          <Keypad value={amountText} onChange={setAmountText} currency={cur} lang={lang} label={t('amount')} />
        </div>

        <div className="flex flex-col gap-2">
          <label htmlFor="exp-title" className="t-footnote font-medium text-text-2 ps-1">
            {t('whatFor')}
          </label>
          <input
            id="exp-title"
            data-testid="title"
            value={title}
            maxLength={80}
            enterKeyHint="done"
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') save();
            }}
            placeholder={suggestions[0]?.label ?? t('whatForPh')}
            className="focus-ring h-12 rounded-control bg-surface px-4 t-body text-text ring-1 ring-separator placeholder:text-text-3"
          />
          {suggestions.length ? (
            <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="group" aria-label={t('suggestions')}>
              {suggestions.map((s) => (
                <Chip
                  key={s.label}
                  selected={title.trim().toLocaleLowerCase() === s.label.toLocaleLowerCase()}
                  onClick={() => {
                    setTitle(s.label);
                    setCategory(null);
                  }}
                  testId="suggestion"
                >
                  {s.label}
                </Chip>
              ))}
            </div>
          ) : null}
        </div>

        <div className="overflow-hidden rounded-card bg-surface">
          <button
            type="button"
            aria-expanded={details}
            aria-controls="exp-details"
            onClick={() => {
              haptic('selection');
              setDetails((d) => !d);
            }}
            data-testid="details"
            className="focus-ring flex min-h-14 w-full items-center gap-3 px-4 py-2 text-start"
          >
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="t-headline text-text">{t('details')}</span>
              <span className="truncate t-footnote text-text-2" data-testid="details-summary">
                {summary}
              </span>
            </span>
            <motion.span animate={{ rotate: details ? 180 : 0 }} transition={spring} className="text-text-2" aria-hidden>
              <CaretDown size={20} />
            </motion.span>
          </button>
        </div>

        <AnimatePresence initial={false}>
          {details ? (
            <motion.div
              id="exp-details"
              key="details"
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={spring}
              className="-mx-1 overflow-hidden px-1"
            >
              <div className="flex flex-col gap-5 pb-1 pt-0.5">
                <div className="flex flex-col gap-2">
                  <span className="t-footnote font-medium text-text-2 ps-1">{t('category')}</span>
                  <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="group" aria-label={t('category')}>
                    {CATEGORIES.map((c) => (
                      <Chip key={c} selected={cat === c} onClick={() => setCategory(c)} testId={`cat-${c}`}>
                        {t(catKey(c))}
                      </Chip>
                    ))}
                  </div>
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
                  <div className="-mx-5 overflow-x-auto px-5">
                    <div className="min-w-[22rem]">
                      <Segmented<Mode> label={t('split')} value={mode} testId="mode" onChange={pickMode} options={MODES.map((m) => ({ key: m, label: t(`mode_${m}` as TKey) }))} />
                    </div>
                  </div>

                  <div className="flex h-2.5 overflow-hidden rounded-full bg-surface-2" aria-hidden dir="ltr">
                    {bar.map((b) => (
                      <motion.span key={b.id} layout transition={spring} style={{ flexGrow: b.part, background: b.tone }} className="h-full" />
                    ))}
                  </div>

                  {mode === 'items' ? (
                    <ReceiptLines lines={lines} setLines={setLines} people={people} cur={cur} rest={receipt?.rest ?? 0} />
                  ) : null}

                  <ul className="overflow-hidden rounded-card bg-surface">
                    {people.map((p, i) => {
                      const share = owed?.[p.id];
                      return (
                        <li key={p.id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
                          <Avatar name={p.name} index={i} size={32} />
                          <span className="flex-1 truncate t-body text-text">{p.isMe ? `${p.name} (${t('you')})` : p.name}</span>
                          {mode !== 'exact' && share !== undefined && share > 0 ? <span className="t-subhead text-text-2 num">{money(share, cur, lang)}</span> : null}
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
                          ) : mode === 'items' ? null : (
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

                <div className="flex flex-col gap-2">
                  <span className="t-footnote font-medium text-text-2 ps-1">{t('paidIn')}</span>
                  <div className="flex gap-2">
                    <select
                      aria-label={t('paidIn')}
                      data-testid="expense-currency"
                      value={cur}
                      onChange={(e) => {
                        setCur(e.target.value);
                        setRateLive(false);
                        if (e.target.value === group.currency) setRateText('');
                      }}
                      className="focus-ring h-12 w-32 shrink-0 rounded-control bg-surface px-3 t-body text-text ring-1 ring-separator"
                    >
                      {CURRENCIES.map((c) => (
                        <option key={c.code} value={c.code}>
                          {c.code}
                        </option>
                      ))}
                    </select>
                    {cur !== group.currency ? (
                      <input
                        inputMode="decimal"
                        aria-label={t('rate')}
                        data-testid="rate"
                        value={rateText}
                        onChange={(e) => {
                          setRateText(e.target.value);
                          setRateLive(false);
                        }}
                        placeholder={t('rate')}
                        className="focus-ring h-12 min-w-0 flex-1 rounded-control bg-surface px-4 t-body text-text ring-1 ring-separator num"
                      />
                    ) : null}
                  </div>
                  {cur !== group.currency && rate ? (
                    <p className="t-footnote text-text-2 ps-1 num" data-testid="rate-line">
                      {t('rateLine', { from: cur, rate: String(rate), to: group.currency })}
                      {rateLive ? ` · ${t('rateLive')}` : ''}
                    </p>
                  ) : null}
                </div>

                {!editing ? (
                  <div className="flex flex-col gap-2">
                    <span className="t-footnote font-medium text-text-2 ps-1">
                      {t('repeats')}
                      {!plus ? <span className="ms-2 rounded-full bg-accent-soft px-2 py-0.5 t-caption text-on-accent-soft">{t('needsPlus')}</span> : null}
                    </span>
                    <Segmented<Every>
                      label={t('repeats')}
                      value={every}
                      testId="every"
                      onChange={pickEvery}
                      options={(['none', 'week', 'month'] as const).map((k) => ({ key: k, label: t(`every_${k}`) }))}
                    />
                  </div>
                ) : null}
              </div>
            </motion.div>
          ) : null}
        </AnimatePresence>
      </div>
    </Sheet>
  );
}

/** Receipt lines for the Items split: what it was, its price, and who had it. */
function ReceiptLines({
  lines,
  setLines,
  people,
  cur,
  rest,
}: {
  lines: Line[];
  setLines: (f: (l: Line[]) => Line[]) => void;
  people: GroupDetail['members'];
  cur: string;
  rest: number;
}) {
  const { t, prefs } = useSession();
  const set = (key: string, patch: Partial<Line>) => setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...patch } : l)));
  return (
    <div className="flex flex-col gap-2" data-testid="receipt">
      {lines.map((l, n) => (
        <div key={l.key} className="flex flex-col gap-2 rounded-card bg-surface p-3">
          <div className="flex gap-2">
            <input
              aria-label={`${t('itemName')} ${n + 1}`}
              value={l.name}
              maxLength={60}
              onChange={(e) => set(l.key, { name: e.target.value })}
              placeholder={t('itemName')}
              className="focus-ring h-11 min-w-0 flex-1 rounded-control bg-surface-2 px-3 t-body text-text placeholder:text-text-3"
            />
            <input
              aria-label={`${t('itemPrice')} ${n + 1}`}
              data-testid="item-price"
              inputMode="decimal"
              value={l.price}
              onChange={(e) => set(l.key, { price: e.target.value })}
              placeholder={formatNumber(0, cur)}
              className="focus-ring h-11 w-24 rounded-control bg-surface-2 px-3 text-center t-body text-text num"
            />
            <button type="button" aria-label={`${t('delete')} ${l.name || n + 1}`} onClick={() => setLines((ls) => ls.filter((x) => x.key !== l.key))} className="tap focus-ring grid place-items-center rounded-full text-text-2">
              <X size={18} />
            </button>
          </div>
          <div className="flex flex-wrap gap-1.5" role="group" aria-label={l.name || `${t('itemName')} ${n + 1}`}>
            {people.map((p, i) => {
              const on = l.members.includes(p.id);
              return (
                <button
                  key={p.id}
                  type="button"
                  aria-pressed={on}
                  onClick={() => {
                    haptic('selection');
                    set(l.key, { members: on ? l.members.filter((m) => m !== p.id) : [...l.members, p.id] });
                  }}
                  className={cx('focus-ring flex h-11 items-center gap-1.5 rounded-full pe-3 ps-1 t-footnote font-medium', on ? 'bg-accent-soft text-on-accent-soft' : 'bg-surface-2 text-text-2')}
                >
                  <Avatar name={p.name} index={i} size={28} />
                  {p.isMe ? t('you') : p.name}
                </button>
              );
            })}
          </div>
        </div>
      ))}
      <div className="flex items-center justify-between gap-2">
        <Button variant="plain" icon={<Plus size={18} />} onClick={() => setLines((ls) => [...ls, { key: newId(), name: '', price: '', members: people.map((p) => p.id) }])} data-testid="add-item">
          {t('addItem')}
        </Button>
        {rest > 0 ? <span className="t-footnote text-text-2 num">{t('itemsRest', { amount: money(rest, cur, prefs.lang) })}</span> : null}
      </div>
    </div>
  );
}

/** "Repeat" with a fresh id and today's date: the same bill again in one tap. */
export function repeatInput(e: Expense): ExpenseInput & { id: string } {
  return { id: newId(), title: e.title, amount: e.amount, currency: e.currency, rate: e.rate, paidBy: e.paidBy, mode: e.mode, items: e.items, category: e.category };
}

export const isPlusError = (e: unknown) => e instanceof ApiError && e.plus;
