import { BadRequestException, Body, Controller, Delete, HttpCode, Inject, NotFoundException, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { members, payments } from '../db/schema.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';

const PaymentBody = z
  .object({ id: z.uuid().optional(), from: z.uuid(), to: z.uuid(), amount: z.number().int().positive().max(9e14) })
  .refine((p) => p.from !== p.to, 'Someone can’t pay themselves.');

@Controller()
export class PaymentsController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  /** "Mark as paid": records money that changed hands outside the app. */
  @Post('groups/:id/payments')
  async create(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) groupId: string, @Body(new Zod(PaymentBody)) body: z.infer<typeof PaymentBody>) {
    await this.groupsService.memberOf(groupId, user.id);
    const both = await this.db.select({ id: members.id }).from(members).where(eq(members.groupId, groupId));
    const ids = new Set(both.map((m) => m.id));
    if (!ids.has(body.from) || !ids.has(body.to)) throw new BadRequestException('Both people must be in this group.');
    // A client-made id makes "mark as paid" safe to retry (the offline queue replays it).
    if (body.id) {
      const [seen] = await this.db.select({ groupId: payments.groupId }).from(payments).where(eq(payments.id, body.id)).limit(1);
      if (seen) {
        if (seen.groupId !== groupId) throw new BadRequestException('That id is already used.');
        return { id: body.id, detail: await this.groupsService.detail(groupId, user.id) };
      }
    }
    const id = await this.db.transaction(async (tx) => {
      const [p] = await tx
        .insert(payments)
        .values({ ...(body.id ? { id: body.id } : {}), groupId, fromMember: body.from, toMember: body.to, amountMinor: body.amount, createdBy: user.id })
        .returning({ id: payments.id });
      await this.groupsService.touch(tx, groupId, 'payment', p.id, 'create', user.id);
      return p.id;
    });
    return { id, detail: await this.groupsService.detail(groupId, user.id) };
  }

  @Delete('payments/:id')
  @HttpCode(200)
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const [p] = await this.db.select({ groupId: payments.groupId }).from(payments).where(and(eq(payments.id, id), isNull(payments.deletedAt))).limit(1);
    if (!p) throw new NotFoundException('Payment not found.');
    await this.groupsService.memberOf(p.groupId, user.id);
    await this.db.transaction(async (tx) => {
      await tx.update(payments).set({ deletedAt: new Date() }).where(eq(payments.id, id));
      await this.groupsService.touch(tx, p.groupId, 'payment', id, 'delete', user.id);
    });
    return this.groupsService.detail(p.groupId, user.id);
  }
}
