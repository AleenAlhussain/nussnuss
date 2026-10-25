import { Global, Inject, Module, type OnApplicationShutdown } from '@nestjs/common';
import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import pg from 'pg';
import { schema } from './schema.js';

export const DB = Symbol('DB');
export const POOL = Symbol('POOL');
export type Db = NodePgDatabase<typeof schema>;
/** A database handle or an open transaction. */
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0] | Db;

export function databaseUrl(): string {
  return process.env.DATABASE_URL ?? 'postgres://nussnuss:nussnuss@127.0.0.1:5432/nussnuss';
}

@Global()
@Module({
  providers: [
    {
      provide: POOL,
      useFactory: () => new pg.Pool({ connectionString: databaseUrl(), max: Number(process.env.DB_POOL_MAX ?? 10) }),
    },
    {
      provide: DB,
      inject: [POOL],
      useFactory: (pool: pg.Pool): Db => drizzle(pool, { schema }),
    },
  ],
  exports: [DB, POOL],
})
export class DbModule implements OnApplicationShutdown {
  constructor(@Inject(POOL) private readonly pool: pg.Pool) {}

  async onApplicationShutdown() {
    await this.pool.end();
  }
}
