import { createHash } from 'node:crypto';
import { Inject, Injectable, Logger, type OnApplicationBootstrap, type OnModuleDestroy } from '@nestjs/common';
import { and, asc, eq, isNull, lte } from 'drizzle-orm';
import { addPeriods, type Every } from '../circles/schedule.js';
import { DB, type Db } from '../db/db.module.js';
import { recurring } from '../db/schema.js';
import { ExpensesService } from '../expenses/expenses.service.js';
import { PlansService } from '../plans/plans.service.js';

/** RFC 4122 version 5 UUID, so each occurrence of a recurring bill has one fixed id and is never created twice. */
export function uuidv5(name: string, namespace = '6ba7b811-9dad-11d1-80b4-00c04fd430c8'): string {
  const ns = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const h = createHash('sha1').update(Buffer.concat([ns, Buffer.from(name)])).digest();
  h[6] = (h[6] & 0x0f) | 0x50;
  h[8] = (h[8] & 0x3f) | 0x80;
  const x = h.subarray(0, 16).toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`;
}

/** Turns due recurring bills into expenses. Safe to run on several API instances at once. */
@Injectable()
export class RecurringService implements OnApplicationBootstrap, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private readonly log = new Logger('Recurring');

  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly expensesService: ExpensesService,
    private readonly plans: PlansService,
  ) {}

  onApplicationBootstrap() {
    const every = Number(process.env.RECURRING_TICK_MS ?? 60_000);
    if (every > 0) this.timer = setInterval(() => void this.runDue().catch((e) => this.log.error(e)), every);
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /** Creates every occurrence that is due by `now` (at most 12 per bill per run), then moves the bill forward. */
  async runDue(now = new Date()): Promise<number> {
    let created = 0;
    await this.db.transaction(async (tx) => {
      const due = await tx
        .select()
        .from(recurring)
        .where(and(isNull(recurring.deletedAt), lte(recurring.nextAt, now)))
        .orderBy(asc(recurring.nextAt))
        .limit(100)
        .for('update', { skipLocked: true });
      for (const r of due) {
        let next = r.nextAt;
        const allowed = r.createdBy ? await this.plans.hasPlus(r.createdBy, r.groupId, now) : false;
        for (let i = 0; i < 12 && next <= now; i++) {
          if (allowed) {
            const id = uuidv5(`${r.id}:${next.toISOString()}`);
            // A savepoint per occurrence: one bad bill never blocks the others.
            const made = await tx
              .transaction((sp) => this.expensesService.insert(sp, r.groupId, id, r.createdBy, {
                title: r.title,
                amount: r.amountMinor,
                paidBy: r.paidBy,
                mode: r.splitMode,
                items: r.items,
                category: r.category,
                spentAt: next.toISOString(),
              }))
              .catch((e: unknown) => {
                this.log.warn(`Recurring ${r.id} skipped: ${(e as Error).message}`);
                return false;
              });
            if (made) created++;
          }
          next = addPeriods(next, r.every as Every, 1, r.anchorDay);
        }
        await tx.update(recurring).set({ nextAt: next }).where(eq(recurring.id, r.id));
      }
    });
    return created;
  }
}
