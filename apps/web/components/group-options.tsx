'use client';

import { CaretRight, ChartBar, Check, CoinVertical, DownloadSimple, Plus, Printer, Repeat, Ticket, Trash } from '@phosphor-icons/react';
import { memberStats, parseAmount, spendingByCategory } from '@nussnuss/core';
import { useRouter } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import { api, saveBlob, type Circle, type GroupDetail } from '@/lib/api';
import { haptic } from '@/lib/feel';
import { money } from '@/lib/format';
import { catKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { groupHasPlus } from './expense-sheet';
import { Sheet } from './glass';
import { shortDate, usePaywall } from './paywall';
import { useToast } from './toast';
import { Avatar, Button, cx, Field, Segmented } from './ui';

function Row({ icon, title, sub, onClick, trailing, testId }: { icon: ReactNode; title: string; sub?: string; onClick?: () => void; trailing?: ReactNode; testId?: string }) {
  const inner = (
    <>
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-row bg-accent-soft text-on-accent-soft" aria-hidden>
        {icon}
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="t-body text-text">{title}</span>
        {sub ? <span className="t-footnote text-text-2">{sub}</span> : null}
      </span>
      {trailing}
    </>
  );
  const cls = 'flex min-h-14 w-full items-center gap-3 border-b border-separator/60 px-4 py-2 text-start last:border-0';
  return onClick ? (
    <button type="button" onClick={onClick} className={cx('focus-ring', cls)} data-testid={testId}>
      {inner}
    </button>
  ) : (
    <div className={cls} data-testid={testId}>
      {inner}
    </div>
  );
}

function PlusBadge() {
  const { t } = useSession();
  return <span className="shrink-0 rounded-full bg-accent-soft px-2 py-0.5 t-caption font-semibold text-on-accent-soft">{t('needsPlus')}</span>;
}

/** An on/off switch with a real switch role, 51 × 31 like iOS and never below the touch size. */
export function Switch({ on, onChange, label, testId }: { on: boolean; onChange: (v: boolean) => void; label: string; testId?: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      data-testid={testId}
      onClick={() => {
        haptic('selection');
        onChange(!on);
      }}
      className="tap focus-ring grid shrink-0 place-items-center"
    >
      <span className={cx('relative h-[31px] w-[51px] rounded-full transition-colors', on ? 'bg-success' : 'bg-surface-2 ring-1 ring-separator')}>
        <span className={cx('absolute top-[2px] h-[27px] w-[27px] rounded-full bg-white shadow transition-[inset-inline-start]', on ? 'start-[22px]' : 'start-[2px]')} />
      </span>
    </button>
  );
}

/** Spending by category and what each person paid, as plain bars (Plus). */
export function Spending({ g }: { g: GroupDetail }) {
  const { t, prefs } = useSession();
  const cats = spendingByCategory(g.expenses, g.currency);
  const paid = g.members.map((m, i) => ({ m, i, v: memberStats({ currency: g.currency, members: g.members, expenses: g.expenses, payments: [] }, m.id).paid })).filter((x) => x.v > 0);
  const maxC = Math.max(1, ...cats.map((c) => c.amount));
  const maxP = Math.max(1, ...paid.map((p) => p.v));
  if (!cats.length) return null;
  return (
    <div className="flex flex-col gap-4 rounded-card bg-surface p-4" data-testid="spending">
      <div className="flex flex-col gap-2">
        <h3 className="t-subhead font-semibold text-text-2">{t('byCategory')}</h3>
        {cats.map((c) => (
          <div key={c.category} className="flex flex-col gap-1">
            <div className="flex justify-between t-footnote">
              <span className="text-text">{t(catKey(c.category))}</span>
              <span className="text-text-2 num">{money(c.amount, g.currency, prefs.lang)}</span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-surface-2">
              <div className="h-full rounded-full bg-accent" style={{ width: `${(c.amount / maxC) * 100}%` }} />
            </div>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-2">
        <h3 className="t-subhead font-semibold text-text-2">{t('byPerson')}</h3>
        {paid.map(({ m, i, v }) => (
          <div key={m.id} className="flex items-center gap-3">
            <Avatar name={m.name} index={i} size={28} />
            <div className="flex min-w-0 flex-1 flex-col gap-1">
              <div className="flex justify-between t-footnote">
                <span className="truncate text-text">{m.isMe ? t('you') : m.name}</span>
                <span className="text-text-2 num">{money(v, g.currency, prefs.lang)}</span>
              </div>
              <div className="h-2 overflow-hidden rounded-full bg-surface-2">
                <div className="h-full rounded-full bg-highlight" style={{ width: `${(v / maxP) * 100}%` }} />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function GroupOptions({
  open,
  onClose,
  group: g,
  onChange,
  onOpenCircle,
  onNewCircle,
}: {
  open: boolean;
  onClose: () => void;
  group: GroupDetail;
  onChange: (d: GroupDetail) => void;
  onOpenCircle: (c: Circle) => void;
  onNewCircle: () => void;
}) {
  const { t, prefs, plan } = useSession();
  const paywall = usePaywall();
  const toast = useToast();
  const router = useRouter();
  const plus = groupHasPlus(g, plan);
  const [showSpending, setShowSpending] = useState(false);
  useEffect(() => {
    if (open) setShowSpending(false);
  }, [open]);
  const buy = () => paywall.open({ groupId: g.id, onDone: () => api.group(g.id).then(onChange).catch(() => {}) });
  const needPlus = (run: () => void) => () => (plus ? run() : buy());
  const pass = g.tripPassUntil && Date.parse(g.tripPassUntil) > Date.now() ? g.tripPassUntil : null;

  return (
    <Sheet open={open} onClose={onClose} title={t('groupMore')} testId="group-options">
      <div className="flex flex-col gap-5 pb-2">
        <div className="overflow-hidden rounded-card bg-surface">
          {pass ? (
            <Row icon={<Ticket size={20} />} title={t('tripPass')} sub={t('tripOnUntil', { date: shortDate(pass, prefs.lang) })} />
          ) : !plan?.plus ? (
            <Row icon={<Ticket size={20} />} title={t('tripPass')} sub={t('tripPassBody')} onClick={buy} trailing={<CaretRight size={18} className="text-text-3 rtl:-scale-x-100" />} testId="get-trip-pass" />
          ) : null}
          <Row
            icon={<Repeat size={20} />}
            title={t('weeklyReminders')}
            sub={t('weeklyRemindersHint')}
            trailing={
              <Switch
                on={g.remindEvery === 'week'}
                label={t('weeklyReminders')}
                testId="weekly-reminders"
                onChange={(v) => {
                  if (!plus) return buy();
                  api
                    .reminders(g.id, v ? 'week' : 'off')
                    .then(onChange)
                    .catch((e) => toast((e as Error).message));
                }}
              />
            }
          />
          <Row
            icon={<ChartBar size={20} />}
            title={t('spending')}
            onClick={needPlus(() => setShowSpending((s) => !s))}
            trailing={plus ? <CaretRight size={18} className={cx('text-text-3 transition-transform', showSpending ? 'rotate-90' : 'rtl:-scale-x-100')} /> : <PlusBadge />}
            testId="open-spending"
          />
        </div>
        {showSpending && plus ? <Spending g={g} /> : null}

        {g.recurring?.length ? (
          <section className="flex flex-col gap-2">
            <h3 className="t-subhead font-semibold text-text-2 ps-4">{t('recurringTitle')}</h3>
            <div className="overflow-hidden rounded-card bg-surface" data-testid="recurring-list">
              {g.recurring.map((r) => (
                <Row
                  key={r.id}
                  icon={<Repeat size={20} />}
                  title={`${r.title} · ${money(r.amount, g.currency, prefs.lang)}`}
                  sub={`${t(`every_${r.every}`)} · ${t('nextOn', { date: shortDate(r.nextAt, prefs.lang) })}`}
                  trailing={
                    <button
                      type="button"
                      className="tap focus-ring shrink-0 rounded-full px-3 t-footnote font-semibold text-danger"
                      onClick={() =>
                        api
                          .stopRecurring(r.id)
                          .then(onChange)
                          .catch(() => toast(t('error')))
                      }
                    >
                      {t('stopRepeating')}
                    </button>
                  }
                />
              ))}
            </div>
          </section>
        ) : null}

        <section className="flex flex-col gap-2">
          <h3 className="t-subhead font-semibold text-text-2 ps-4">{t('circles')}</h3>
          <div className="overflow-hidden rounded-card bg-surface">
            {(g.circles ?? []).map((c) => (
              <Row
                key={c.id}
                icon={<CoinVertical size={20} />}
                title={c.name}
                sub={`${t('circlePot', { amount: money(c.pot, g.currency, prefs.lang) })} · ${c.status === 'upcoming' ? t('circle_upcoming', { date: shortDate(c.startOn, prefs.lang) }) : t(`circle_${c.status}`)}`}
                onClick={() => onOpenCircle(c)}
                trailing={<CaretRight size={18} className="text-text-3 rtl:-scale-x-100" />}
              />
            ))}
            <Row icon={<Plus size={20} />} title={t('newCircle')} sub={t('circleHint')} onClick={onNewCircle} testId="new-circle" />
          </div>
        </section>

        <div className="overflow-hidden rounded-card bg-surface">
          <Row
            icon={<DownloadSimple size={20} />}
            title={t('exportCsv')}
            onClick={needPlus(() =>
              api
                .exportCsv(g.id)
                .then((b) => saveBlob(b, `${g.name}.csv`))
                .catch(() => toast(t('error'))),
            )}
            trailing={plus ? null : <PlusBadge />}
            testId="export-csv"
          />
          <Row icon={<Printer size={20} />} title={t('print')} onClick={needPlus(() => router.push(`/g/${g.id}/print`))} trailing={plus ? null : <PlusBadge />} testId="print" />
        </div>
      </div>
    </Sheet>
  );
}

/** The running circles, small, above the expenses: whose turn it is and who is late. */
export function CirclesCard({ g, onOpen }: { g: GroupDetail; onOpen: (c: Circle) => void }) {
  const { t, prefs } = useSession();
  const live = (g.circles ?? []).filter((c) => c.status !== 'done');
  if (!live.length) return null;
  const name = (id: string) => {
    const m = g.members.find((x) => x.id === id);
    return m?.isMe ? t('you') : (m?.name ?? '?');
  };
  return (
    <div className="flex flex-col gap-2">
      {live.map((c) => {
        const r = c.rounds[c.current ?? 0];
        const others = c.turns.length - 1;
        return (
          <button key={c.id} type="button" onClick={() => onOpen(c)} className="focus-ring flex items-center gap-3 rounded-card bg-surface p-4 text-start" data-testid="circle-card">
            <span className="grid h-11 w-11 shrink-0 place-items-center rounded-row bg-highlight text-on-highlight" aria-hidden>
              <CoinVertical size={22} weight="fill" />
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="truncate t-headline text-text">{c.name}</span>
              <span className="truncate t-footnote text-text-2">
                {c.status === 'upcoming'
                  ? t('circle_upcoming', { date: shortDate(c.startOn, prefs.lang) })
                  : `${t('circleRound', { n: (c.current ?? 0) + 1 })} · ${r.receiver === g.me ? t('circleYouGet') : t('circleGets', { name: name(r.receiver) })}`}
              </span>
            </span>
            <span className="flex flex-col items-end gap-0.5 text-end">
              <span className="t-footnote text-text-2 num">{t('circlePaidN', { paid: r.paid.length, total: others })}</span>
              {r.late.length ? <span className="t-footnote font-semibold text-danger">{`${r.late.length} ${t('late')}`}</span> : null}
            </span>
          </button>
        );
      })}
    </div>
  );
}

export function CircleSheet({ circle, g, onClose, onChange }: { circle: Circle | null; g: GroupDetail; onClose: () => void; onChange: (d: GroupDetail) => void }) {
  const { t, prefs } = useSession();
  const toast = useToast();
  // Show the latest copy of the circle after each change.
  const c = circle ? (g.circles ?? []).find((x) => x.id === circle.id) ?? circle : null;
  const name = (id: string) => {
    const m = g.members.find((x) => x.id === id);
    return m?.isMe ? t('you') : (m?.name ?? '?');
  };
  const idx = (id: string) => g.members.findIndex((m) => m.id === id);
  const realName = (id: string) => g.members.find((x) => x.id === id)?.name ?? '?';
  return (
    <Sheet open={!!c} onClose={onClose} title={c?.name ?? ''} testId="circle-sheet">
      {c ? (
        <div className="flex flex-col gap-4 pb-2">
          <p className="t-subhead text-text-2">
            {t('circlePot', { amount: money(c.pot, g.currency, prefs.lang) })} · {money(c.amount, g.currency, prefs.lang)} × {c.turns.length} · {t(`every_${c.every}`)}
          </p>
          <p className="rounded-card bg-surface px-4 py-3 t-footnote text-text-2">{t('circleHint')}</p>
          <ol className="flex flex-col gap-3">
            {c.rounds.map((r) => (
              <li key={r.round} className={cx('flex flex-col gap-2 rounded-card bg-surface p-4', c.current === r.round && 'ring-2 ring-accent')}>
                <div className="flex items-center gap-3">
                  <Avatar name={realName(r.receiver)} index={idx(r.receiver)} size={32} />
                  <span className="flex min-w-0 flex-1 flex-col">
                    <span className="t-headline text-text">{r.receiver === g.me ? t('circleYouGet') : t('circleGets', { name: name(r.receiver) })}</span>
                    <span className="t-footnote text-text-2">
                      {t('circleRound', { n: r.round + 1 })} · {t('circleDue', { date: shortDate(r.dueOn, prefs.lang) })}
                    </span>
                  </span>
                  <span className="t-footnote text-text-2 num">{t('circlePaidN', { paid: r.paid.length, total: c.turns.length - 1 })}</span>
                </div>
                <div className="flex flex-wrap gap-2" role="group" aria-label={`${t('circleRound', { n: r.round + 1 })} · ${t('paid')}`}>
                  {c.turns
                    .filter((m) => m !== r.receiver)
                    .map((m) => {
                      const paid = r.paid.includes(m);
                      const late = r.late.includes(m);
                      return (
                        <button
                          key={m}
                          type="button"
                          aria-pressed={paid}
                          onClick={() => {
                            haptic(paid ? 'selection' : 'success');
                            api
                              .circlePaid(c.id, r.round, m, !paid)
                              .then(onChange)
                              .catch((e) => toast((e as Error).message));
                          }}
                          className={cx(
                            'focus-ring flex h-11 items-center gap-1.5 rounded-full pe-3 ps-1 t-footnote font-semibold',
                            paid ? 'bg-success-soft text-success' : late ? 'bg-danger-soft text-danger' : 'bg-surface-2 text-text-2',
                          )}
                          data-testid="circle-member"
                        >
                          <Avatar name={realName(m)} index={idx(m)} size={28} />
                          {name(m)}
                          {paid ? <Check size={16} weight="bold" aria-hidden /> : late ? ` · ${t('late')}` : null}
                        </button>
                      );
                    })}
                </div>
              </li>
            ))}
          </ol>
          <Button
            variant="danger"
            block
            icon={<Trash size={20} />}
            onClick={() =>
              api
                .deleteCircle(c.id)
                .then((d) => {
                  onChange(d);
                  onClose();
                })
                .catch(() => toast(t('error')))
            }
          >
            {t('deleteCircle')}
          </Button>
        </div>
      ) : null}
    </Sheet>
  );
}

const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

export function NewCircleSheet({ open, g, onClose, onCreated }: { open: boolean; g: GroupDetail; onClose: () => void; onCreated: (d: GroupDetail) => void }) {
  const { t, prefs } = useSession();
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [every, setEvery] = useState<'week' | 'month'>('month');
  const [start, setStart] = useState(today());
  const [order, setOrder] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!open) return;
    setName('');
    setAmount('');
    setEvery('month');
    setStart(today());
    setOrder(g.members.map((m) => m.id));
    setError(null);
  }, [open, g.members]);
  const minor = parseAmount(amount, g.currency) ?? 0;
  const create = async () => {
    if (!name.trim()) return setError(t('err_name'));
    if (!minor) return setError(t('err_amount'));
    if (order.length < 2) return setError(t('circleNeedTwo'));
    setBusy(true);
    try {
      onCreated(await api.addCircle(g.id, { name: name.trim(), amount: minor, every, startOn: start, turns: order }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const idx = (id: string) => g.members.findIndex((m) => m.id === id);
  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={t('newCircle')}
      testId="new-circle-sheet"
      footer={
        <div className="flex flex-col gap-2">
          {error ? (
            <p className="text-center t-footnote text-danger" role="alert">
              {error}
            </p>
          ) : null}
          <Button block onClick={create} disabled={busy} data-testid="create-circle">
            {t('create')}
          </Button>
        </div>
      }
    >
      <div className="flex flex-col gap-5">
        <p className="t-footnote text-text-2">{t('circleHint')}</p>
        <Field label={t('circleName')} placeholder={t('circleNamePh')} value={name} maxLength={60} onChange={(e) => setName(e.target.value)} data-testid="circle-name" data-autofocus />
        <Field
          label={`${t('circleEach')} (${g.currency})`}
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          hint={minor ? t('circlePot', { amount: money(minor * order.length, g.currency, prefs.lang) }) : undefined}
          data-testid="circle-amount"
        />
        <div className="flex flex-col gap-1.5">
          <span className="t-footnote font-medium text-text-2 ps-1">{t('circleEvery')}</span>
          <Segmented<'week' | 'month'>
            label={t('circleEvery')}
            value={every}
            onChange={setEvery}
            options={[
              { key: 'week', label: t('every_week') },
              { key: 'month', label: t('every_month') },
            ]}
          />
        </div>
        <Field label={t('circleStart')} type="date" value={start} onChange={(e) => setStart(e.target.value)} data-testid="circle-start" />
        <div className="flex flex-col gap-2">
          <span className="t-footnote font-medium text-text-2 ps-1">{t('circleOrder')}</span>
          <ol className="overflow-hidden rounded-card bg-surface">
            {order.map((id, i) => (
              <li key={id} className="flex min-h-14 items-center gap-3 border-b border-separator/60 px-4 py-2 last:border-0">
                <span className="w-6 text-center t-headline text-text-2 num">{i + 1}</span>
                <Avatar name={g.members[idx(id)]?.name ?? '?'} index={idx(id)} size={32} />
                <span className="flex-1 truncate t-body text-text">{g.members[idx(id)]?.isMe ? t('you') : g.members[idx(id)]?.name}</span>
                {i > 0 ? (
                  <button
                    type="button"
                    aria-label={t('moveUp', { name: g.members[idx(id)]?.name ?? '' })}
                    onClick={() => setOrder((o) => o.map((x, j) => (j === i - 1 ? id : j === i ? o[i - 1] : x)))}
                    className="tap focus-ring grid place-items-center rounded-full text-text-2"
                  >
                    ↑
                  </button>
                ) : null}
                <button
                  type="button"
                  aria-label={`${t('remove')} ${g.members[idx(id)]?.name ?? ''}`}
                  onClick={() => setOrder((o) => o.filter((x) => x !== id))}
                  className="tap focus-ring grid place-items-center rounded-full text-text-2"
                >
                  ✕
                </button>
              </li>
            ))}
          </ol>
          {g.members.some((m) => !order.includes(m.id)) ? (
            <div className="flex flex-wrap gap-2">
              {g.members
                .filter((m) => !order.includes(m.id))
                .map((m) => (
                  <button key={m.id} type="button" onClick={() => setOrder((o) => [...o, m.id])} className="focus-ring inline-flex h-11 items-center gap-2 rounded-full bg-surface px-4 t-subhead text-text ring-1 ring-separator">
                    <Plus size={16} />
                    {m.isMe ? t('you') : m.name}
                  </button>
                ))}
            </div>
          ) : null}
        </div>
      </div>
    </Sheet>
  );
}
