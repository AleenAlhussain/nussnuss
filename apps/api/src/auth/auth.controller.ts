import { Body, Controller, Delete, Get, HttpCode, Inject, Patch, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { eq, sql } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { members, sessions, users } from '../db/schema.js';
import { type AuthUser, CurrentUser, newToken, Public, sha256, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';

const name = z.string().trim().min(1).max(40);
const locale = z.enum(['en', 'ar']);
const AnonymousBody = z.object({ name, locale: locale.default('en'), device: z.string().max(80).optional() });
const PatchMe = z.object({ name: name.optional(), locale: locale.optional() }).refine((v) => v.name !== undefined || v.locale !== undefined, 'Nothing to change.');

const meView = (u: { id: string; displayName: string; locale: string }) => ({ id: u.id, name: u.displayName, locale: u.locale });

@Controller()
export class AuthController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  /** Creates an account with no email or password; the token is the only key. */
  @Public()
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('auth/anonymous')
  async anonymous(@Body(new Zod(AnonymousBody)) body: z.infer<typeof AnonymousBody>) {
    const token = newToken();
    const user = await this.db.transaction(async (tx) => {
      const [u] = await tx.insert(users).values({ displayName: body.name, locale: body.locale }).returning();
      await tx.insert(sessions).values({ userId: u.id, tokenHash: sha256(token), device: body.device ?? null });
      return u;
    });
    return { token, user: meView(user) };
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return meView(user);
  }

  @Patch('me')
  async patchMe(@CurrentUser() user: AuthUser, @Body(new Zod(PatchMe)) body: z.infer<typeof PatchMe>) {
    const [u] = await this.db
      .update(users)
      .set({ ...(body.name ? { displayName: body.name } : {}), ...(body.locale ? { locale: body.locale } : {}) })
      .where(eq(users.id, user.id))
      .returning();
    return meView(u);
  }

  /** Signs this device out. */
  @Post('auth/logout')
  @HttpCode(204)
  async logout(@CurrentUser() user: AuthUser) {
    await this.db.delete(sessions).where(eq(sessions.id, user.sessionId));
  }

  /**
   * Deletes the account and every session (App Store guideline 5.1.1(v)).
   * The person's name in shared groups becomes "Former member" so friends' balances still add up.
   */
  @Delete('me')
  @HttpCode(204)
  async deleteMe(@CurrentUser() user: AuthUser) {
    await this.db.transaction(async (tx) => {
      const mine = await tx.select({ id: members.id, groupId: members.groupId }).from(members).where(eq(members.userId, user.id));
      for (const m of mine) {
        const label = `Former member ${m.id.slice(0, 4)}`;
        await tx.update(members).set({ name: label, nameKey: label.toLowerCase(), userId: null }).where(eq(members.id, m.id));
        await this.groupsService.touch(tx, m.groupId, 'member', m.id, 'update');
      }
      if (mine.length) {
        // Groups nobody else has joined are deleted with the account.
        const groupIds = [...new Set(mine.map((m) => m.groupId))];
        await tx.execute(sql`
          delete from groups g
          where g.id in (${sql.join(groupIds.map((id) => sql`${id}`), sql`, `)})
            and not exists (select 1 from members m where m.group_id = g.id and m.user_id is not null)`);
      }
      await tx.delete(users).where(eq(users.id, user.id));
    });
  }
}

