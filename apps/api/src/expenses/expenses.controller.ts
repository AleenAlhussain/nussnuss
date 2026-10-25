import { BadRequestException, Body, Controller, Delete, HttpCode, Inject, NotFoundException, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { and, eq, isNotNull, isNull } from 'drizzle-orm';
import { DB, type Db } from '../db/db.module.js';
import { expenseShares, expenses } from '../db/schema.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';
import { ExpenseBody, type ExpenseInput, ExpensesService } from './expenses.service.js';

@Controller()
export class ExpensesController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
    private readonly expensesService: ExpensesService,
  ) {}

  @Post('groups/:id/expenses')
  async create(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) groupId: string, @Body(new Zod(ExpenseBody)) body: ExpenseInput) {
    await this.groupsService.memberOf(groupId, user.id);
    const id = body.id ?? crypto.randomUUID();
    const existing = await this.db.select({ groupId: expenses.groupId }).from(expenses).where(eq(expenses.id, id)).limit(1);
    if (existing.length) {
      if (existing[0].groupId !== groupId) throw new BadRequestException('That id is already used.');
      return { id, detail: await this.groupsService.detail(groupId, user.id) };
    }
    await this.db.transaction((tx) => this.expensesService.insert(tx, groupId, id, user.id, body));
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
      const { currency, rate } = await this.expensesService.check(tx, groupId, body);
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
