import { BadRequestException, Body, Controller, ForbiddenException, Get, HttpException, Inject, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';
import { PlansService, products } from './plans.service.js';
import { StoreError, verifyAppleTransaction, verifyGooglePurchase } from './stores.js';

const AppleBody = z.object({ signedTransaction: z.string().min(20).max(20000), groupId: z.uuid().optional() });
const GoogleBody = z.object({ productId: z.string().min(1).max(100), purchaseToken: z.string().min(10).max(4000), groupId: z.uuid().optional() });
const DevBody = z.object({ productId: z.string().min(1).max(100), groupId: z.uuid().optional(), days: z.number().int().min(1).max(400).optional() });

const asHttp = (e: unknown): never => {
  if (e instanceof StoreError) throw new HttpException(e.message, e.status);
  throw e;
};

@Controller()
export class PlansController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly plans: PlansService,
    private readonly groupsService: GroupsService,
  ) {}

  @Get('me/plan')
  plan(@CurrentUser() user: AuthUser) {
    return this.plans.plan(user.id);
  }

  /** The products the apps can sell, so prices live in the stores and ids live here. */
  @Get('plans/products')
  list() {
    return Object.entries(products()).map(([id, p]) => ({ id, ...p }));
  }

  private async tripGroup(user: AuthUser, productId: string, groupId?: string) {
    if (products()[productId]?.kind !== 'trip_pass') return null;
    if (!groupId) throw new BadRequestException('Pick the group this Trip Pass is for.');
    await this.groupsService.memberOf(groupId, user.id);
    return groupId;
  }

  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('purchases/apple')
  async apple(@CurrentUser() user: AuthUser, @Body(new Zod(AppleBody)) body: z.infer<typeof AppleBody>) {
    const tx = await verifyAppleTransaction(body.signedTransaction).catch(asHttp);
    if (!products()[tx.productId]) throw new BadRequestException('Unknown product.');
    const groupId = await this.tripGroup(user, tx.productId, body.groupId);
    await this.plans.grant(this.db, {
      userId: user.id,
      productId: tx.productId,
      platform: 'apple',
      transactionId: tx.originalTransactionId ?? tx.transactionId,
      groupId,
      ...(tx.expiresDate ? { expiresAt: new Date(tx.expiresDate) } : {}),
    });
    return this.plans.plan(user.id);
  }

  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('purchases/google')
  async google(@CurrentUser() user: AuthUser, @Body(new Zod(GoogleBody)) body: z.infer<typeof GoogleBody>) {
    const product = products()[body.productId];
    if (!product) throw new BadRequestException('Unknown product.');
    const groupId = await this.tripGroup(user, body.productId, body.groupId);
    const p = await verifyGooglePurchase(body.productId, body.purchaseToken, product.kind === 'plus').catch(asHttp);
    await this.plans.grant(this.db, {
      userId: user.id,
      productId: body.productId,
      platform: 'google',
      transactionId: p.orderId,
      groupId,
      ...(p.expiresAt ? { expiresAt: p.expiresAt } : {}),
    });
    return this.plans.plan(user.id);
  }

  /** Development and review builds only: grants a product without a store. Off unless ALLOW_DEV_PURCHASES=true. */
  @Post('purchases/dev')
  async dev(@CurrentUser() user: AuthUser, @Body(new Zod(DevBody)) body: z.infer<typeof DevBody>) {
    if (process.env.ALLOW_DEV_PURCHASES !== 'true') throw new ForbiddenException('Test purchases are turned off on this server.');
    if (!products()[body.productId]) throw new BadRequestException('Unknown product.');
    const groupId = await this.tripGroup(user, body.productId, body.groupId);
    await this.plans.grant(this.db, {
      userId: user.id,
      productId: body.productId,
      platform: 'dev',
      transactionId: `dev-${crypto.randomUUID()}`,
      groupId,
      ...(body.days ? { expiresAt: new Date(Date.now() + body.days * 864e5) } : {}),
    });
    return this.plans.plan(user.id);
  }
}
