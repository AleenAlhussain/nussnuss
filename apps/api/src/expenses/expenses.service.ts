import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { CATEGORIES, CURRENCIES, SPLIT_MODES, validateSplit } from '@nussnuss/core';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db, type Tx } from '../db/db.module.js';
import { expenseShares, expenses, groups, members } from '../db/schema.js';
import { GroupsService } from '../groups/groups.service.js';

const codes = new Set(CURRENCIES.map((c) => c.code));

export const SplitItems = z.array(z.object({ memberId: z.uuid(), value: z.number().int().min(0) })).min(1).max(50);

export const ExpenseBody = z.object({
  /** Client-made id. Sending the same id twice returns the first expense instead of making a copy. */
  id: z.uuid().optional(),
  title: z.string().trim().min(1).max(80),
  amount: z.number().int().positive().max(9e14),
  currency: z.string().length(3).toUpperCase().refine((c) => codes.has(c), 'Unknown currency.').optional(),
  rate: z.number().positive().max(1e9).optional(),
  paidBy: z.uuid(),
  mode: z.enum(SPLIT_MODES as unknown as [string, ...string[]]),
  items: SplitItems,
  category: z.enum(CATEGORIES as unknown as [string, ...string[]]).default('other'),
  spentAt: z.iso.datetime({ offset: true }).optional(),
});
export type ExpenseInput = z.infer<typeof ExpenseBody>;

const MESSAGES: Record<string, string> = {
  noAmount: 'Enter an amount.',
  noPeople: 'Pick at least one person to share it.',
  exactMismatch: 'The amounts must add up to the total.',
  percentMismatch: 'The percentages must add up to 100%.',
  noShares: 'Give at least one person a share.',
  payerMissing: 'The person who paid is not in this group.',
};

@Injectable()
export class ExpensesService {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  /** Checks the split with the same rules the apps use, so a bad split never reaches the database. */
  async check(tx: Tx, groupId: string, body: Pick<ExpenseInput, 'amount' | 'currency' | 'rate' | 'paidBy' | 'mode' | 'items'>) {
    const [g] = await tx.select({ currency: groups.currency }).from(groups).where(eq(groups.id, groupId));
    if (!g) throw new NotFoundException('Group not found.');
    const ids = (await tx.select({ id: members.id }).from(members).where(eq(members.groupId, groupId))).map((m) => m.id);
    const known = new Set(ids);
    if (body.items.some((i) => !known.has(i.memberId))) throw new BadRequestException('Everyone in the split must be in this group.');
    if (new Set(body.items.map((i) => i.memberId)).size !== body.items.length) throw new BadRequestException('Each person can appear once.');
    const currency = body.currency ?? g.currency;
    if (currency !== g.currency && !body.rate) throw new BadRequestException(`Add the exchange rate from ${currency} to ${g.currency}.`);
    const err = validateSplit(body.amount, body.mode as never, body.items, body.paidBy, ids);
    if (err) throw new BadRequestException(MESSAGES[err] ?? 'The split is not valid.');
    return { currency, rate: currency === g.currency ? 1 : body.rate! };
  }

  /** Inserts a checked expense and its shares inside `tx`. Returns false when that id already exists. */
  async insert(tx: Tx, groupId: string, id: string, createdBy: string | null, body: Omit<ExpenseInput, 'id'>): Promise<boolean> {
    const [existing] = await tx.select({ id: expenses.id }).from(expenses).where(eq(expenses.id, id)).limit(1);
    if (existing) return false;
    const { currency, rate } = await this.check(tx, groupId, body);
    await tx.insert(expenses).values({
      id,
      groupId,
      title: body.title,
      amountMinor: body.amount,
      currency,
      rate,
      paidBy: body.paidBy,
      splitMode: body.mode,
      category: body.category,
      spentAt: body.spentAt ? new Date(body.spentAt) : new Date(),
      createdBy,
    });
    const items = body.items.filter((i) => i.value > 0);
    await tx.insert(expenseShares).values(items.map((i) => ({ expenseId: id, memberId: i.memberId, value: i.value })));
    await this.groupsService.touch(tx, groupId, 'expense', id, 'create', createdBy);
    return true;
  }

  get database() {
    return this.db;
  }
}
