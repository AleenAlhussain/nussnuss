import { createHash, randomBytes } from 'node:crypto';
import {
  BadRequestException,
  createParamDecorator,
  type ExecutionContext,
  type PipeTransform,
  SetMetadata,
} from '@nestjs/common';
import type { ZodType } from 'zod';

export const IS_PUBLIC = 'nn:isPublic';
/** Route needs no session token. */
export const Public = () => SetMetadata(IS_PUBLIC, true);

export interface AuthUser {
  id: string;
  displayName: string;
  locale: string;
  sessionId: string;
}

export const CurrentUser = createParamDecorator((_data: unknown, ctx: ExecutionContext): AuthUser => {
  const req = ctx.switchToHttp().getRequest<{ user?: AuthUser }>();
  return req.user as AuthUser;
});

/** Validates a body or query with a zod schema; 400 lists every problem with its path. */
export class Zod<T> implements PipeTransform<unknown, T> {
  constructor(private readonly schema: ZodType<T>) {}

  transform(value: unknown): T {
    const r = this.schema.safeParse(value);
    if (!r.success) {
      throw new BadRequestException({
        statusCode: 400,
        error: 'Bad Request',
        message: 'Some fields are not valid.',
        issues: r.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      });
    }
    return r.data;
  }
}

export const newToken = () => randomBytes(32).toString('base64url');
export const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
export const nameKey = (s: string) => s.trim().toLocaleLowerCase().replace(/\s+/g, ' ');
