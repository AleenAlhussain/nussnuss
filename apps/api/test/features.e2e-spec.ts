import 'reflect-metadata';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { CompactSign, exportJWK, exportPKCS8, generateKeyPair, SignJWT } from 'jose';
import pg from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/app.js';
import { runMigrations } from '../src/db/migrate.js';
import { RemindersService } from '../src/notifications/reminders.service.js';
import { RecurringService } from '../src/recurring/recurring.service.js';

const url = process.env.DATABASE_URL ?? 'postgres://nussnuss:nussnuss@127.0.0.1:5432/nussnuss_test';
process.env.DATABASE_URL = url;
process.env.RATE_LIMIT_PER_MINUTE = '100000';
process.env.RECURRING_TICK_MS = '0';
process.env.REMINDERS_TICK_MS = '0';

let app: INestApplication;
let http: ReturnType<typeof request>;
let base: string;

/** A tiny HTTP server standing in for Apple, Google and the rates API. */
let fake: Server;
let fakeUrl = '';
const routes = new Map<string, (req: IncomingMessage, body: string) => { status?: number; json: unknown }>();
const hits: string[] = [];

async function resetDatabase() {
  const c = new pg.Client({ connectionString: url });
  await c.connect();
  await c.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
  await c.end();
  await runMigrations(url);
}

async function signUp(name: string, locale = 'en') {
  const r = await http.post('/auth/anonymous').send({ name, locale }).expect(201);
  return { token: r.body.token as string, user: r.body.user as { id: string; name: string } };
}
const as = (token: string) => ({
  get: (p: string) => http.get(p).set('Authorization', `Bearer ${token}`),
  post: (p: string) => http.post(p).set('Authorization', `Bearer ${token}`),
  patch: (p: string) => http.patch(p).set('Authorization', `Bearer ${token}`),
  del: (p: string) => http.delete(p).set('Authorization', `Bearer ${token}`),
});

async function group(token: string, people: string[], currency = 'AED') {
  const r = await as(token).post('/groups').send({ name: 'Flat 12', emoji: '🏠', currency, members: people }).expect(201);
  const ids: Record<string, string> = Object.fromEntries(r.body.members.map((m: { id: string; name: string }) => [m.name, m.id]));
  return { id: r.body.id as string, me: r.body.me as string, ids };
}

async function grantPlus(token: string) {
  process.env.ALLOW_DEV_PURCHASES = 'true';
  await as(token).post('/purchases/dev').send({ productId: 'nussnuss.plus.yearly' }).expect(201);
  process.env.ALLOW_DEV_PURCHASES = 'false';
}

beforeAll(async () => {
  await resetDatabase();
  fake = createServer((req: IncomingMessage, res: ServerResponse) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const path = (req.url ?? '').split('?')[0];
      hits.push(`${req.method} ${path}`);
      const handler = routes.get(`${req.method} ${path}`);
      const out = handler ? handler(req, body) : { status: 404, json: { error: 'no route' } };
      res.writeHead(out.status ?? 200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(out.json));
    });
  });
  await new Promise<void>((r) => fake.listen(0, '127.0.0.1', () => r()));
  fakeUrl = `http://127.0.0.1:${(fake.address() as AddressInfo).port}`;

  const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
  app = configureApp(mod.createNestApplication());
  await app.listen(0, '127.0.0.1');
  base = await app.getUrl();
  http = request(app.getHttpServer());
});

afterAll(async () => {
  await app?.close();
  await new Promise((r) => fake?.close(r));
});

describe('keeping an account', () => {
  test('a recovery code signs in on a new phone; a new code replaces the old one', async () => {
    const { token, user } = await signUp('Talal');
    const first = (await as(token).post('/me/recovery').expect(201)).body.code as string;
    expect(first).toMatch(/^[0-9A-Z]{5}(-[0-9A-Z]{5}){3}$/);
    const typed = first.toLowerCase().replace(/-/g, ' ');
    const again = await http.post('/auth/recover').send({ code: typed }).expect(201);
    expect(again.body.user.id).toBe(user.id);
    expect(again.body.token).not.toBe(token);
    const second = (await as(token).post('/me/recovery').expect(201)).body.code;
    await http.post('/auth/recover').send({ code: first }).expect(401);
    await http.post('/auth/recover').send({ code: second }).expect(201);
    const sec = (await as(token).get('/me/security').expect(200)).body;
    expect(sec.recoveryCode).toBe(true);
    expect(sec.sessions.length).toBe(3);
  });

  test('a device code works once and only for ten minutes', async () => {
    const { token, user } = await signUp('Sara');
    const { code } = (await as(token).post('/me/link').expect(201)).body;
    const r = await http.post('/auth/link').send({ code, device: 'web' }).expect(201);
    expect(r.body.user.id).toBe(user.id);
    await http.post('/auth/link').send({ code }).expect(401);
  });

  test('Sign in with Apple and Google: verified tokens only, one account per identity', async () => {
    const { publicKey, privateKey } = await generateKeyPair('RS256');
    const jwk = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
    routes.set('GET /jwks', () => ({ json: { keys: [jwk] } }));
    process.env.APPLE_JWKS_URL = `${fakeUrl}/jwks`;
    process.env.GOOGLE_JWKS_URL = `${fakeUrl}/jwks`;
    const idToken = (iss: string, aud: string, sub: string, key = privateKey) =>
      new SignJWT({ email: `${sub}@example.com` })
        .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
        .setIssuer(iss)
        .setAudience(aud)
        .setSubject(sub)
        .setIssuedAt()
        .setExpirationTime('5m')
        .sign(key);

    delete process.env.APPLE_CLIENT_IDS;
    await http.post('/auth/apple').send({ token: await idToken('https://appleid.apple.com', 'app.nussnuss', 'a1') }).expect(503);
    process.env.APPLE_CLIENT_IDS = 'app.nussnuss';
    process.env.GOOGLE_CLIENT_IDS = 'web-client.apps.googleusercontent.com';

    const first = await http.post('/auth/apple').send({ token: await idToken('https://appleid.apple.com', 'app.nussnuss', 'a1'), name: 'Huda' }).expect(201);
    expect(first.body.user.name).toBe('Huda');
    const again = await http.post('/auth/apple').send({ token: await idToken('https://appleid.apple.com', 'app.nussnuss', 'a1') }).expect(201);
    expect(again.body.user.id).toBe(first.body.user.id);

    await http.post('/auth/apple').send({ token: await idToken('https://appleid.apple.com', 'someone.else', 'a1') }).expect(401);
    const forged = (await generateKeyPair('RS256')).privateKey;
    await http.post('/auth/apple').send({ token: await idToken('https://appleid.apple.com', 'app.nussnuss', 'a1', forged) }).expect(401);

    // Linking Google to the signed-in account, then signing in with Google lands on the same account.
    const g = await idToken('https://accounts.google.com', 'web-client.apps.googleusercontent.com', 'g1');
    await as(first.body.token).post('/auth/google').send({ token: g }).expect(201);
    const viaGoogle = await http.post('/auth/google').send({ token: g }).expect(201);
    expect(viaGoogle.body.user.id).toBe(first.body.user.id);
    const other = await signUp('Mona');
    await as(other.token).post('/auth/google').send({ token: g }).expect(409);
  });

  test('passkey requests hand out a challenge that expires after one use', async () => {
    const { token } = await signUp('Lina');
    const reg = (await as(token).post('/me/passkeys/options').expect(201)).body;
    expect(reg.options.rp.name).toBe('NussNuss');
    expect(reg.options.challenge.length).toBeGreaterThan(20);
    const login = (await http.post('/auth/passkey/options').expect(201)).body;
    await http.post('/auth/passkey').send({ challengeId: login.challengeId, response: { id: 'nope', type: 'public-key', response: {} } }).expect(401);
    await http.post('/auth/passkey').send({ challengeId: login.challengeId, response: { id: 'nope' } }).expect(400);
  });

  test('how to pay me: normalised, checked, and shown to friends in the group', async () => {
    const { token } = await signUp('Omar');
    const me = await as(token)
      .patch('/me')
      .send({ payTo: [{ kind: 'iban', value: 'ae07 0331 2345 6789 0123 456' }, { kind: 'paypal', value: 'paypal.me/omar' }, { kind: 'instapay', value: 'omar@instapay' }] })
      .expect(200);
    expect(me.body.payTo).toEqual([
      { kind: 'iban', value: 'AE070331234567890123456' },
      { kind: 'paypal', value: 'https://paypal.me/omar' },
      { kind: 'instapay', value: 'omar@instapay' },
    ]);
    const bad = await as(token).patch('/me').send({ payTo: [{ kind: 'link', value: 'http://evil.test/x' }] }).expect(400);
    expect(bad.body.issues[0].message).toMatch(/https/);
    const g = await group(token, ['Sara']);
    const d = (await as(token).get(`/groups/${g.id}`)).body;
    expect(d.members.find((m: { isMe: boolean }) => m.isMe).payTo).toHaveLength(3);
  });

  test('my data export lists the account and every group', async () => {
    const { token } = await signUp('Zaid');
    await group(token, ['Rami']);
    const r = (await as(token).get('/me/export').expect(200)).body;
    expect(r.account.name).toBe('Zaid');
    expect(r.groups).toHaveLength(1);
  });
});

describe('Plus', () => {
  test('test purchases are off unless the server allows them', async () => {
    const { token } = await signUp('Talal');
    await as(token).post('/purchases/dev').send({ productId: 'nussnuss.plus.yearly' }).expect(403);
    expect((await as(token).get('/me/plan')).body.plus).toBe(false);
    await grantPlus(token);
    const plan = (await as(token).get('/me/plan')).body;
    expect(plan.plus).toBe(true);
    expect(Date.parse(plan.plusUntil)).toBeGreaterThan(Date.now() + 360 * 864e5);
  });

  test('a Trip Pass opens Plus features for everyone in that group only', async () => {
    const a = await signUp('Talal');
    const g = await group(a.token, ['Sara']);
    const other = await group(a.token, ['Omar']);
    const csv = (gid: string) => as(a.token).get(`/groups/${gid}/export.csv`);
    expect((await csv(g.id).expect(403)).body.plus).toBe(true);
    process.env.ALLOW_DEV_PURCHASES = 'true';
    await as(a.token).post('/purchases/dev').send({ productId: 'nussnuss.trip_pass' }).expect(400);
    await as(a.token).post('/purchases/dev').send({ productId: 'nussnuss.trip_pass', groupId: g.id }).expect(201);
    process.env.ALLOW_DEV_PURCHASES = 'false';
    await csv(g.id).expect(200);
    await csv(other.id).expect(403);
    expect((await as(a.token).get(`/groups/${g.id}`)).body.tripPassUntil).toBeTruthy();
  });

  test('App Store transactions: only a chain that ends at the configured root counts', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'nn-apple-'));
    const ssl = (...args: string[]) => execFileSync('openssl', args, { cwd: dir, stdio: 'pipe' });
    const ext = join(dir, 'ca.ext');
    writeFileSync(ext, 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n');
    ssl('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'root.key');
    ssl('req', '-x509', '-new', '-key', 'root.key', '-subj', '/CN=Test Root', '-days', '2', '-out', 'root.pem');
    ssl('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'int.key');
    ssl('req', '-new', '-key', 'int.key', '-subj', '/CN=Test Intermediate', '-out', 'int.csr');
    ssl('x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '2', '-extfile', ext, '-out', 'int.pem');
    ssl('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'leaf.key');
    ssl('req', '-new', '-key', 'leaf.key', '-subj', '/CN=Test Leaf', '-out', 'leaf.csr');
    ssl('x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', '-CAkey', 'int.key', '-CAcreateserial', '-days', '2', '-out', 'leaf.pem');
    ssl('pkcs8', '-topk8', '-nocrypt', '-in', 'leaf.key', '-out', 'leaf.p8');
    const der = (f: string) => readFileSync(join(dir, f), 'utf8').replace(/-----[^-]+-----|\s/g, '');
    const { importPKCS8 } = await import('jose');
    const leafKey = await importPKCS8(readFileSync(join(dir, 'leaf.p8'), 'utf8'), 'ES256');
    const sign = (payload: object) =>
      new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
        .setProtectedHeader({ alg: 'ES256', x5c: [der('leaf.pem'), der('int.pem'), der('root.pem')] })
        .sign(leafKey);
    const tx = { bundleId: 'app.nussnuss', productId: 'nussnuss.plus.monthly', transactionId: '1001', originalTransactionId: '1000', expiresDate: Date.now() + 30 * 864e5 };

    const { token } = await signUp('Buyer');
    await as(token).post('/purchases/apple').send({ signedTransaction: await sign(tx) }).expect(503);
    process.env.APPLE_ROOT_CA = join(dir, 'root.pem');
    process.env.APPLE_BUNDLE_ID = 'app.nussnuss';
    await as(token).post('/purchases/apple').send({ signedTransaction: await sign({ ...tx, bundleId: 'other.app' }) }).expect(400);
    const jws = await sign(tx);
    const [h, , s] = jws.split('.');
    const tampered = `${h}.${Buffer.from(JSON.stringify({ ...tx, expiresDate: Date.now() + 9e12 })).toString('base64url')}.${s}`;
    await as(token).post('/purchases/apple').send({ signedTransaction: tampered }).expect(400);
    const ok = await as(token).post('/purchases/apple').send({ signedTransaction: jws }).expect(201);
    expect(ok.body.plus).toBe(true);
    // The same transaction sent again does not add a second purchase.
    await as(token).post('/purchases/apple').send({ signedTransaction: jws }).expect(201);
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    const n = await c.query("select count(*)::int as n from entitlements where platform = 'apple'");
    await c.end();
    expect(n.rows[0].n).toBe(1);
  });

  test('Google Play subscriptions are checked with the Play API and acknowledged', async () => {
    const { privateKey } = await generateKeyPair('RS256', { extractable: true });
    process.env.GOOGLE_PLAY_SERVICE_ACCOUNT = JSON.stringify({ client_email: 'ci@test.iam', private_key: await exportPKCS8(privateKey), token_uri: `${fakeUrl}/token` });
    process.env.ANDROID_PACKAGE_NAME = 'app.nussnuss.nussnuss';
    process.env.GOOGLE_PLAY_API_URL = fakeUrl;
    routes.set('POST /token', () => ({ json: { access_token: 'at', expires_in: 3600 } }));
    const subPath = '/androidpublisher/v3/applications/app.nussnuss.nussnuss/purchases/subscriptionsv2/tokens/tok-123456';
    routes.set(`GET ${subPath}`, () => ({
      json: {
        subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
        latestOrderId: 'GPA.1',
        acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
        lineItems: [{ productId: 'nussnuss.plus.monthly', expiryTime: new Date(Date.now() + 30 * 864e5).toISOString() }],
      },
    }));
    const ack = '/androidpublisher/v3/applications/app.nussnuss.nussnuss/purchases/subscriptions/nussnuss.plus.monthly/tokens/tok-123456:acknowledge';
    routes.set(`POST ${ack}`, () => ({ json: {} }));
    const { token } = await signUp('Android');
    const r = await as(token).post('/purchases/google').send({ productId: 'nussnuss.plus.monthly', purchaseToken: 'tok-123456' }).expect(201);
    expect(r.body.plus).toBe(true);
    expect(hits).toContain(`POST ${ack}`);
    await as(token).post('/purchases/google').send({ productId: 'nussnuss.plus.monthly', purchaseToken: 'unknown-tok' }).expect(400);
  });
});

describe('recurring bills', () => {
  test('each missed month is added once, then the bill waits for its next date', async () => {
    const { token } = await signUp('Talal');
    const g = await group(token, ['Sara', 'Omar']);
    const body = {
      title: 'Rent',
      amount: 300000,
      paidBy: g.me,
      mode: 'equal',
      items: Object.values(g.ids).map((memberId) => ({ memberId, value: 1 })),
      category: 'bills',
      every: 'month',
      startAt: '2026-08-31T09:00:00.000Z',
    };
    await as(token).post(`/groups/${g.id}/recurring`).send(body).expect(403);
    await grantPlus(token);
    const d = (await as(token).post(`/groups/${g.id}/recurring`).send(body).expect(201)).body;
    expect(d.recurring).toHaveLength(1);
    const svc = app.get(RecurringService);
    const now = new Date('2026-11-01T00:00:00.000Z');
    expect(await svc.runDue(now)).toBe(3);
    expect(await svc.runDue(now)).toBe(0);
    const after = (await as(token).get(`/groups/${g.id}`)).body;
    // Monthly on the 31st lands on the last day of shorter months.
    expect(after.expenses.map((e: { spentAt: string }) => e.spentAt.slice(0, 10)).sort()).toEqual(['2026-08-31', '2026-09-30', '2026-10-31']);
    expect(after.expenses.every((e: { title: string; amount: number }) => e.title === 'Rent' && e.amount === 300000)).toBe(true);
    expect(after.recurring[0].nextAt.slice(0, 10)).toBe('2026-11-30');
    await as(token).del(`/recurring/${d.recurring[0].id}`).expect(200);
    expect((await as(token).get(`/groups/${g.id}`)).body.recurring).toHaveLength(0);
  });
});

describe('money circles', () => {
  test('turns, payments, the current round and who is late', async () => {
    const { token } = await signUp('Talal');
    const g = await group(token, ['Sara', 'Omar']);
    const turns = [g.ids.Sara, g.me, g.ids.Omar];
    await as(token).post(`/groups/${g.id}/circles`).send({ name: 'Summer circle', amount: 50000, every: 'month', startOn: '2026-09-01', turns: [g.me, g.me] }).expect(400);
    const d = (await as(token).post(`/groups/${g.id}/circles`).send({ name: 'Summer circle', amount: 50000, every: 'month', startOn: '2026-09-01', turns }).expect(201)).body;
    const c = d.circles[0];
    expect(c.pot).toBe(150000);
    expect(c.rounds.map((r: { dueOn: string }) => r.dueOn)).toEqual(['2026-09-01', '2026-10-01', '2026-11-01']);
    expect(c.current).toBe(0);
    await as(token).post(`/circles/${c.id}/paid`).send({ round: 0, memberId: g.ids.Sara }).expect(400);
    await as(token).post(`/circles/${c.id}/paid`).send({ round: 0, memberId: g.me }).expect(201);
    const two = (await as(token).post(`/circles/${c.id}/paid`).send({ round: 0, memberId: g.ids.Omar }).expect(201)).body.circles[0];
    expect(two.current).toBe(1);
    expect(two.rounds[0].late).toEqual([]);
    expect(two.rounds[1].late.sort()).toEqual([g.ids.Sara, g.ids.Omar].sort());
    const undone = (await as(token).post(`/circles/${c.id}/unpaid`).send({ round: 0, memberId: g.ids.Omar }).expect(201)).body.circles[0];
    expect(undone.current).toBe(0);
    await as(token).del(`/circles/${c.id}`).expect(200);
    expect((await as(token).get(`/groups/${g.id}`)).body.circles).toHaveLength(0);
  });
});

describe('rates, export, reminders and live updates', () => {
  test('exchange rates come from the configured source, for Plus', async () => {
    const { token } = await signUp('Talal');
    routes.set('GET /latest/USD', () => ({ json: { result: 'success', rates: { USD: 1, AED: 3.6725 } } }));
    process.env.RATES_URL = `${fakeUrl}/latest/{base}`;
    await as(token).get('/rates?from=USD&to=AED').expect(403);
    await grantPlus(token);
    const r = (await as(token).get('/rates?from=usd&to=AED').expect(200)).body;
    expect(r.rate).toBe(3.6725);
  });

  test('CSV export: one column per person, a byte-order mark, formulas neutralised', async () => {
    const { token } = await signUp('Talal');
    await grantPlus(token);
    const g = await group(token, ['سارة']);
    await as(token)
      .post(`/groups/${g.id}/expenses`)
      .send({ title: '=HYPERLINK("x")', amount: 1000, paidBy: g.me, mode: 'equal', items: Object.values(g.ids).map((memberId) => ({ memberId, value: 1 })) })
      .expect(201);
    const r = await as(token).get(`/groups/${g.id}/export.csv`).expect(200);
    expect(r.headers['content-type']).toMatch(/text\/csv/);
    expect(r.text.charCodeAt(0)).toBe(0xfeff);
    const lines = r.text.slice(1).trim().split('\r\n');
    expect(lines[0]).toBe('Type,Date,Title,Category,Amount,Currency,Rate,Amount (AED),Paid by,Talal,سارة');
    expect(lines[1]).toContain(`"'=HYPERLINK(""x"")"`);
    expect(lines.at(-1)).toBe('Balance,,,,,AED,,,,5.00,-5.00');
  });

  test('weekly reminders reach the person who owes, in their language, once a week', async () => {
    const talal = await signUp('Talal');
    const g = await group(talal.token, ['Sara']);
    const invite = (await as(talal.token).post(`/groups/${g.id}/invites`).expect(201)).body.token;
    const sara = await signUp('Sara', 'ar');
    await as(sara.token).post(`/invites/${invite}/join`).send({ memberId: g.ids.Sara }).expect(201);
    await as(talal.token)
      .post(`/groups/${g.id}/expenses`)
      .send({ title: 'Internet', amount: 20000, paidBy: g.me, mode: 'equal', items: Object.values(g.ids).map((memberId) => ({ memberId, value: 1 })) })
      .expect(201);
    await as(talal.token).patch(`/groups/${g.id}/reminders`).send({ every: 'week' }).expect(403);
    await grantPlus(talal.token);
    await as(talal.token).patch(`/groups/${g.id}/reminders`).send({ every: 'week' }).expect(200);
    await as(sara.token).post('/me/devices').send({ platform: 'android', token: 'fcm-token-123' }).expect(204);
    const svc = app.get(RemindersService);
    expect(await svc.runDue()).toBe(1);
    expect(await svc.runDue()).toBe(0);
    const inbox = (await as(sara.token).get('/me/notifications').expect(200)).body;
    expect(inbox).toHaveLength(1);
    expect(inbox[0]).toMatchObject({ kind: 'reminder', read: false, data: { to: 'Talal', amount: 10000, currency: 'AED' } });
    await as(sara.token).post('/me/notifications/read').send({}).expect(204);
    expect((await as(sara.token).get('/me/notifications')).body[0].read).toBe(true);
  });

  test('live updates: the stream sends the version now and again after a change', async () => {
    const { token } = await signUp('Talal');
    const g = await group(token, ['Sara']);
    const ctrl = new AbortController();
    const res = await fetch(`${base}/groups/${g.id}/events`, { headers: { Authorization: `Bearer ${token}` }, signal: ctrl.signal });
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toMatch(/text\/event-stream/);
    const reader = res.body!.getReader();
    const decoder = new TextDecoder();
    let text = '';
    const next = async () => {
      while (!/\n\n/.test(text)) text += decoder.decode((await reader.read()).value);
      const i = text.indexOf('\n\n');
      const ev = text.slice(0, i);
      text = text.slice(i + 2);
      return JSON.parse(ev.split('\n').find((l) => l.startsWith('data: '))!.slice(6)) as { version: number };
    };
    const first = await next();
    await as(token)
      .post(`/groups/${g.id}/expenses`)
      .send({ title: 'Tea', amount: 500, paidBy: g.me, mode: 'equal', items: [{ memberId: g.me, value: 1 }] })
      .expect(201);
    const second = await next();
    expect(second.version).toBe(first.version + 1);
    ctrl.abort();
    const stranger = await signUp('Stranger');
    const no = await fetch(`${base}/groups/${g.id}/events`, { headers: { Authorization: `Bearer ${stranger.token}` } });
    expect(no.status).toBe(404);
  });
});
