import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { type Avatar, coverKey, expenseInGroupCurrency, groupCover, owedInGroupCurrency } from '@nussnuss/core';
import { and, desc, eq, inArray, isNull, lt, ne, gt, or, sql } from 'drizzle-orm';
import { avatarView, namePersonKey, userPersonKey } from '../common/identity.js';
import { DB, type Db } from '../db/db.module.js';
import { changes, expenses, payments, users } from '../db/schema.js';
import { type Computed, type ExpenseView, GroupsService, type MemberRow } from '../groups/groups.service.js';

export interface Money {
  currency: string;
  amount: number;
}

/** Someone the caller shares a group with. `amount` > 0: they owe the caller. */
interface PersonLink {
  key: string;
  name: string;
  avatar: Avatar;
  claimed: boolean;
  /** One entry per shared group. */
  groups: { c: Computed; member: MemberRow; amount: number }[];
}

/** Adds amounts per currency and drops zeros, biggest first. */
export function sumByCurrency(items: Money[]): Money[] {
  const m = new Map<string, number>();
  for (const i of items) m.set(i.currency, (m.get(i.currency) ?? 0) + i.amount);
  return [...m.entries()]
    .filter(([, v]) => v !== 0)
    .map(([currency, amount]) => ({ currency, amount }))
    .sort((a, b) => Math.abs(b.amount) - Math.abs(a.amount));
}

/** What the caller and one other member owe each other in a group, from its settle-up plan. */
export function pairAmount(c: Computed, other: string): number {
  let v = 0;
  for (const t of c.transfers) {
    if (t.from === other && t.to === c.me) v += t.amount;
    if (t.from === c.me && t.to === other) v -= t.amount;
  }
  return v;
}

/** The caller's share of an expense in the group currency: + when it lent them money, − when it cost them. */
export function impactOf(e: ExpenseView, me: string, groupCurrency: string): number {
  const owed = owedInGroupCurrency(e, groupCurrency)[me] ?? 0;
  return (e.paidBy === me ? expenseInGroupCurrency(e, groupCurrency) : 0) - owed;
}

const groupBrief = (c: Computed) => ({
  id: c.group.id,
  name: c.group.name,
  emoji: c.group.emoji,
  cover: coverKey(groupCover(c.group)),
  currency: c.group.currency,
});

@Injectable()
export class PeopleService {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  /** Everyone the caller shares a group with, merged across groups. */
  links(all: Computed[]): PersonLink[] {
    // A name nobody claimed joins the account of the one person with that name who did, if there is exactly one.
    const claimedByName = new Map<string, Set<string>>();
    for (const c of all)
      for (const m of c.members)
        if (m.userId && m.id !== c.me) {
          const s = claimedByName.get(m.nameKey) ?? new Set<string>();
          s.add(m.userId);
          claimedByName.set(m.nameKey, s);
        }
    const people = new Map<string, PersonLink>();
    for (const c of all) {
      for (const m of c.members) {
        if (m.id === c.me) continue;
        let key: string;
        let claimed = false;
        if (m.userId) {
          key = userPersonKey(m.userId);
          claimed = true;
        } else {
          const owners = claimedByName.get(m.nameKey);
          key = owners?.size === 1 ? userPersonKey([...owners][0]) : namePersonKey(m.nameKey);
        }
        let p = people.get(key);
        if (!p) {
          p = { key, name: m.name, avatar: avatarView(m.avatar, m.name), claimed, groups: [] };
          people.set(key, p);
        }
        // Prefer the account's own name and look over an unclaimed copy.
        if (m.userId && !p.claimed) {
          p.name = m.name;
          p.avatar = avatarView(m.avatar, m.name);
          p.claimed = true;
        }
        p.groups.push({ c, member: m, amount: pairAmount(c, m.id) });
      }
    }
    return [...people.values()];
  }

  async overview(userId: string) {
    const all = await this.groupsService.mine(userId);
    const people = this.links(all);
    const totals = sumByCurrency(all.map((c) => ({ currency: c.group.currency, amount: c.balances[c.me] ?? 0 })));

    // The one thing worth doing next: pay what you owe first, then collect, then get a group going.
    const pairs = people.flatMap((p) => p.groups.filter((g) => g.amount !== 0).map((g) => ({ p, ...g })));
    const owe = pairs.filter((x) => x.amount < 0).sort((a, b) => a.amount - b.amount)[0];
    const owed = pairs.filter((x) => x.amount > 0).sort((a, b) => b.amount - a.amount)[0];
    const pick = owe ?? owed;
    let next: Record<string, unknown> | null = null;
    if (pick) {
      next = {
        kind: pick.amount < 0 ? 'pay' : 'collect',
        person: { key: pick.p.key, name: pick.p.name, avatar: pick.p.avatar },
        amount: Math.abs(pick.amount),
        currency: pick.c.group.currency,
        group: groupBrief(pick.c),
        memberId: pick.member.id,
        payTo: pick.amount < 0 ? pick.member.payTo : [],
      };
    } else {
      const empty = all.find((c) => c.expenses.length === 0);
      if (empty) next = { kind: empty.members.length > 1 ? 'first' : 'invite', group: groupBrief(empty) };
    }

    const order = (p: PersonLink) => {
      const sums = sumByCurrency(p.groups.map((g) => ({ currency: g.c.group.currency, amount: g.amount })));
      return { p, sums, size: sums[0] ? Math.abs(sums[0].amount) : 0 };
    };
    const strip = people
      .map(order)
      .sort((a, b) => b.size - a.size || a.p.name.localeCompare(b.p.name))
      .slice(0, 24)
      .map(({ p, sums }) => ({ key: p.key, name: p.name, avatar: p.avatar, balances: sums, groups: p.groups.length }));

    const [u] = await this.db.select({ seen: users.activitySeenAt }).from(users).where(eq(users.id, userId));
    const unread = await this.unread(userId, all, u?.seen ?? null);
    return { totals, groups: all.length, next, people: strip, unread };
  }

  async person(userId: string, key: string) {
    const all = await this.groupsService.mine(userId);
    const p = this.links(all).find((x) => x.key === key);
    if (!p) throw new NotFoundException('Person not found.');
    const shared: Record<string, unknown>[] = [];
    for (const g of p.groups) {
      for (const e of g.c.expenses) {
        const mine = e.paidBy === g.c.me;
        const theirs = e.paidBy === g.member.id;
        if (!mine && !theirs) continue;
        const owed = owedInGroupCurrency(e, g.c.group.currency);
        // What this expense moved between the two of you: their share if you paid, yours if they did.
        const amount = mine ? owed[g.member.id] ?? 0 : -(owed[g.c.me] ?? 0);
        if (!amount) continue;
        shared.push({
          id: e.id,
          group: groupBrief(g.c),
          title: e.title,
          category: e.category,
          currency: g.c.group.currency,
          amount,
          paidByMe: mine,
          at: e.spentAt,
        });
      }
    }
    shared.sort((a, b) => String(b.at).localeCompare(String(a.at)));
    return {
      key: p.key,
      name: p.name,
      avatar: p.avatar,
      claimed: p.claimed,
      balances: sumByCurrency(p.groups.map((g) => ({ currency: g.c.group.currency, amount: g.amount }))),
      groups: p.groups.map((g) => ({
        ...groupBrief(g.c),
        amount: g.amount,
        memberId: g.member.id,
        me: g.c.me,
        payTo: g.member.payTo,
      })),
      shared: shared.slice(0, 30),
    };
  }

  /** Records a payment in every shared group that isn't even, so the two of you end at zero everywhere. */
  async settleAll(userId: string, key: string, only?: string[]) {
    const all = await this.groupsService.mine(userId);
    const p = this.links(all).find((x) => x.key === key);
    if (!p) throw new NotFoundException('Person not found.');
    const todo = p.groups.filter((g) => g.amount !== 0 && (!only || only.includes(g.c.group.id)));
    const made: { id: string; groupId: string }[] = [];
    await this.db.transaction(async (tx) => {
      for (const g of todo) {
        const from = g.amount > 0 ? g.member.id : g.c.me;
        const to = g.amount > 0 ? g.c.me : g.member.id;
        const [row] = await tx
          .insert(payments)
          .values({ groupId: g.c.group.id, fromMember: from, toMember: to, amountMinor: Math.abs(g.amount), createdBy: userId })
          .returning({ id: payments.id });
        await this.groupsService.touch(tx, g.c.group.id, 'payment', row.id, 'create', userId);
        made.push({ id: row.id, groupId: g.c.group.id });
      }
    });
    return { payments: made, person: await this.person(userId, key) };
  }

  private async unread(userId: string, all: Computed[], seen: Date | null) {
    if (!all.length) return 0;
    const ids = all.map((c) => c.group.id);
    const [r] = await this.db
      .select({ n: sql<number>`count(*)::int` })
      .from(changes)
      .where(
        and(
          inArray(changes.groupId, ids),
          inArray(changes.entity, ['expense', 'payment']),
          inArray(changes.op, ['create', 'update']),
          or(isNull(changes.actor), ne(changes.actor, userId)),
          seen ? gt(changes.at, seen) : undefined,
        ),
      );
    return Math.min(99, r?.n ?? 0);
  }

  /** What happened across the caller's groups, newest first, 30 at a time. */
  async activity(userId: string, opts: { before?: number; group?: string }) {
    const all = await this.groupsService.mine(userId);
    const byGroup = new Map(all.map((c) => [c.group.id, c]));
    const ids = opts.group ? (byGroup.has(opts.group) ? [opts.group] : []) : [...byGroup.keys()];
    const [u] = await this.db.select({ seen: users.activitySeenAt }).from(users).where(eq(users.id, userId));
    const seen = u?.seen ?? null;
    if (!ids.length) return { items: [], next: null, unread: 0 };
    const rows = await this.db
      .select()
      .from(changes)
      .where(
        and(
          inArray(changes.groupId, ids),
          inArray(changes.entity, ['expense', 'payment']),
          inArray(changes.op, ['create', 'update']),
          opts.before ? lt(changes.id, opts.before) : undefined,
        ),
      )
      .orderBy(desc(changes.id))
      .limit(60);
    const expenseIds = rows.filter((r) => r.entity === 'expense').map((r) => r.entityId);
    const paymentIds = rows.filter((r) => r.entity === 'payment').map((r) => r.entityId);
    const liveExpenses = new Set(
      expenseIds.length
        ? (await this.db.select({ id: expenses.id }).from(expenses).where(and(inArray(expenses.id, expenseIds), isNull(expenses.deletedAt)))).map((r) => r.id)
        : [],
    );
    const livePayments = new Set(
      paymentIds.length
        ? (await this.db.select({ id: payments.id }).from(payments).where(and(inArray(payments.id, paymentIds), isNull(payments.deletedAt)))).map((r) => r.id)
        : [],
    );
    const seenEntity = new Set<string>();
    const items: Record<string, unknown>[] = [];
    let last: number | null = null;
    for (const r of rows) {
      if (items.length >= 30) break;
      last = r.id;
      const c = byGroup.get(r.groupId);
      if (!c) continue;
      const once = `${r.entityId}:${r.op}`;
      if (seenEntity.has(once)) continue;
      seenEntity.add(once);
      const person = (m: MemberRow | undefined) => (m ? { name: m.name, me: m.id === c.me, avatar: avatarView(m.avatar, m.name) } : null);
      const base = {
        id: String(r.id),
        op: r.op,
        at: r.at.toISOString(),
        group: groupBrief(c),
        unread: r.actor !== userId && (!seen || r.at > seen),
      };
      if (r.entity === 'expense') {
        if (!liveExpenses.has(r.entityId)) continue;
        const e = c.expenses.find((x) => x.id === r.entityId);
        if (!e) continue;
        const actorId = r.actor ?? (r.op === 'create' ? e.createdBy : null);
        const actor = actorId ? c.members.find((m) => m.userId === actorId) : undefined;
        items.push({
          ...base,
          kind: 'expense',
          actor: person(actor ?? (r.op === 'create' ? c.members.find((m) => m.id === e.paidBy) : undefined)),
          expense: {
            id: e.id,
            title: e.title,
            amount: expenseInGroupCurrency(e, c.group.currency),
            category: e.category,
            paidBy: person(c.members.find((m) => m.id === e.paidBy)),
            impact: impactOf(e, c.me, c.group.currency),
          },
        });
      } else {
        if (!livePayments.has(r.entityId)) continue;
        const pay = c.payments.find((x) => x.id === r.entityId);
        if (!pay) continue;
        const actor = r.actor ? c.members.find((m) => m.userId === r.actor) : c.members.find((m) => m.userId === pay.createdBy);
        items.push({
          ...base,
          kind: 'payment',
          actor: person(actor),
          payment: {
            id: pay.id,
            amount: pay.amountMinor,
            from: person(c.members.find((m) => m.id === pay.fromMember)),
            to: person(c.members.find((m) => m.id === pay.toMember)),
          },
        });
      }
    }
    const more = rows.length === 60 || (items.length >= 30 && last !== rows[rows.length - 1]?.id);
    return { items, next: more && last ? String(last) : null, unread: await this.unread(userId, all, seen) };
  }

  async markSeen(userId: string) {
    await this.db.update(users).set({ activitySeenAt: new Date() }).where(eq(users.id, userId));
  }
}
