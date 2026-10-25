import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AccountsController } from './accounts/accounts.controller.js';
import { AuthController } from './auth/auth.controller.js';
import { AuthGuard } from './auth/auth.guard.js';
import { CirclesController } from './circles/circles.controller.js';
import { DbModule } from './db/db.module.js';
import { EventsController } from './events/events.controller.js';
import { EventsService } from './events/events.service.js';
import { ExpensesController } from './expenses/expenses.controller.js';
import { ExpensesService } from './expenses/expenses.service.js';
import { ExportController } from './export/export.controller.js';
import { GroupsController } from './groups/groups.controller.js';
import { GroupsService } from './groups/groups.service.js';
import { HealthController } from './health.controller.js';
import { InvitesController } from './invites/invites.controller.js';
import { NotificationsController } from './notifications/notifications.controller.js';
import { PushService } from './notifications/push.service.js';
import { RemindersService } from './notifications/reminders.service.js';
import { PaymentsController } from './payments/payments.controller.js';
import { PlansController } from './plans/plans.controller.js';
import { PlansService } from './plans/plans.service.js';
import { RatesController } from './rates/rates.controller.js';
import { RecurringController } from './recurring/recurring.controller.js';
import { RecurringService } from './recurring/recurring.service.js';

@Module({
  imports: [DbModule, ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: Number(process.env.RATE_LIMIT_PER_MINUTE ?? 300) }])],
  controllers: [
    HealthController,
    AuthController,
    AccountsController,
    GroupsController,
    ExpensesController,
    PaymentsController,
    InvitesController,
    PlansController,
    RecurringController,
    CirclesController,
    RatesController,
    ExportController,
    EventsController,
    NotificationsController,
  ],
  providers: [
    GroupsService,
    ExpensesService,
    PlansService,
    RecurringService,
    EventsService,
    PushService,
    RemindersService,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule {}
