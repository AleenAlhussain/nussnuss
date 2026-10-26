import { Body, ConflictException, Controller, Get, GoneException, Inject, NotFoundException, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { coverKey, groupCover } from '@nussnuss/core';
import { randomInt } from 'node:crypto';
import { and, asc, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { groups, invites, members, users } from '../db/schema.js';
import { type AuthUser, CurrentUser, nameKey, Public, sha256, Zod } from '../common/http.js';
import { avatarView } from '../common/identity.js';
import { GroupsService } from '../groups/groups.service.js';

const INVITE_DAYS = 30;
const JoinBody = z.union([z.object({ memberId: z.uuid() }), z.object({ name: z.string().trim().min(1).max(40) })]);
const tokenParam = z.string().min(8).max(100);

/** Letters and digits that can't be mistaken for each other when read aloud or typed (no 0/o, 1/l/i). */
const ALPHABET = '23456789abcdefghjkmnpqrstuvwxyz';
const CODE_LENGTH = 10;
/** A short invite code ("k7m2q9xd4p", about 50 bits). Links last 30 days and lookups are rate limited. */
export const shortCode = () => Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
/** Short codes are case-insensitive; older long tokens are kept exactly as they were made. */
const hashOf = (token: string) => sha256(token.length <= 12 ? token.trim().toLowerCase() : token);

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
    const token = shortCode();
    const expiresAt = new Date(Date.now() + INVITE_DAYS * 864e5);
    await this.db.insert(invites).values({ groupId, tokenHash: hashOf(token), createdBy: user.id, expiresAt });
    return { token, path: `/j/${token}`, expiresAt: expiresAt.toISOString() };
  }

  private async find(token: string) {
    const t = tokenParam.safeParse(token);
    if (!t.success) throw new NotFoundException('This link is not valid.');
    const [inv] = await this.db.select().from(invites).where(eq(invites.tokenHash, hashOf(token))).limit(1);
    if (!inv) throw new NotFoundException('This link is not valid.');
    if (inv.expiresAt.getTime() < Date.now()) throw new GoneException('This link has expired. Ask for a new one.');
    return inv;
  }

  /** What a friend sees before joining: the group's name, its cover, who is in it and who invited them. No amounts. */
  @Public()
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Get('invites/:token')
  async preview(@Param('token') token: string) {
    const inv = await this.find(token);
    const [g] = await this.db.select().from(groups).where(eq(groups.id, inv.groupId));
    if (!g) throw new NotFoundException('This link is not valid.');
    const ms = await this.db
      .select({ member: members, avatar: users.avatar })
      .from(members)
      .leftJoin(users, eq(users.id, members.userId))
      .where(eq(members.groupId, g.id))
      .orderBy(asc(members.seq));
    const inviter = inv.createdBy ? ms.find((m) => m.member.userId === inv.createdBy) : undefined;
    return {
      group: { id: g.id, name: g.name, emoji: g.emoji, cover: coverKey(groupCover(g)), currency: g.currency },
      members: ms.map((m) => ({ id: m.member.id, name: m.member.name, claimed: m.member.userId !== null, avatar: avatarView(m.avatar, m.member.name) })),
      invitedBy: inviter ? { name: inviter.member.name, avatar: avatarView(inviter.avatar, inviter.member.name) } : null,
    };
  }

  /** Join as one of the open names, or under a new name. Joining twice returns the same place. */
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
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
        await this.groupsService.touch(tx, groupId, 'member', r[0].id, 'update', user.id);
      } else {
        const key = nameKey(body.name);
        const [taken] = await tx.select({ id: members.id }).from(members).where(and(eq(members.groupId, groupId), eq(members.nameKey, key))).limit(1);
        if (taken) throw new ConflictException('That name is already in the group. Pick it from the list instead.');
        const [m] = await tx.insert(members).values({ groupId, userId: user.id, name: body.name, nameKey: key }).returning({ id: members.id });
        await this.groupsService.touch(tx, groupId, 'member', m.id, 'create', user.id);
      }
    });
    return this.groupsService.detail(groupId, user.id);
  }
}

