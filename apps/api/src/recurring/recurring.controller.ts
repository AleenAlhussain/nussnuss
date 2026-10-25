import { Body, Controller, Delete, HttpCode, Inject, NotFoundException, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { recurring } from '../db/schema.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { ExpenseBody, ExpensesService } from '../expenses/expenses.service.js';
import { GroupsService } from '../groups/groups.service.js';
import { PlansService } from '../plans/plans.service.js';

const RecurringBody = ExpenseBody.omit({ id: true, currency: true, rate: true, spentAt: true }).extend({
  every: z.enum(['week', 'month']),
  /** First time it is added. Defaults to now; an existing bill usually starts on its next due date. */
  startAt: z.iso.datetime({ offset: true }).optional(),
});

@Controller()
export class RecurringController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
    private readonly expensesService: ExpensesService,
    private readonly plans: PlansService,
  ) {}

  /** A bill that repeats every week or month (Plus). It is added on its date with the same split. */
  @Post('groups/:id/recurring')
  async create(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) groupId: string, @Body(new Zod(RecurringBody)) body: z.infer<typeof RecurringBody>) {
    await this.groupsService.memberOf(groupId, user.id);
    await this.plans.requirePlus(user.id, groupId);
    const start = body.startAt ? new Date(body.startAt) : new Date();
    await this.db.transaction(async (tx) => {
      await this.expensesService.check(tx, groupId, body);
      const [r] = await tx
        .insert(recurring)
        .values({
          groupId,
          title: body.title,
          amountMinor: body.amount,
          paidBy: body.paidBy,
          splitMode: body.mode,
          items: body.items.filter((i) => i.value > 0),
          category: body.category,
          every: body.every,
          anchorDay: start.getUTCDate(),
          nextAt: start,
          createdBy: user.id,
        })
        .returning({ id: recurring.id });
      await this.groupsService.touch(tx, groupId, 'recurring', r.id, 'create');
    });
    return this.groupsService.detail(groupId, user.id);
  }

  /** Stops it; expenses already added stay. */
  @Delete('recurring/:id')
  @HttpCode(200)
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const [r] = await this.db.select({ groupId: recurring.groupId }).from(recurring).where(and(eq(recurring.id, id), isNull(recurring.deletedAt)));
    if (!r) throw new NotFoundException('That repeating bill was not found.');
    await this.groupsService.memberOf(r.groupId, user.id);
    await this.db.transaction(async (tx) => {
      await tx.update(recurring).set({ deletedAt: new Date() }).where(eq(recurring.id, id));
      await this.groupsService.touch(tx, r.groupId, 'recurring', id, 'delete');
    });
    return this.groupsService.detail(r.groupId, user.id);
  }
}
