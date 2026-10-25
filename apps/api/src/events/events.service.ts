import { Injectable, Logger, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import pg from 'pg';
import { filter, interval, map, merge, type Observable, Subject } from 'rxjs';
import { databaseUrl } from '../db/db.module.js';
import { CHANGE_CHANNEL } from '../groups/groups.service.js';

export interface GroupChanged {
  groupId: string;
  version: number;
}

/**
 * Listens to Postgres for "group X is at version N" (sent by GroupsService.touch on commit) and
 * fans it out to open event streams. Every API instance listens, so it works behind a load balancer.
 */
@Injectable()
export class EventsService implements OnModuleInit, OnModuleDestroy {
  private client?: pg.Client;
  private readonly changes = new Subject<GroupChanged>();
  private closed = false;
  private readonly log = new Logger('Events');

  async onModuleInit() {
    if (process.env.EVENTS === 'off') return;
    await this.connect();
  }

  private async connect() {
    if (this.closed) return;
    const c = new pg.Client({ connectionString: databaseUrl() });
    c.on('notification', (n) => {
      const [groupId, v] = (n.payload ?? '').split(':');
      if (groupId && v) this.changes.next({ groupId, version: Number(v) });
    });
    const retry = () => {
      if (this.closed) return;
      this.client = undefined;
      setTimeout(() => void this.connect().catch((e) => this.log.warn(`listen failed: ${(e as Error).message}`)), 2000);
    };
    c.on('error', retry);
    c.on('end', retry);
    await c.connect();
    await c.query(`LISTEN ${CHANGE_CHANNEL}`);
    this.client = c;
  }

  async onModuleDestroy() {
    this.closed = true;
    await this.client?.end().catch(() => undefined);
    this.changes.complete();
  }

  /** Version updates for one group, plus a comment-like ping every 25 s so proxies keep the stream open. */
  stream(groupId: string): Observable<{ type?: string; data: unknown }> {
    return merge(
      this.changes.pipe(
        filter((c) => c.groupId === groupId),
        map((c) => ({ type: 'version', data: { version: c.version } })),
      ),
      interval(25_000).pipe(map(() => ({ type: 'ping', data: {} }))),
    );
  }
}
