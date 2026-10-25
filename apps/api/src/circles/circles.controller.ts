import { BadRequestException, Body, Controller, Delete, HttpCode, Inject, NotFoundException, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { circlePayments, circles, members } from '../db/schema.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';

const CircleBody = z.object({
  name: z.string().trim().min(1).max(60),
  /** What each person pays in every round, in minor units of the group currency. */
  amount: z.number().int().positive().max(9e14),
  every: z.enum(['week', 'month']),
  startOn: z.iso.date(),
  /** Member ids in the order they take the pot. Everyone appears once. */
  turns: z.array(z.uuid()).min(2).max(50),
});
const PaidBody = z.object({ round: z.number().int().min(0).max(49), memberId: z.uuid() });

/**
 * Money circles (جمعية): tracking only. NussNuss records who paid each round and whose turn it is;
 * the money itself moves between friends outside the app until a licensed payment partner is in place.
 */
@Controller()
export class CirclesController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  @Post('groups/:id/circles')
  async create(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) groupId: string, @Body(new Zod(CircleBody)) body: z.infer<typeof CircleBody>) {
    await this.groupsService.memberOf(groupId, user.id);
    if (new Set(body.turns).size !== body.turns.length) throw new BadRequestException('Each person can take one turn.');
    const ids = new Set((await this.db.select({ id: members.id }).from(members).where(eq(members.groupId, groupId))).map((m) => m.id));
    if (body.turns.some((t) => !ids.has(t))) throw new BadRequestException('Everyone in the circle must be in this group.');
    await this.db.transaction(async (tx) => {
      const [c] = await tx
        .insert(circles)
        .values({ groupId, name: body.name, amountMinor: body.amount, every: body.every, startOn: body.startOn, turns: body.turns, createdBy: user.id })
        .returning({ id: circles.id });
      await this.groupsService.touch(tx, groupId, 'circle', c.id, 'create');
    });
    return this.groupsService.detail(groupId, user.id);
  }

  private async circle(user: AuthUser, id: string) {
    const [c] = await this.db.select().from(circles).where(and(eq(circles.id, id), isNull(circles.deletedAt)));
    if (!c) throw new NotFoundException('That circle was not found.');
    await this.groupsService.memberOf(c.groupId, user.id);
    return c;
  }

  @Post('circles/:id/paid')
  async paid(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new Zod(PaidBody)) body: z.infer<typeof PaidBody>) {
    const c = await this.circle(user, id);
    if (body.round >= c.turns.length) throw new BadRequestException('That round is not part of this circle.');
    if (!c.turns.includes(body.memberId)) throw new BadRequestException('That person is not in this circle.');
    if (c.turns[body.round] === body.memberId) throw new BadRequestException('The person taking the pot does not pay into their own round.');
    await this.db.transaction(async (tx) => {
      await tx.insert(circlePayments).values({ circleId: id, round: body.round, memberId: body.memberId, markedBy: user.id }).onConflictDoNothing();
      await this.groupsService.touch(tx, c.groupId, 'circle', id, 'update');
    });
    return this.groupsService.detail(c.groupId, user.id);
  }

  /** Undo a payment that was marked by mistake. */
  @Post('circles/:id/unpaid')
  async unpaid(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new Zod(PaidBody)) body: z.infer<typeof PaidBody>) {
    const c = await this.circle(user, id);
    await this.db.transaction(async (tx) => {
      await tx
        .delete(circlePayments)
        .where(and(eq(circlePayments.circleId, id), eq(circlePayments.round, body.round), eq(circlePayments.memberId, body.memberId)));
      await this.groupsService.touch(tx, c.groupId, 'circle', id, 'update');
    });
    return this.groupsService.detail(c.groupId, user.id);
  }

  @Delete('circles/:id')
  @HttpCode(200)
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const c = await this.circle(user, id);
    await this.db.transaction(async (tx) => {
      await tx.update(circles).set({ deletedAt: new Date() }).where(eq(circles.id, id));
      await this.groupsService.touch(tx, c.groupId, 'circle', id, 'delete');
    });
    return this.groupsService.detail(c.groupId, user.id);
  }
}
