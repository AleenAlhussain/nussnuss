import { Body, ConflictException, Controller, Get, GoneException, Inject, NotFoundException, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { and, asc, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { groups, invites, members } from '../db/schema.js';
import { type AuthUser, CurrentUser, nameKey, newToken, Public, sha256, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';

const INVITE_DAYS = 30;
const JoinBody = z.union([z.object({ memberId: z.uuid() }), z.object({ name: z.string().trim().min(1).max(40) })]);
const tokenParam = z.string().min(20).max(100);

@Controller()
export class InvitesController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  /** A link anyone can open to see the group and pick who they are. Valid for 30 days. */
  @Post('groups/:id/invites')
  async create(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) groupId: string) {
    await this.groupsService.memberOf(groupId, user.id);
    const token = newToken();
    const expiresAt = new Date(Date.now() + INVITE_DAYS * 864e5);
    await this.db.insert(invites).values({ groupId, tokenHash: sha256(token), createdBy: user.id, expiresAt });
    return { token, expiresAt: expiresAt.toISOString() };
  }

  private async find(token: string) {
    const t = tokenParam.safeParse(token);
    if (!t.success) throw new NotFoundException('This link is not valid.');
    const [inv] = await this.db.select().from(invites).where(eq(invites.tokenHash, sha256(token))).limit(1);
    if (!inv) throw new NotFoundException('This link is not valid.');
    if (inv.expiresAt.getTime() < Date.now()) throw new GoneException('This link has expired. Ask for a new one.');
    return inv;
  }

  /** What a friend sees before joining: the group's name and who is in it. No amounts. */
  @Public()
  @Get('invites/:token')
  async preview(@Param('token') token: string) {
    const inv = await this.find(token);
    const [g] = await this.db.select().from(groups).where(eq(groups.id, inv.groupId));
    if (!g) throw new NotFoundException('This link is not valid.');
    const ms = await this.db.select().from(members).where(eq(members.groupId, g.id)).orderBy(asc(members.seq));
    return {
      group: { id: g.id, name: g.name, emoji: g.emoji, currency: g.currency },
      members: ms.map((m) => ({ id: m.id, name: m.name, claimed: m.userId !== null })),
    };
  }

  /** Join as one of the open names, or under a new name. Joining twice returns the same place. */
  @Post('invites/:token/join')
  async join(@CurrentUser() user: AuthUser, @Param('token') token: string, @Body(new Zod(JoinBody)) body: z.infer<typeof JoinBody>) {
    const inv = await this.find(token);
    const groupId = inv.groupId;
    const [already] = await this.db.select({ id: members.id }).from(members).where(and(eq(members.groupId, groupId), eq(members.userId, user.id))).limit(1);
    if (already) return this.groupsService.detail(groupId, user.id);

    await this.db.transaction(async (tx) => {
      if ('memberId' in body) {
        const r = await tx
          .update(members)
          .set({ userId: user.id })
          .where(and(eq(members.id, body.memberId), eq(members.groupId, groupId), isNull(members.userId)))
          .returning({ id: members.id });
        if (!r.length) throw new ConflictException('Someone already joined as that person. Pick another name.');
        await this.groupsService.touch(tx, groupId, 'member', r[0].id, 'update');
      } else {
        const key = nameKey(body.name);
        const [taken] = await tx.select({ id: members.id }).from(members).where(and(eq(members.groupId, groupId), eq(members.nameKey, key))).limit(1);
        if (taken) throw new ConflictException('That name is already in the group. Pick it from the list instead.');
        const [m] = await tx.insert(members).values({ groupId, userId: user.id, name: body.name, nameKey: key }).returning({ id: members.id });
        await this.groupsService.touch(tx, groupId, 'member', m.id, 'create');
      }
    });
    return this.groupsService.detail(groupId, user.id);
  }
}

