import { Body, Controller, Delete, Get, HttpCode, Inject, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { and, desc, eq, inArray, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { devices, groups, notifications } from '../db/schema.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';
import { PlansService } from '../plans/plans.service.js';

const DeviceBody = z.object({ platform: z.enum(['ios', 'android', 'web']), token: z.string().min(8).max(4096) });
const ReadBody = z.object({ ids: z.array(z.uuid()).max(200).optional() });
const RemindBody = z.object({ every: z.enum(['off', 'week']) });

@Controller()
export class NotificationsController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
    private readonly plans: PlansService,
  ) {}

  /** Registers this phone for push notifications (the token comes from APNs or FCM). */
  @Post('me/devices')
  @HttpCode(204)
  async addDevice(@CurrentUser() user: AuthUser, @Body(new Zod(DeviceBody)) body: z.infer<typeof DeviceBody>) {
    await this.db
      .insert(devices)
      .values({ userId: user.id, platform: body.platform, token: body.token })
      .onConflictDoUpdate({ target: devices.token, set: { userId: user.id, platform: body.platform, lastSeenAt: new Date() } });
  }

  @Delete('me/devices/:token')
  @HttpCode(204)
  async removeDevice(@CurrentUser() user: AuthUser, @Param('token') token: string) {
    await this.db.delete(devices).where(and(eq(devices.token, token), eq(devices.userId, user.id)));
  }

  /** The inbox: newest first, the last 50. */
  @Get('me/notifications')
  async list(@CurrentUser() user: AuthUser) {
    const rows = await this.db.select().from(notifications).where(eq(notifications.userId, user.id)).orderBy(desc(notifications.createdAt)).limit(50);
    return rows.map((n) => ({ id: n.id, kind: n.kind, groupId: n.groupId, data: n.data, createdAt: n.createdAt.toISOString(), read: !!n.readAt }));
  }

  @Post('me/notifications/read')
  @HttpCode(204)
  async read(@CurrentUser() user: AuthUser, @Body(new Zod(ReadBody)) body: z.infer<typeof ReadBody>) {
    await this.db
      .update(notifications)
      .set({ readAt: new Date() })
      .where(and(eq(notifications.userId, user.id), isNull(notifications.readAt), ...(body.ids?.length ? [inArray(notifications.id, body.ids)] : [])));
  }

  /** Turns weekly reminders on or off for a group (Plus). */
  @Patch('groups/:id/reminders')
  async reminders(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new Zod(RemindBody)) body: z.infer<typeof RemindBody>) {
    await this.groupsService.memberOf(id, user.id);
    if (body.every !== 'off') await this.plans.requirePlus(user.id, id);
    await this.db.transaction(async (tx) => {
      await tx.update(groups).set({ remindEvery: body.every, ...(body.every === 'off' ? {} : { lastReminderAt: null }) }).where(eq(groups.id, id));
      await this.groupsService.touch(tx, id, 'group', id, 'update');
    });
    return this.groupsService.detail(id, user.id);
  }
}
