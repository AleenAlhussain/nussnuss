import { ForbiddenException, Inject, Injectable } from '@nestjs/common';
import { and, desc, eq, gt, inArray, isNull, or } from 'drizzle-orm';
import { DB, type Db, type Tx } from '../db/db.module.js';
import { entitlements, members } from '../db/schema.js';

export type Kind = 'plus' | 'trip_pass' | 'look';

export interface Product {
  kind: Kind;
  /** How long it lasts when the store does not say (Trip Pass: 30 days). Null = for good. */
  days: number | null;
}

/** Store product ids. Override with PRODUCTS='{"id":{"kind":"plus","days":31}}' if the store ids differ. */
export function products(): Record<string, Product> {
  const base: Record<string, Product> = {
    'nussnuss.plus.monthly': { kind: 'plus', days: 31 },
    'nussnuss.plus.yearly': { kind: 'plus', days: 366 },
    'nussnuss.trip_pass': { kind: 'trip_pass', days: 30 },
    'nussnuss.look.night': { kind: 'look', days: null },
    'nussnuss.look.saffron': { kind: 'look', days: null },
  };
  try {
    return { ...base, ...(process.env.PRODUCTS ? (JSON.parse(process.env.PRODUCTS) as Record<string, Product>) : {}) };
  } catch {
    return base;
  }
}

export interface Plan {
  plus: boolean;
  plusUntil: string | null;
  tripPasses: { groupId: string; until: string }[];
  looks: string[];
}

@Injectable()
export class PlansService {
  constructor(@Inject(DB) private readonly db: Db) {}

  async plan(userId: string, now = new Date()): Promise<Plan> {
    const rows = await this.db
      .select()
      .from(entitlements)
      .where(and(eq(entitlements.userId, userId), or(isNull(entitlements.expiresAt), gt(entitlements.expiresAt, now))))
      .orderBy(desc(entitlements.expiresAt));
    const plus = rows.filter((r) => r.kind === 'plus');
    return {
      plus: plus.length > 0,
      plusUntil: plus[0]?.expiresAt?.toISOString() ?? null,
      tripPasses: rows.filter((r) => r.kind === 'trip_pass' && r.groupId).map((r) => ({ groupId: r.groupId!, until: r.expiresAt!.toISOString() })),
      looks: [...new Set(rows.filter((r) => r.kind === 'look').map((r) => r.productId))],
    };
  }

  /** Plus features are open when the person has Plus, or anyone bought a Trip Pass for this group. */
  async hasPlus(userId: string, groupId?: string, now = new Date()): Promise<boolean> {
    const conds = [and(eq(entitlements.userId, userId), eq(entitlements.kind, 'plus'), gt(entitlements.expiresAt, now))];
    if (groupId) conds.push(and(eq(entitlements.groupId, groupId), eq(entitlements.kind, 'trip_pass'), gt(entitlements.expiresAt, now)));
    const [row] = await this.db.select({ id: entitlements.id }).from(entitlements).where(or(...conds)).limit(1);
    return !!row;
  }

  /** For background jobs: anyone in the group has Plus, or the group has a Trip Pass. */
  async groupHasPlus(groupId: string, now = new Date()): Promise<boolean> {
    const ids = (await this.db.select({ userId: members.userId }).from(members).where(eq(members.groupId, groupId)))
      .map((m) => m.userId)
      .filter((x): x is string => !!x);
    const conds = [and(eq(entitlements.groupId, groupId), eq(entitlements.kind, 'trip_pass'), gt(entitlements.expiresAt, now))];
    if (ids.length) conds.push(and(inArray(entitlements.userId, ids), eq(entitlements.kind, 'plus'), gt(entitlements.expiresAt, now)));
    const [row] = await this.db.select({ id: entitlements.id }).from(entitlements).where(or(...conds)).limit(1);
    return !!row;
  }

  async requirePlus(userId: string, groupId?: string) {
    if (!(await this.hasPlus(userId, groupId))) throw new ForbiddenException({ statusCode: 403, error: 'Plus', message: 'This is part of NussNuss Plus.', plus: true });
  }

  /** Records a verified purchase once; the same store transaction never counts twice. */
  async grant(
    tx: Tx | Db,
    g: { userId: string; productId: string; platform: 'apple' | 'google' | 'dev'; transactionId: string; groupId?: string | null; expiresAt?: Date | null },
  ) {
    const p = products()[g.productId];
    if (!p) throw new ForbiddenException('Unknown product.');
    const expiresAt = g.expiresAt !== undefined ? g.expiresAt : p.days === null ? null : new Date(Date.now() + p.days * 864e5);
    await tx
      .insert(entitlements)
      .values({
        userId: g.userId,
        kind: p.kind,
        productId: g.productId,
        groupId: p.kind === 'trip_pass' ? (g.groupId ?? null) : null,
        platform: g.platform,
        transactionId: g.transactionId,
        expiresAt,
      })
      .onConflictDoUpdate({ target: [entitlements.platform, entitlements.transactionId], set: { expiresAt } });
    return p;
  }
}
