import { BadRequestException, Body, Controller, Delete, HttpCode, Inject, NotFoundException, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { CATEGORIES, CURRENCIES, SPLIT_MODES, validateSplit } from '@nussnuss/core';
import { and, eq, isNotNull, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db, type Tx } from '../db/db.module.js';
import { expenseShares, expenses, groups, members } from '../db/schema.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';

const codes = new Set(CURRENCIES.map((c) => c.code));
const ExpenseBody = z.object({
  /** Client-made id. Sending the same id twice returns the first expense instead of making a copy. */
  id: z.uuid().optional(),
  title: z.string().trim().min(1).max(80),
  amount: z.number().int().positive().max(9e14),
  currency: z.string().length(3).toUpperCase().refine((c) => codes.has(c), 'Unknown currency.').optional(),
  rate: z.number().positive().max(1e9).optional(),
  paidBy: z.uuid(),
  mode: z.enum(SPLIT_MODES as unknown as [string, ...string[]]),
  items: z.array(z.object({ memberId: z.uuid(), value: z.number().int().min(0) })).min(1).max(50),
  category: z.enum(CATEGORIES as unknown as [string, ...string[]]).default('other'),
  spentAt: z.iso.datetime({ offset: true }).optional(),
});
type ExpenseInput = z.infer<typeof ExpenseBody>;

const MESSAGES: Record<string, string> = {
  noAmount: 'Enter an amount.',
  noPeople: 'Pick at least one person to share it.',
  exactMismatch: 'The amounts must add up to the total.',
  percentMismatch: 'The percentages must add up to 100%.',
  noShares: 'Give at least one person a share.',
  payerMissing: 'The person who paid is not in this group.',
};

@Controller()
export class ExpensesController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  /** Checks the split with the same rules the apps use, so a bad split never reaches the database. */
  private async check(tx: Tx, groupId: string, body: ExpenseInput) {
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

  @Post('groups/:id/expenses')
  async create(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) groupId: string, @Body(new Zod(ExpenseBody)) body: ExpenseInput) {
    await this.groupsService.memberOf(groupId, user.id);
    const id = body.id ?? crypto.randomUUID();
    const existing = await this.db.select({ groupId: expenses.groupId }).from(expenses).where(eq(expenses.id, id)).limit(1);
    if (existing.length) {
      if (existing[0].groupId !== groupId) throw new BadRequestException('That id is already used.');
      return { id, detail: await this.groupsService.detail(groupId, user.id) };
    }
    await this.db.transaction(async (tx) => {
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
        createdBy: user.id,
      });
      const items = body.items.filter((i) => i.value > 0);
      await tx.insert(expenseShares).values(items.map((i) => ({ expenseId: id, memberId: i.memberId, value: i.value })));
      await this.groupsService.touch(tx, groupId, 'expense', id, 'create');
    });
    return { id, detail: await this.groupsService.detail(groupId, user.id) };
  }

  private async owned(user: AuthUser, id: string, deleted = false) {
    const [e] = await this.db
      .select({ groupId: expenses.groupId })
      .from(expenses)
      .where(and(eq(expenses.id, id), deleted ? isNotNull(expenses.deletedAt) : isNull(expenses.deletedAt)))
      .limit(1);
    if (!e) throw new NotFoundException('Expense not found.');
    await this.groupsService.memberOf(e.groupId, user.id);
    return e.groupId;
  }

  @Patch('expenses/:id')
  async update(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new Zod(ExpenseBody)) body: ExpenseInput) {
    const groupId = await this.owned(user, id);
    await this.db.transaction(async (tx) => {
      const { currency, rate } = await this.check(tx, groupId, body);
      await tx
        .update(expenses)
        .set({
          title: body.title,
          amountMinor: body.amount,
          currency,
          rate,
          paidBy: body.paidBy,
          splitMode: body.mode,
          category: body.category,
          ...(body.spentAt ? { spentAt: new Date(body.spentAt) } : {}),
          updatedAt: new Date(),
        })
        .where(eq(expenses.id, id));
      await tx.delete(expenseShares).where(eq(expenseShares.expenseId, id));
      await tx.insert(expenseShares).values(body.items.filter((i) => i.value > 0).map((i) => ({ expenseId: id, memberId: i.memberId, value: i.value })));
      await this.groupsService.touch(tx, groupId, 'expense', id, 'update');
    });
    return this.groupsService.detail(groupId, user.id);
  }

  /** Soft delete, so "Undo" can bring it back. */
  @Delete('expenses/:id')
  @HttpCode(200)
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const groupId = await this.owned(user, id);
    await this.db.transaction(async (tx) => {
      await tx.update(expenses).set({ deletedAt: new Date() }).where(eq(expenses.id, id));
      await this.groupsService.touch(tx, groupId, 'expense', id, 'delete');
    });
    return this.groupsService.detail(groupId, user.id);
  }

  @Post('expenses/:id/restore')
  async restore(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const groupId = await this.owned(user, id, true);
    await this.db.transaction(async (tx) => {
      await tx.update(expenses).set({ deletedAt: null }).where(eq(expenses.id, id));
      await this.groupsService.touch(tx, groupId, 'expense', id, 'restore');
    });
    return this.groupsService.detail(groupId, user.id);
  }
}
