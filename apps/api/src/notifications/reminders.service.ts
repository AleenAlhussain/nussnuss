import { Inject, Injectable, Logger, type OnApplicationBootstrap, type OnModuleDestroy } from '@nestjs/common';
import { formatMoney } from '@nussnuss/core';
import { and, eq, inArray, isNull, lt, or } from 'drizzle-orm';
import { DB, type Db } from '../db/db.module.js';
import { groups, notifications, users } from '../db/schema.js';
import { GroupsService } from '../groups/groups.service.js';
import { PlansService } from '../plans/plans.service.js';
import { PushService } from './push.service.js';

const WEEK = 7 * 864e5;

const copy = {
  en: { title: (g: string) => `${g}`, body: (amount: string, to: string) => `A gentle reminder: you owe ${to} ${amount}.` },
  ar: { title: (g: string) => `${g}`, body: (amount: string, to: string) => `تذكير لطيف: عليك ${amount} لـ ${to}.` },
};

/** Weekly reminders for groups that turned them on (Plus): one notice per person who owes, in their language. */
@Injectable()
export class RemindersService implements OnApplicationBootstrap, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private readonly log = new Logger('Reminders');

  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
    private readonly plans: PlansService,
    private readonly push: PushService,
  ) {}

  onApplicationBootstrap() {
    const every = Number(process.env.REMINDERS_TICK_MS ?? 3_600_000);
    if (every > 0) this.timer = setInterval(() => void this.runDue().catch((e) => this.log.error(e)), every);
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  async runDue(now = new Date()): Promise<number> {
    let sent = 0;
    const due = await this.db.transaction(async (tx) => {
      const rows = await tx
        .select({ id: groups.id, createdBy: groups.createdBy })
        .from(groups)
        .where(and(eq(groups.remindEvery, 'week'), or(isNull(groups.lastReminderAt), lt(groups.lastReminderAt, new Date(now.getTime() - WEEK)))))
        .limit(100)
        .for('update', { skipLocked: true });
      if (rows.length) await tx.update(groups).set({ lastReminderAt: now }).where(inArray(groups.id, rows.map((r) => r.id)));
      return rows;
    });
    for (const g of due) {
      if (!(await this.plans.groupHasPlus(g.id, now))) continue;
      const snap = await this.groupsService.snapshot(g.id);
      for (const t of snap.transfers) {
        const debtor = snap.members.find((m) => m.id === t.from);
        const creditor = snap.members.find((m) => m.id === t.to);
        if (!debtor?.userId || !creditor) continue;
        const [u] = await this.db.select({ locale: users.locale }).from(users).where(eq(users.id, debtor.userId));
        const lang = u?.locale === 'ar' ? 'ar' : 'en';
        const amount = formatMoney(t.amount, snap.group.currency, lang);
        const [n] = await this.db
          .insert(notifications)
          .values({
            userId: debtor.userId,
            groupId: g.id,
            kind: 'reminder',
            data: { to: creditor.name, toMember: creditor.id, fromMember: debtor.id, amount: t.amount, currency: snap.group.currency, group: snap.group.name, emoji: snap.group.emoji },
          })
          .returning({ id: notifications.id });
        const pushed = await this.push.toUser(debtor.userId, {
          title: copy[lang].title(`${snap.group.emoji} ${snap.group.name}`.trim()),
          body: copy[lang].body(amount, creditor.name),
          data: { groupId: g.id, kind: 'reminder' },
        });
        if (pushed) await this.db.update(notifications).set({ pushedAt: new Date() }).where(eq(notifications.id, n.id));
        sent++;
      }
    }
    return sent;
  }
}
