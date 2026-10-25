import { Controller, Get, Inject } from '@nestjs/common';
import { sql } from 'drizzle-orm';
import { DB, type Db } from './db/db.module.js';
import { Public } from './common/http.js';

@Controller('health')
export class HealthController {
  constructor(@Inject(DB) private readonly db: Db) {}

  @Public()
  @Get()
  async check() {
    await this.db.execute(sql`select 1`);
    return { ok: true, db: 'up', version: process.env.APP_VERSION ?? 'dev' };
  }
}
