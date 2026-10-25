import { Controller, Get, Inject, Param, ParseUUIDPipe, Req, Res } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { eq } from 'drizzle-orm';
import type { Request, Response } from 'express';
import { DB, type Db } from '../db/db.module.js';
import { groups } from '../db/schema.js';
import { type AuthUser, CurrentUser } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';
import { EventsService } from './events.service.js';

@Controller()
export class EventsController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
    private readonly events: EventsService,
  ) {}

  /**
   * Server-sent events: the group's current version first, then every new version as friends change
   * things. Clients reload the group when the version moves. The token goes in the Authorization header.
   */
  @SkipThrottle()
  @Get('groups/:id/events')
  async stream(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Req() req: Request, @Res() res: Response) {
    await this.groupsService.memberOf(id, user.id);
    const [g] = await this.db.select({ version: groups.version }).from(groups).where(eq(groups.id, id));
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    const send = (event: string, data: unknown) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    send('version', { version: g?.version ?? 0 });
    const sub = this.events.stream(id).subscribe((e) => send(e.type ?? 'message', e.data));
    req.on('close', () => sub.unsubscribe());
  }
}
