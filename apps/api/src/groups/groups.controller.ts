import {
  Body,
  ConflictException,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  HttpCode,
  Inject,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { CURRENCIES } from '@nussnuss/core';
import { and, eq, isNull } from 'drizzle-orm';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { expenses, groups, members } from '../db/schema.js';
import { type AuthUser, CurrentUser, nameKey, Zod } from '../common/http.js';
import { GroupsService } from './groups.service.js';

const codes = new Set(CURRENCIES.map((c) => c.code));
const currency = z.string().length(3).toUpperCase().refine((c) => codes.has(c), 'Unknown currency.');
const personName = z.string().trim().min(1).max(40);
const emoji = z.string().min(1).max(16);

const CreateGroup = z.object({
  name: z.string().trim().min(1).max(60),
  emoji: emoji.default('🍽️'),
  currency,
  /** The other people, by name. The creator is added automatically under their own name. */
  members: z.array(personName).max(49).default([]),
});
const PatchGroup = z.object({ name: z.string().trim().min(1).max(60).optional(), emoji: emoji.optional(), currency: currency.optional() });
const MemberBody = z.object({ name: personName });
const Since = z.object({ since: z.coerce.number().int().min(0).default(0) });

const isUniqueViolation = (e: unknown) => {
  const err = e as { code?: string; cause?: { code?: string } };
  return err?.code === '23505' || err?.cause?.code === '23505';
};

@Controller('groups')
export class GroupsController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.groupsService.list(user.id);
  }

  @Post()
  async create(@CurrentUser() user: AuthUser, @Body(new Zod(CreateGroup)) body: z.infer<typeof CreateGroup>) {
    const keys = new Set([nameKey(user.displayName)]);
    for (const n of body.members) {
      const k = nameKey(n);
      if (keys.has(k)) throw new ConflictException('Two people have the same name.');
      keys.add(k);
    }
    const id = await this.db.transaction(async (tx) => {
      const [g] = await tx.insert(groups).values({ name: body.name, emoji: body.emoji, currency: body.currency, createdBy: user.id }).returning();
      await tx.insert(members).values([
        { groupId: g.id, userId: user.id, name: user.displayName, nameKey: nameKey(user.displayName) },
        ...body.members.map((n) => ({ groupId: g.id, name: n.trim(), nameKey: nameKey(n) })),
      ]);
      await this.groupsService.touch(tx, g.id, 'group', g.id, 'create');
      return g.id;
    });
    return this.groupsService.detail(id, user.id);
  }

  @Get(':id')
  detail(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.groupsService.detail(id, user.id);
  }

  @Get(':id/changes')
  changes(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query(new Zod(Since)) q: z.infer<typeof Since>) {
    return this.groupsService.changesSince(id, user.id, q.since);
  }

  @Patch(':id')
  async patch(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new Zod(PatchGroup)) body: z.infer<typeof PatchGroup>) {
    await this.groupsService.memberOf(id, user.id);
    await this.db.transaction(async (tx) => {
      if (body.currency) {
        const [g] = await tx.select({ currency: groups.currency }).from(groups).where(eq(groups.id, id));
        if (g && g.currency !== body.currency) {
          const [any] = await tx.select({ id: expenses.id }).from(expenses).where(and(eq(expenses.groupId, id), isNull(expenses.deletedAt))).limit(1);
          if (any) throw new ConflictException('The group currency can only change before the first expense.');
        }
      }
      await tx.update(groups).set(body).where(eq(groups.id, id));
      await this.groupsService.touch(tx, id, 'group', id, 'update');
    });
    return this.groupsService.detail(id, user.id);
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.groupsService.memberOf(id, user.id);
    const [g] = await this.db.select({ createdBy: groups.createdBy }).from(groups).where(eq(groups.id, id));
    if (g?.createdBy && g.createdBy !== user.id) throw new ForbiddenException('Only the person who made the group can delete it.');
    await this.db.delete(groups).where(eq(groups.id, id));
  }

  @Post(':id/members')
  async addMember(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new Zod(MemberBody)) body: z.infer<typeof MemberBody>) {
    await this.groupsService.memberOf(id, user.id);
    try {
      await this.db.transaction(async (tx) => {
        const [m] = await tx.insert(members).values({ groupId: id, name: body.name, nameKey: nameKey(body.name) }).returning();
        await this.groupsService.touch(tx, id, 'member', m.id, 'create');
      });
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException('Someone in this group already has that name.');
      throw e;
    }
    return this.groupsService.detail(id, user.id);
  }

  @Patch(':id/members/:memberId')
  async renameMember(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('memberId', ParseUUIDPipe) memberId: string,
    @Body(new Zod(MemberBody)) body: z.infer<typeof MemberBody>,
  ) {
    await this.groupsService.memberOf(id, user.id);
    try {
      await this.db.transaction(async (tx) => {
        const r = await tx
          .update(members)
          .set({ name: body.name, nameKey: nameKey(body.name) })
          .where(and(eq(members.id, memberId), eq(members.groupId, id)))
          .returning({ id: members.id });
        if (!r.length) throw new NotFoundException('Person not found.');
        await this.groupsService.touch(tx, id, 'member', memberId, 'update');
      });
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException('Someone in this group already has that name.');
      throw e;
    }
    return this.groupsService.detail(id, user.id);
  }
}
