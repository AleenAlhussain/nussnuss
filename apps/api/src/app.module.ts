import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AuthController } from './auth/auth.controller.js';
import { AuthGuard } from './auth/auth.guard.js';
import { DbModule } from './db/db.module.js';
import { ExpensesController } from './expenses/expenses.controller.js';
import { GroupsController } from './groups/groups.controller.js';
import { GroupsService } from './groups/groups.service.js';
import { HealthController } from './health.controller.js';
import { InvitesController } from './invites/invites.controller.js';
import { PaymentsController } from './payments/payments.controller.js';

@Module({
  imports: [DbModule, ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: Number(process.env.RATE_LIMIT_PER_MINUTE ?? 300) }])],
  controllers: [HealthController, AuthController, GroupsController, ExpensesController, PaymentsController, InvitesController],
  providers: [
    GroupsService,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
  ],
})
export class AppModule {}
