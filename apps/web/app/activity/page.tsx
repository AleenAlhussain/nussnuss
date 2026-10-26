'use client';

import { Checks } from '@phosphor-icons/react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { BarButton, Screen } from '@/components/glass';
import { Avatar, CategoryTile } from '@/components/identity';
import { PullToRefresh } from '@/components/pull';
import { Button, Chip, Empty } from '@/components/ui';
import { api, type ActivityItem, type GroupSummary } from '@/lib/api';
import { setUnread } from '@/lib/badge';
import { ago, money, whenBucket } from '@/lib/format';
import type { TKey } from '@/lib/i18n';
import { useSession } from '@/lib/session';
import { cachedGroups } from '@/lib/sync';

const BUCKETS = ['today', 'yesterday', 'thisWeek', 'earlier'] as const;

/** What happened across all your groups: who added what, your share, payments; newest first. */
export default function ActivityPage() {
  const { ready, me, t, prefs } = useSession();
  const router = useRouter();
  const lang = prefs.lang;
  const [items, setItems] = useState<ActivityItem[] | null>(null);
  const [next, setNext] = useState<string | null>(null);
  const [group, setGroup] = useState<string | null>(null);
  const [groups, setGroups] = useState<GroupSummary[]>([]);
  const [unread, setUnreadHere] = useState(0);
  const [more, setMore] = useState(false);

  const load = useCallback(async () => {
    try {
      const r = await api.activity(group ? { group } : {});
      setItems(r.items);
      setNext(r.next);
      setUnreadHere(r.unread);
      setUnread(r.unread);
    } catch {
      setItems((x) => x ?? []);
    }
  }, [group]);
  useEffect(() => {
    if (ready && !me) router.replace('/');
    if (!ready || !me) return;
    load();
    cachedGroups().then((g) => g && setGroups(g));
    api.groups().then(setGroups).catch(() => {});
  }, [ready, me, load, router]);

  const markRead = async () => {
    await api.activitySeen().catch(() => {});
    setUnread(0);
    setUnreadHere(0);
    setItems((x) => x?.map((i) => ({ ...i, unread: false })) ?? null);
  };
  const loadMore = async () => {
    if (!next) return;
    setMore(true);
    try {
      const r = await api.activity({ before: next, ...(group ? { group } : {}) });
      setItems((x) => [...(x ?? []), ...r.items]);
      setNext(r.next);
    } finally {
      setMore(false);
    }
  };

  const sections = useMemo(() => {
    const by = new Map<string, ActivityItem[]>();
    for (const i of items ?? []) {
      const b = whenBucket(i.at);
      by.set(b, [...(by.get(b) ?? []), i]);
    }
    return BUCKETS.filter((b) => by.has(b)).map((b) => ({ key: b, items: by.get(b)! }));
  }, [items]);

  const who = (w: { name: string; me?: boolean } | null) => (w?.me ? t('you') : (w?.name ?? '?'));

  const describe = (i: ActivityItem): { line: string; sub: string; amount?: string; positive?: boolean } => {
    const groupName = i.group.name;
    const when = ago(i.at, lang);
    if (i.kind === 'expense') {
      const e = i.expense;
      const mine = !!i.actor?.me;
      const line = mine
        ? i.op === 'update'
          ? t('act_youEdited', { title: e.title })
          : t('act_youAdded', { title: e.title })
        : `${who(i.actor)} ${i.op === 'update' ? t('act_edited', { title: e.title }) : t('act_added', { title: e.title })}`;
      const share = e.impact > 0 ? t('youLent', { amount: money(e.impact, i.group.currency, lang) }) : e.impact < 0 ? t('yourShare', { amount: money(-e.impact, i.group.currency, lang) }) : t('notInvolved');
      return { line, sub: `${groupName} · ${when} · ${share}`, amount: money(e.amount, i.group.currency, lang) };
    }
    const p = i.payment;
    const amount = money(p.amount, i.group.currency, lang);
    let line: string;
    if (i.actor?.me) line = p.to?.me ? t('act_youGot', { name: who(p.from) }) : t('act_youPaid', { name: who(p.to) });
    else if (p.to?.me) line = `${who(i.actor ?? p.from)} ${t('act_paidYou')}`;
    else line = `${who(i.actor ?? p.from)} ${t('act_paid', { name: who(p.to) })}`;
    return { line, sub: `${groupName} · ${when}`, amount, positive: !!p.to?.me };
  };

  return (
    <Screen
      title={t('tabActivity')}
      testId="activity"
      actions={
        unread ? (
          <BarButton label={t('markAllRead')} onClick={markRead} testId="mark-all-read">
            <Checks size={22} />
          </BarButton>
        ) : null
      }
    >
      {groups.length > 1 ? (
        <div className="-mx-5 flex gap-2 overflow-x-auto px-5 pb-1" role="group" aria-label={t('tabActivity')} data-testid="activity-filter">
          <Chip selected={!group} onClick={() => setGroup(null)} testId="filter-all">
            {t('everything')}
          </Chip>
          {groups.map((g) => (
            <Chip key={g.id} selected={group === g.id} onClick={() => setGroup(g.id)} testId="filter-group">
              {g.name}
            </Chip>
          ))}
        </div>
      ) : null}
      {items === null ? (
        <div className="flex flex-col gap-3" aria-busy="true">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="flex items-center gap-3 rounded-card bg-surface p-4">
              <div className="shimmer h-11 w-11 rounded-full" />
              <div className="flex flex-1 flex-col gap-2">
                <div className="shimmer h-4 w-2/3 rounded" />
                <div className="shimmer h-3 w-1/2 rounded" />
              </div>
            </div>
          ))}
        </div>
      ) : !items.length ? (
        <Empty title={t('noActivityTitle')} body={t('noActivityBody')} />
      ) : (
        <div className="flex flex-col gap-5">
          {sections.map((s) => (
            <section key={s.key} className="flex flex-col gap-2">
              <h2 className="t-subhead font-semibold text-text-2 ps-4">{t(s.key as TKey)}</h2>
              <ul className="overflow-hidden rounded-card bg-surface">
                {s.items.map((i) => {
                  const d = describe(i);
                  return (
                    <li key={i.id} className="border-b border-separator/60 last:border-0">
                      <Link href={`/g/${i.group.id}`} className="focus-ring flex min-h-16 items-center gap-3 px-4 py-3" data-testid="activity-row" data-unread={i.unread ? 'true' : undefined}>
                        <span className="relative">
                          {i.actor ? <Avatar name={i.actor.name} avatar={i.actor.avatar} size={44} /> : <CategoryTile category={i.kind === 'expense' ? i.expense.category : 'other'} size={44} />}
                          {i.kind === 'expense' && i.actor ? (
                            <span className="absolute -bottom-1 -end-1 rounded-full ring-2 ring-surface">
                              <CategoryTile category={i.expense.category} size={20} />
                            </span>
                          ) : null}
                        </span>
                        <span className="flex min-w-0 flex-1 flex-col">
                          <span className="line-clamp-2 t-body text-text">{d.line}</span>
                          <span className="line-clamp-2 t-footnote text-text-2">{d.sub}</span>
                        </span>
                        {d.amount ? <span className={`t-subhead font-semibold num whitespace-nowrap ${d.positive ? 'text-success' : 'text-text'}`}>{d.amount}</span> : null}
                        {i.unread ? (
                          <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-accent" aria-label={t('newItem')} role="img" data-testid="unread-dot" />
                        ) : null}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </section>
          ))}
          {next ? (
            <Button variant="secondary" block onClick={loadMore} disabled={more} data-testid="activity-more">
              {t('showMore')}
            </Button>
          ) : null}
        </div>
      )}
      <PullToRefresh onRefresh={load} />
    </Screen>
  );
}
