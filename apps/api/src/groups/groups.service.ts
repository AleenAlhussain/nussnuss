import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { computeBalances, coverKey, groupCover, groupTotal, simplifyDebts, type ExpenseLike, type SplitMode, type Transfer } from '@nussnuss/core';
import { and, asc, desc, eq, gt, inArray, isNull, sql } from 'drizzle-orm';
import { circleView } from '../circles/schedule.js';
import { avatarView } from '../common/identity.js';
import { DB, type Db, type Tx } from '../db/db.module.js';
import {
  changes,
  circlePayments,
  circles,
  entitlements,
  expenseShares,
  expenses,
  groups,
  members,
  payments,
  recurring,
  users,
  type AvatarSetting,
  type PayTo,
} from '../db/schema.js';

export type Entity = 'group' | 'member' | 'expense' | 'payment' | 'circle' | 'recurring';
export type Op = 'create' | 'update' | 'delete' | 'restore';

/** Postgres channel that carries "group X is now at version N" to every API instance (sent on commit). */
export const CHANGE_CHANNEL = 'nn_group_changed';

export interface ExpenseView {
  id: string;
  title: string;
  amount: number;
  currency: string;
  rate: number;
  paidBy: string;
  mode: SplitMode;
  items: { memberId: string; value: number }[];
  category: string;
  spentAt: string;
  createdAt: string;
  updatedAt: string;
  createdBy: string | null;
}

/** A member row with what the group screen needs from their account. */
export interface MemberRow {
  id: string;
  groupId: string;
  userId: string | null;
  name: string;
  nameKey: string;
  payTo: PayTo[];
  avatar: AvatarSetting | null;
}

/** One of the caller's groups with its balances worked out (Home, people, Activity). */
export interface Computed {
  group: typeof groups.$inferSelect;
  me: string;
  members: MemberRow[];
  expenses: ExpenseView[];
  payments: (typeof payments.$inferSelect)[];
  balances: Record<string, number>;
  transfers: Transfer[];
  total: number;
}

@Injectable()
export class GroupsService {
  constructor(@Inject(DB) private readonly db: Db) {}

  /** Bumps the group's version and logs the change. Call inside the same transaction as the write. */
  async touch(tx: Tx, groupId: string, entity: Entity, entityId: string, op: Op, actor: string | null = null): Promise<number> {
    const [g] = await tx
      .update(groups)
      .set({ version: sql`${groups.version} + 1`, updatedAt: new Date() })
      .where(eq(groups.id, groupId))
      .returning({ version: groups.version });
    if (!g) return 0;
    await tx.insert(changes).values({ groupId, version: g.version, entity, entityId, op, actor });
    // NOTIFY is delivered only when the transaction commits, so listeners never see uncommitted versions.
    await tx.execute(sql`select pg_notify(${CHANGE_CHANNEL}, ${`${groupId}:${g.version}`})`);
    return g.version;
  }

  /** The caller's member row in the group. 404 (not 403) when they aren't in it, so ids don't leak. */
  async memberOf(groupId: string, userId: string, tx: Tx = this.db) {
    const [m] = await tx
      .select()
      .from(members)
      .where(and(eq(members.groupId, groupId), eq(members.userId, userId)))
      .limit(1);
    if (!m) throw new NotFoundException('Group not found.');
    return m;
  }

  /** Every group the person is in, newest activity first, with balances and the settle-up plan. */
  async mine(userId: string): Promise<Computed[]> {
    const rows = await this.db
      .select({ groupId: members.groupId, memberId: members.id })
      .from(members)
      .innerJoin(groups, eq(groups.id, members.groupId))
      .where(eq(members.userId, userId))
      .orderBy(desc(groups.updatedAt));
    const out: Computed[] = [];
    for (const r of rows) {
      const d = await this.detailRows(r.groupId);
      const balances = computeBalances(d.core);
      out.push({
        group: d.group,
        me: r.memberId,
        members: d.members,
        expenses: d.expenses,
        payments: d.payments,
        balances,
        transfers: simplifyDebts(balances, d.members.map((m) => m.id)),
        total: groupTotal(d.core),
      });
    }
    return out;
  }

  async list(userId: string) {
    const all = await this.mine(userId);
    return all.map((c) => {
      const latestExpense = c.expenses.reduce<ExpenseView | null>((a, e) => (!a || e.createdAt > a.createdAt ? e : a), null);
      const latestPayment = c.payments[0] ?? null;
      const who = (memberId: string | null | undefined) => {
        const m = c.members.find((x) => x.id === memberId);
        return m ? { name: m.name, me: m.id === c.me } : null;
      };
      const byUser = (userId: string | null) => (userId ? c.members.find((m) => m.userId === userId) : undefined);
      let lastActivity: Record<string, unknown> | null = null;
      if (latestExpense && (!latestPayment || latestExpense.createdAt >= latestPayment.paidAt.toISOString())) {
        const adder = byUser(latestExpense.createdBy) ?? c.members.find((m) => m.id === latestExpense.paidBy);
        lastActivity = { kind: 'expense', who: adder ? { name: adder.name, me: adder.id === c.me } : null, title: latestExpense.title, at: latestExpense.createdAt };
      } else if (latestPayment) {
        lastActivity = { kind: 'payment', from: who(latestPayment.fromMember), to: who(latestPayment.toMember), at: latestPayment.paidAt.toISOString() };
      }
      const allEven = Object.values(c.balances).every((v) => v === 0);
      return {
        id: c.group.id,
        name: c.group.name,
        emoji: c.group.emoji,
        cover: coverKey(groupCover(c.group)),
        currency: c.group.currency,
        version: c.group.version,
        updatedAt: c.group.updatedAt.toISOString(),
        memberCount: c.members.length,
        memberNames: c.members.map((m) => m.name),
        members: c.members.slice(0, 5).map((m) => ({ name: m.name, avatar: avatarView(m.avatar, m.name), me: m.id === c.me })),
        expenseCount: c.expenses.length,
        total: c.total,
        myBalance: c.balances[c.me] ?? 0,
        /** Everyone is even and something was spent: Home folds these away. */
        settled: allEven && c.expenses.length > 0,
        lastActivity,
      };
    });
  }

  private async detailRows(groupId: string) {
    const [g] = await this.db.select().from(groups).where(eq(groups.id, groupId)).limit(1);
    if (!g) throw new NotFoundException('Group not found.');
    const ms = await this.db
      .select({ member: members, payTo: users.payTo, avatar: users.avatar })
      .from(members)
      .leftJoin(users, eq(users.id, members.userId))
      .where(eq(members.groupId, groupId))
      .orderBy(asc(members.seq));
    const ex = await this.db
      .select()
      .from(expenses)
      .where(and(eq(expenses.groupId, groupId), isNull(expenses.deletedAt)))
      .orderBy(desc(expenses.spentAt), desc(expenses.createdAt));
    const shares = ex.length
      ? await this.db.select().from(expenseShares).where(inArray(expenseShares.expenseId, ex.map((e) => e.id)))
      : [];
    const pays = await this.db
      .select()
      .from(payments)
      .where(and(eq(payments.groupId, groupId), isNull(payments.deletedAt)))
      .orderBy(desc(payments.paidAt));
    const byExpense = new Map<string, { memberId: string; value: number }[]>();
    for (const s of shares) {
      const list = byExpense.get(s.expenseId) ?? [];
      list.push({ memberId: s.memberId, value: s.value });
      byExpense.set(s.expenseId, list);
    }
    const order = new Map(ms.map((m, i) => [m.member.id, i]));
    const expenseViews: ExpenseView[] = ex.map((e) => ({
      id: e.id,
      title: e.title,
      amount: e.amountMinor,
      currency: e.currency,
      rate: e.rate,
      paidBy: e.paidBy,
      mode: e.splitMode as SplitMode,
      items: (byExpense.get(e.id) ?? []).sort((a, b) => (order.get(a.memberId) ?? 0) - (order.get(b.memberId) ?? 0)),
      category: e.category,
      spentAt: e.spentAt.toISOString(),
      createdAt: e.createdAt.toISOString(),
      updatedAt: e.updatedAt.toISOString(),
      createdBy: e.createdBy,
    }));
    const core = {
      currency: g.currency,
      members: ms.map((m) => ({ id: m.member.id })),
      expenses: expenseViews as ExpenseLike[],
      payments: pays.map((p) => ({ from: p.fromMember, to: p.toMember, amount: p.amountMinor })),
    };
    const memberRows: MemberRow[] = ms.map((m) => ({
      id: m.member.id,
      groupId: m.member.groupId,
      userId: m.member.userId,
      name: m.member.name,
      nameKey: m.member.nameKey,
      payTo: (m.payTo ?? []) as PayTo[],
      avatar: (m.avatar ?? null) as AvatarSetting | null,
    }));
    return { group: g, members: memberRows, expenses: expenseViews, payments: pays, core };
  }

  /** Everything a group screen needs, with balances and the settle-up plan computed from the rows. */
  async detail(groupId: string, userId: string) {
    const me = await this.memberOf(groupId, userId);
    const d = await this.detailRows(groupId);
    const balances = computeBalances(d.core);
    const cs = await this.db
      .select()
      .from(circles)
      .where(and(eq(circles.groupId, groupId), isNull(circles.deletedAt)))
      .orderBy(asc(circles.createdAt));
    const cps = cs.length ? await this.db.select().from(circlePayments).where(inArray(circlePayments.circleId, cs.map((c) => c.id))) : [];
    const rec = await this.db
      .select()
      .from(recurring)
      .where(and(eq(recurring.groupId, groupId), isNull(recurring.deletedAt)))
      .orderBy(asc(recurring.nextAt));
    const [pass] = await this.db
      .select({ expiresAt: entitlements.expiresAt })
      .from(entitlements)
      .where(and(eq(entitlements.groupId, groupId), eq(entitlements.kind, 'trip_pass'), gt(entitlements.expiresAt, new Date())))
      .orderBy(desc(entitlements.expiresAt))
      .limit(1);
    return {
      id: d.group.id,
      name: d.group.name,
      emoji: d.group.emoji,
      cover: coverKey(groupCover(d.group)),
      currency: d.group.currency,
      version: d.group.version,
      createdBy: d.group.createdBy,
      updatedAt: d.group.updatedAt.toISOString(),
      remindEvery: d.group.remindEvery,
      tripPassUntil: pass?.expiresAt?.toISOString() ?? null,
      me: me.id,
      members: d.members.map((m) => ({
        id: m.id,
        name: m.name,
        claimed: m.userId !== null,
        isMe: m.id === me.id,
        payTo: m.payTo,
        avatar: avatarView(m.avatar, m.name),
      })),
      expenses: d.expenses.map(({ createdBy: _c, ...e }) => e),
      payments: d.payments.map((p) => ({ id: p.id, from: p.fromMember, to: p.toMember, amount: p.amountMinor, paidAt: p.paidAt.toISOString() })),
      total: groupTotal(d.core),
      balances,
      transfers: simplifyDebts(balances, d.members.map((m) => m.id)),
      circles: cs.map((c) => circleView(c, cps.filter((p) => p.circleId === c.id))),
      recurring: rec.map((r) => ({
        id: r.id,
        title: r.title,
        amount: r.amountMinor,
        paidBy: r.paidBy,
        mode: r.splitMode as SplitMode,
        items: r.items,
        category: r.category,
        every: r.every,
        nextAt: r.nextAt.toISOString(),
      })),
    };
  }

  /** Members and the settle-up plan, for background jobs that act on a group without a signed-in member. */
  async snapshot(groupId: string) {
    const d = await this.detailRows(groupId);
    const balances = computeBalances(d.core);
    return { group: d.group, members: d.members, transfers: simplifyDebts(balances, d.members.map((m) => m.id)) };
  }

  async changesSince(groupId: string, userId: string, since: number) {
    await this.memberOf(groupId, userId);
    const [g] = await this.db.select({ version: groups.version }).from(groups).where(eq(groups.id, groupId));
    const rows = await this.db
      .select({ version: changes.version, entity: changes.entity, entityId: changes.entityId, op: changes.op, at: changes.at })
      .from(changes)
      .where(and(eq(changes.groupId, groupId), gt(changes.version, since)))
      .orderBy(asc(changes.version))
      .limit(500);
    return { version: g?.version ?? since, changes: rows.map((r) => ({ ...r, at: r.at.toISOString() })) };
  }
}
