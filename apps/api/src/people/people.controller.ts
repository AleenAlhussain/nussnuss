import { BadRequestException, Body, Controller, Get, HttpCode, Inject, NotFoundException, Param, Post, Query } from '@nestjs/common';
import { and, eq, inArray, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { DB, type Db } from '../db/db.module.js';
import { payments } from '../db/schema.js';
import { GroupsService } from '../groups/groups.service.js';
import { PeopleService } from './people.service.js';

const keyParam = z.string().regex(/^[un][0-9a-f]{20}$/);
const SettleBody = z.object({ groups: z.array(z.uuid()).max(100).optional() });
const ActivityQuery = z.object({ before: z.coerce.number().int().positive().optional(), group: z.uuid().optional() });
const UndoBody = z.object({ ids: z.array(z.uuid()).min(1).max(100) });

@Controller()
export class PeopleController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly people: PeopleService,
    private readonly groupsService: GroupsService,
  ) {}

  private key(k: string) {
    if (!keyParam.safeParse(k).success) throw new NotFoundException('Person not found.');
    return k;
  }

  /** Home: the overall balance per currency, the next step, and the people strip. */
  @Get('overview')
  overview(@CurrentUser() user: AuthUser) {
    return this.people.overview(user.id);
  }

  /** One person across every group you share: what you owe each other and what you split. */
  @Get('people/:key')
  person(@CurrentUser() user: AuthUser, @Param('key') key: string) {
    return this.people.person(user.id, this.key(key));
  }

  /** "Settle everything": marks every open balance with this person as paid, in one go. */
  @Post('people/:key/settle')
  settle(@CurrentUser() user: AuthUser, @Param('key') key: string, @Body(new Zod(SettleBody)) body: z.infer<typeof SettleBody>) {
    return this.people.settleAll(user.id, this.key(key), body.groups);
  }

  /** Undo for "Settle everything": removes the payments it recorded. */
  @Post('payments/undo')
  @HttpCode(200)
  async undo(@CurrentUser() user: AuthUser, @Body(new Zod(UndoBody)) body: z.infer<typeof UndoBody>) {
    const rows = await this.db
      .select({ id: payments.id, groupId: payments.groupId })
      .from(payments)
      .where(and(inArray(payments.id, body.ids), isNull(payments.deletedAt)));
    if (rows.length !== body.ids.length) throw new BadRequestException('Some of those payments are already gone.');
    for (const g of new Set(rows.map((r) => r.groupId))) await this.groupsService.memberOf(g, user.id);
    await this.db.transaction(async (tx) => {
      for (const r of rows) {
        await tx.update(payments).set({ deletedAt: new Date() }).where(eq(payments.id, r.id));
        await this.groupsService.touch(tx, r.groupId, 'payment', r.id, 'delete', user.id);
      }
    });
    return { undone: rows.length };
  }

  @Get('activity')
  activity(@CurrentUser() user: AuthUser, @Query(new Zod(ActivityQuery)) q: z.infer<typeof ActivityQuery>) {
    return this.people.activity(user.id, q);
  }

  /** The tab badge: how many Activity items are new. */
  @Get('activity/unread')
  async unread(@CurrentUser() user: AuthUser) {
    return { unread: await this.people.unreadCount(user.id) };
  }

  /** "Mark all read". */
  @Post('activity/seen')
  @HttpCode(204)
  async seen(@CurrentUser() user: AuthUser) {
    await this.people.markSeen(user.id);
  }
}
