import { BadRequestException, Body, Controller, Delete, Get, Inject, NotFoundException, Param, ParseUUIDPipe, Post, Res } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { toneFor } from '@nussnuss/core';
import { and, eq, ne } from 'drizzle-orm';
import type { Response } from 'express';
import { z } from 'zod';
import { type AuthUser, CurrentUser, Public, Zod } from '../common/http.js';
import { meView } from '../common/identity.js';
import { DB, type Db } from '../db/db.module.js';
import { avatars, users } from '../db/schema.js';

/** Base64 of the image; a data: URL prefix is accepted too. 70 KB is plenty for 256×256 (the apps send ~20 KB). */
const PhotoBody = z.object({ data: z.string().min(100).max(96_000) });
const MAX_BYTES = 70_000;

function sniff(b: Buffer): 'image/jpeg' | 'image/png' | 'image/webp' | null {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length > 8 && b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (b.length > 12 && b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP') return 'image/webp';
  return null;
}

/** Profile photos. Each new photo gets a new id, so the image can be cached for good. */
@Controller()
export class AvatarsController {
  constructor(@Inject(DB) private readonly db: Db) {}

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('me/photo')
  async setPhoto(@CurrentUser() user: AuthUser, @Body(new Zod(PhotoBody)) body: z.infer<typeof PhotoBody>) {
    const b64 = body.data.replace(/^data:image\/[a-z]+;base64,/, '');
    const bytes = Buffer.from(b64, 'base64');
    if (bytes.length > MAX_BYTES) throw new BadRequestException('That photo is too big. Try a smaller one.');
    const mime = sniff(bytes);
    if (!mime) throw new BadRequestException('Use a JPEG, PNG or WebP photo.');
    const u = await this.db.transaction(async (tx) => {
      const [cur] = await tx.select().from(users).where(eq(users.id, user.id));
      const [a] = await tx.insert(avatars).values({ userId: user.id, mime, data: bytes.toString('base64') }).returning({ id: avatars.id });
      await tx.delete(avatars).where(and(eq(avatars.userId, user.id), ne(avatars.id, a.id)));
      const tone = cur.avatar?.tone ?? toneFor(cur.displayName);
      const [next] = await tx.update(users).set({ avatar: { kind: 'photo', id: a.id, tone } }).where(eq(users.id, user.id)).returning();
      return next;
    });
    return meView(u);
  }

  @Delete('me/photo')
  async removePhoto(@CurrentUser() user: AuthUser) {
    const u = await this.db.transaction(async (tx) => {
      const [cur] = await tx.select().from(users).where(eq(users.id, user.id));
      await tx.delete(avatars).where(eq(avatars.userId, user.id));
      const tone = cur.avatar?.tone ?? toneFor(cur.displayName);
      const [next] = await tx.update(users).set({ avatar: { kind: 'initial', tone } }).where(eq(users.id, user.id)).returning();
      return next;
    });
    return meView(u);
  }

  /** The image itself. Public by unguessable id, like any photo link a friend is shown. */
  @Public()
  @Get('avatars/:id')
  async photo(@Param('id', ParseUUIDPipe) id: string, @Res() res: Response) {
    const [a] = await this.db.select().from(avatars).where(eq(avatars.id, id)).limit(1);
    if (!a) throw new NotFoundException('Photo not found.');
    res.setHeader('Content-Type', a.mime);
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    // The web app runs on another origin and shows these in <img>.
    res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.end(Buffer.from(a.data, 'base64'));
  }
}
