import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { computeBalances, groupTotal, simplifyDebts, type ExpenseLike, type SplitMode } from '@nussnuss/core';
import { and, asc, desc, eq, gt, inArray, isNull, sql } from 'drizzle-orm';
import { DB, type Db, type Tx } from '../db/db.module.js';
import { changes, expenseShares, expenses, groups, members, payments } from '../db/schema.js';

export type Entity = 'group' | 'member' | 'expense' | 'payment';
export type Op = 'create' | 'update' | 'delete' | 'restore';

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
}

@Injectable()
export class GroupsService {
  constructor(@Inject(DB) private readonly db: Db) {}

  /** Bumps the group's version and logs the change. Call inside the same transaction as the write. */
  async touch(tx: Tx, groupId: string, entity: Entity, entityId: string, op: Op): Promise<number> {
    const [g] = await tx
      .update(groups)
      .set({ version: sql`${groups.version} + 1`, updatedAt: new Date() })
      .where(eq(groups.id, groupId))
      .returning({ version: groups.version });
    if (!g) return 0;
    await tx.insert(changes).values({ groupId, version: g.version, entity, entityId, op });
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

  async list(userId: string) {
    const mine = await this.db
      .select({ group: groups, memberId: members.id })
      .from(members)
      .innerJoin(groups, eq(groups.id, members.groupId))
      .where(eq(members.userId, userId))
      .orderBy(desc(groups.updatedAt));
    const out = [];
    for (const { group, memberId } of mine) {
      const d = await this.detailRows(group.id);
      const balances = computeBalances(d.core);
      out.push({
        id: group.id,
        name: group.name,
        emoji: group.emoji,
        currency: group.currency,
        version: group.version,
        updatedAt: group.updatedAt.toISOString(),
        memberCount: d.members.length,
        memberNames: d.members.map((m) => m.name),
        total: groupTotal(d.core),
        myBalance: balances[memberId] ?? 0,
      });
    }
    return out;
  }

  private async detailRows(groupId: string) {
    const [g] = await this.db.select().from(groups).where(eq(groups.id, groupId)).limit(1);
    if (!g) throw new NotFoundException('Group not found.');
    const ms = await this.db.select().from(members).where(eq(members.groupId, groupId)).orderBy(asc(members.seq));
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
    const order = new Map(ms.map((m, i) => [m.id, i]));
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
    }));
    const core = {
      currency: g.currency,
      members: ms.map((m) => ({ id: m.id })),
      expenses: expenseViews as ExpenseLike[],
      payments: pays.map((p) => ({ from: p.fromMember, to: p.toMember, amount: p.amountMinor })),
    };
    return { group: g, members: ms, expenses: expenseViews, payments: pays, core };
  }

  /** Everything a group screen needs, with balances and the settle-up plan computed from the rows. */
  async detail(groupId: string, userId: string) {
    const me = await this.memberOf(groupId, userId);
    const d = await this.detailRows(groupId);
    const balances = computeBalances(d.core);
    return {
      id: d.group.id,
      name: d.group.name,
      emoji: d.group.emoji,
      currency: d.group.currency,
      version: d.group.version,
      createdBy: d.group.createdBy,
      updatedAt: d.group.updatedAt.toISOString(),
      me: me.id,
      members: d.members.map((m) => ({ id: m.id, name: m.name, claimed: m.userId !== null, isMe: m.id === me.id })),
      expenses: d.expenses,
      payments: d.payments.map((p) => ({ id: p.id, from: p.fromMember, to: p.toMember, amount: p.amountMinor, paidAt: p.paidAt.toISOString() })),
      total: groupTotal(d.core),
      balances,
      transfers: simplifyDebts(balances, d.members.map((m) => m.id)),
    };
  }

  async changesSince(groupId: string, userId: string, since: number) {
    await this.memberOf(groupId, userId);
    const [g] = await this.db.select({ version: groups.version }).from(groups).where(eq(groups.id, groupId));
    const rows = await this.db
      .select({ version: changes.version, entity: changes.entity, entityId: changes.entityId, op: changes.op, at: changes.at })
      .from(changes)
      .where(and(eq(changes.groupId, groupId), gt(changes.version, since)))
      .orderBy(asc(changes.version))
      .limit(1000);
    return { version: g?.version ?? since, changes: rows.map((r) => ({ ...r, at: r.at.toISOString() })) };
  }
}
