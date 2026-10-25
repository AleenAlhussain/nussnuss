import { type CanActivate, type ExecutionContext, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { eq } from 'drizzle-orm';
import type { Request } from 'express';
import { DB, type Db } from '../db/db.module.js';
import { sessions, users } from '../db/schema.js';
import { type AuthUser, IS_PUBLIC, sha256 } from '../common/http.js';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    @Inject(DB) private readonly db: Db,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [ctx.getHandler(), ctx.getClass()]);
    const req = ctx.switchToHttp().getRequest<Request & { user?: AuthUser }>();
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';

    if (token) {
      const [row] = await this.db
        .select({ sessionId: sessions.id, id: users.id, displayName: users.displayName, locale: users.locale })
        .from(sessions)
        .innerJoin(users, eq(users.id, sessions.userId))
        .where(eq(sessions.tokenHash, sha256(token)))
        .limit(1);
      if (row) req.user = row;
    }
    if (isPublic) return true;
    if (!req.user) throw new UnauthorizedException('Sign in to continue.');
    return true;
  }
}
