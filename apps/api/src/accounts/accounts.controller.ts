import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Delete,
  Get,
  HttpCode,
  Inject,
  NotFoundException,
  Param,
  Post,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type RegistrationResponseJSON,
} from '@simplewebauthn/server';
import { and, eq, gt, isNull, lt } from 'drizzle-orm';
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';
import { z } from 'zod';
import { DB, type Db } from '../db/db.module.js';
import { challenges, identities, linkCodes, members, passkeys, sessions, users } from '../db/schema.js';
import { type AuthUser, CurrentUser, newToken, Public, sha256, Zod } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';
import { linkCode, normalizeCode, recoveryCode } from './codes.js';

const device = z.string().max(80).optional();
const displayName = z.string().trim().min(1).max(40);
const CodeBody = z.object({ code: z.string().trim().min(6).max(40), device });
const IdTokenBody = z.object({ token: z.string().min(20).max(8000), name: displayName.optional(), device });
const PasskeyRegisterBody = z.object({ challengeId: z.uuid(), response: z.record(z.string(), z.unknown()) });
const PasskeyLoginBody = z.object({ challengeId: z.uuid(), response: z.record(z.string(), z.unknown()), device });

const meView = (u: { id: string; displayName: string; locale: string }) => ({ id: u.id, name: u.displayName, locale: u.locale });

const jwks = new Map<string, ReturnType<typeof createRemoteJWKSet>>();
const keySet = (url: string) => {
  let k = jwks.get(url);
  if (!k) jwks.set(url, (k = createRemoteJWKSet(new URL(url))));
  return k;
};

const PROVIDERS = {
  apple: {
    jwks: () => process.env.APPLE_JWKS_URL ?? 'https://appleid.apple.com/auth/keys',
    issuer: ['https://appleid.apple.com'],
    audience: () => process.env.APPLE_CLIENT_IDS,
  },
  google: {
    jwks: () => process.env.GOOGLE_JWKS_URL ?? 'https://www.googleapis.com/oauth2/v3/certs',
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
    audience: () => process.env.GOOGLE_CLIENT_IDS,
  },
} as const;
type Provider = keyof typeof PROVIDERS;

const rpId = () => process.env.WEBAUTHN_RP_ID ?? 'localhost';
const origins = () =>
  (process.env.WEBAUTHN_ORIGIN ?? process.env.WEB_ORIGIN ?? 'http://localhost:3000')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
const b64u = (b: Uint8Array) => Buffer.from(b).toString('base64url');

/**
 * Ways to keep an account and sign in again: a recovery code, a short code shown on a signed-in
 * device, Sign in with Apple or Google, and passkeys. All are optional; the app works without any.
 */
@Controller()
export class AccountsController {
  constructor(
    @Inject(DB) private readonly db: Db,
    private readonly groupsService: GroupsService,
  ) {}

  private async session(userId: string, deviceName?: string) {
    const token = newToken();
    await this.db.insert(sessions).values({ userId, tokenHash: sha256(token), device: deviceName ?? null });
    const [u] = await this.db.select().from(users).where(eq(users.id, userId));
    return { token, user: meView(u) };
  }

  /** What the account is protected by, for the Settings screen. */
  @Get('me/security')
  async security(@CurrentUser() user: AuthUser) {
    const [u] = await this.db.select({ recoveryCreatedAt: users.recoveryCreatedAt }).from(users).where(eq(users.id, user.id));
    const ids = await this.db.select({ provider: identities.provider, email: identities.email }).from(identities).where(eq(identities.userId, user.id));
    const keys = await this.db.select({ id: passkeys.id, createdAt: passkeys.createdAt }).from(passkeys).where(eq(passkeys.userId, user.id));
    const devices = await this.db.select({ id: sessions.id, device: sessions.device, lastSeenAt: sessions.lastSeenAt }).from(sessions).where(eq(sessions.userId, user.id));
    return {
      recoveryCode: !!u?.recoveryCreatedAt,
      recoveryCreatedAt: u?.recoveryCreatedAt?.toISOString() ?? null,
      identities: ids,
      passkeys: keys.map((k) => ({ id: k.id, createdAt: k.createdAt.toISOString() })),
      sessions: devices.map((d) => ({ id: d.id, device: d.device, lastSeenAt: d.lastSeenAt.toISOString(), current: d.id === user.sessionId })),
      providers: { apple: !!process.env.APPLE_CLIENT_IDS, google: !!process.env.GOOGLE_CLIENT_IDS, passkeys: true },
    };
  }

  /** Makes a new recovery code (replacing any old one). It is shown once; only its hash is kept. */
  @Post('me/recovery')
  async makeRecovery(@CurrentUser() user: AuthUser) {
    const code = recoveryCode();
    await this.db.update(users).set({ recoveryHash: sha256(normalizeCode(code)), recoveryCreatedAt: new Date() }).where(eq(users.id, user.id));
    return { code };
  }

  @Public()
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('auth/recover')
  async recover(@Body(new Zod(CodeBody)) body: z.infer<typeof CodeBody>) {
    const [u] = await this.db.select({ id: users.id }).from(users).where(eq(users.recoveryHash, sha256(normalizeCode(body.code)))).limit(1);
    if (!u) throw new UnauthorizedException('That recovery code does not match an account.');
    return this.session(u.id, body.device);
  }

  /** A code to type on another device, valid for 10 minutes and once. */
  @Post('me/link')
  async makeLink(@CurrentUser() user: AuthUser) {
    const code = linkCode();
    const expiresAt = new Date(Date.now() + 10 * 60_000);
    await this.db.delete(linkCodes).where(lt(linkCodes.expiresAt, new Date()));
    await this.db.insert(linkCodes).values({ userId: user.id, codeHash: sha256(normalizeCode(code)), expiresAt });
    return { code, expiresAt: expiresAt.toISOString() };
  }

  @Public()
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('auth/link')
  async link(@Body(new Zod(CodeBody)) body: z.infer<typeof CodeBody>) {
    const [row] = await this.db
      .update(linkCodes)
      .set({ usedAt: new Date() })
      .where(and(eq(linkCodes.codeHash, sha256(normalizeCode(body.code))), isNull(linkCodes.usedAt), gt(linkCodes.expiresAt, new Date())))
      .returning({ userId: linkCodes.userId });
    if (!row) throw new UnauthorizedException('That code has expired or was already used. Make a new one on your other device.');
    return this.session(row.userId, body.device);
  }

  private async verifyIdToken(provider: Provider, token: string): Promise<JWTPayload & { sub: string; email?: string; name?: string }> {
    const p = PROVIDERS[provider];
    const audience = p.audience()?.split(',').map((s) => s.trim()).filter(Boolean);
    if (!audience?.length) throw new ServiceUnavailableException(`Sign in with ${provider === 'apple' ? 'Apple' : 'Google'} is not set up on this server yet.`);
    try {
      const { payload } = await jwtVerify(token, keySet(p.jwks()), { issuer: [...p.issuer], audience });
      if (!payload.sub) throw new Error('no subject');
      return payload as JWTPayload & { sub: string; email?: string };
    } catch {
      throw new UnauthorizedException('That sign-in could not be checked. Try again.');
    }
  }

  /**
   * Signed in already: links Apple or Google to this account. Not signed in: signs in to the account
   * that identity belongs to, or makes a new one.
   */
  private async withIdentity(provider: Provider, user: AuthUser | undefined, body: z.infer<typeof IdTokenBody>) {
    const claims = await this.verifyIdToken(provider, body.token);
    const [existing] = await this.db
      .select({ userId: identities.userId })
      .from(identities)
      .where(and(eq(identities.provider, provider), eq(identities.subject, claims.sub)))
      .limit(1);
    if (user) {
      if (existing && existing.userId !== user.id) throw new ConflictException('That account is already linked to someone else.');
      if (!existing) await this.db.insert(identities).values({ userId: user.id, provider, subject: claims.sub, email: claims.email ?? null });
      return { linked: true, user: meView(user) };
    }
    if (existing) return this.session(existing.userId, body.device);
    const name = body.name ?? (typeof claims.name === 'string' ? claims.name : undefined) ?? claims.email?.split('@')[0] ?? 'Friend';
    const [u] = await this.db.insert(users).values({ displayName: name.slice(0, 40) }).returning({ id: users.id });
    await this.db.insert(identities).values({ userId: u.id, provider, subject: claims.sub, email: claims.email ?? null });
    return this.session(u.id, body.device);
  }

  @Public()
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('auth/apple')
  apple(@CurrentUser() user: AuthUser | undefined, @Body(new Zod(IdTokenBody)) body: z.infer<typeof IdTokenBody>) {
    return this.withIdentity('apple', user, body);
  }

  @Public()
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('auth/google')
  google(@CurrentUser() user: AuthUser | undefined, @Body(new Zod(IdTokenBody)) body: z.infer<typeof IdTokenBody>) {
    return this.withIdentity('google', user, body);
  }

  private async challenge(kind: 'register' | 'login', challenge: string, userId: string | null) {
    await this.db.delete(challenges).where(lt(challenges.expiresAt, new Date()));
    const [c] = await this.db
      .insert(challenges)
      .values({ kind, challenge, userId, expiresAt: new Date(Date.now() + 5 * 60_000) })
      .returning({ id: challenges.id });
    return c.id;
  }

  private async takeChallenge(id: string, kind: 'register' | 'login', userId: string | null) {
    const [c] = await this.db.delete(challenges).where(and(eq(challenges.id, id), eq(challenges.kind, kind), gt(challenges.expiresAt, new Date()))).returning();
    if (!c || (userId && c.userId !== userId)) throw new BadRequestException('That passkey request has expired. Try again.');
    return c.challenge;
  }

  @Post('me/passkeys/options')
  async passkeyOptions(@CurrentUser() user: AuthUser) {
    const existing = await this.db.select({ id: passkeys.id, transports: passkeys.transports }).from(passkeys).where(eq(passkeys.userId, user.id));
    const options = await generateRegistrationOptions({
      rpName: 'NussNuss',
      rpID: rpId(),
      userName: user.displayName,
      userID: new TextEncoder().encode(user.id),
      attestationType: 'none',
      excludeCredentials: existing.map((k) => ({ id: k.id, transports: k.transports })),
      authenticatorSelection: { residentKey: 'required', userVerification: 'preferred' },
    });
    return { challengeId: await this.challenge('register', options.challenge, user.id), options };
  }

  @Post('me/passkeys')
  async addPasskey(@CurrentUser() user: AuthUser, @Body(new Zod(PasskeyRegisterBody)) body: z.infer<typeof PasskeyRegisterBody>) {
    const expectedChallenge = await this.takeChallenge(body.challengeId, 'register', user.id);
    let result;
    try {
      result = await verifyRegistrationResponse({
        response: body.response as unknown as RegistrationResponseJSON,
        expectedChallenge,
        expectedOrigin: origins(),
        expectedRPID: rpId(),
        requireUserVerification: false,
      });
    } catch {
      throw new BadRequestException('That passkey could not be saved. Try again.');
    }
    if (!result.verified) throw new BadRequestException('That passkey could not be saved. Try again.');
    const c = result.registrationInfo.credential;
    await this.db
      .insert(passkeys)
      .values({ id: c.id, userId: user.id, publicKey: b64u(c.publicKey), counter: c.counter, transports: c.transports ?? [] })
      .onConflictDoNothing();
    return { id: c.id };
  }

  @Delete('me/passkeys/:id')
  @HttpCode(204)
  async removePasskey(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    await this.db.delete(passkeys).where(and(eq(passkeys.id, id), eq(passkeys.userId, user.id)));
  }

  @Public()
  @Post('auth/passkey/options')
  async loginOptions() {
    const options = await generateAuthenticationOptions({ rpID: rpId(), userVerification: 'preferred' });
    return { challengeId: await this.challenge('login', options.challenge, null), options };
  }

  @Public()
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('auth/passkey')
  async loginPasskey(@Body(new Zod(PasskeyLoginBody)) body: z.infer<typeof PasskeyLoginBody>) {
    const expectedChallenge = await this.takeChallenge(body.challengeId, 'login', null);
    const response = body.response as unknown as AuthenticationResponseJSON;
    const [key] = await this.db.select().from(passkeys).where(eq(passkeys.id, String(response.id))).limit(1);
    if (!key) throw new UnauthorizedException('That passkey is not linked to an account here.');
    let result;
    try {
      result = await verifyAuthenticationResponse({
        response,
        expectedChallenge,
        expectedOrigin: origins(),
        expectedRPID: rpId(),
        credential: { id: key.id, publicKey: new Uint8Array(Buffer.from(key.publicKey, 'base64url')), counter: key.counter, transports: key.transports },
        requireUserVerification: false,
      });
    } catch {
      throw new UnauthorizedException('That passkey could not be checked.');
    }
    if (!result.verified) throw new UnauthorizedException('That passkey could not be checked.');
    await this.db.update(passkeys).set({ counter: result.authenticationInfo.newCounter, lastUsedAt: new Date() }).where(eq(passkeys.id, key.id));
    return this.session(key.userId, body.device);
  }

  /** Signs another of this person's devices out. */
  @Delete('me/sessions/:id')
  @HttpCode(204)
  async endSession(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    const r = await this.db.delete(sessions).where(and(eq(sessions.id, id), eq(sessions.userId, user.id))).returning({ id: sessions.id });
    if (!r.length) throw new NotFoundException('That device is not signed in.');
  }

  /** Everything NussNuss holds about this person, as one file (privacy: data portability). */
  @Get('me/export')
  async exportMine(@CurrentUser() user: AuthUser) {
    const [u] = await this.db.select().from(users).where(eq(users.id, user.id));
    const mine = await this.db.select({ groupId: members.groupId }).from(members).where(eq(members.userId, user.id));
    const groupsOut = [];
    for (const m of mine) groupsOut.push(await this.groupsService.detail(m.groupId, user.id));
    return {
      exportedAt: new Date().toISOString(),
      account: { id: u.id, name: u.displayName, locale: u.locale, payTo: u.payTo, createdAt: u.createdAt.toISOString() },
      groups: groupsOut,
    };
  }
}
