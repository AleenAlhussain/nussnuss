import 'reflect-metadata';
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import pg from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/app.js';
import { runMigrations } from '../src/db/migrate.js';

const url = process.env.DATABASE_URL ?? 'postgres://nussnuss:nussnuss@127.0.0.1:5432/nussnuss_test';
process.env.DATABASE_URL = url;
process.env.RATE_LIMIT_PER_MINUTE = '100000';

let app: INestApplication;
let http: ReturnType<typeof request>;

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

beforeAll(async () => {
  await resetDatabase();
  const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
  app = configureApp(mod.createNestApplication());
  await app.init();
  http = request(app.getHttpServer());
});

afterAll(async () => {
  await app?.close();
});

describe('health and auth', () => {
  test('health is public and checks the database', async () => {
    const r = await http.get('/health').expect(200);
    expect(r.body).toMatchObject({ ok: true, db: 'up' });
  });

  test('anonymous account: no email, token works, bad token does not', async () => {
    const { token, user } = await signUp('Talal');
    expect(token.length).toBeGreaterThan(30);
    const me = await as(token).get('/me').expect(200);
    expect(me.body).toEqual({ id: user.id, name: 'Talal', locale: 'en', payTo: [] });
    await http.get('/me').expect(401);
    await http.get('/me').set('Authorization', 'Bearer nope').expect(401);
    await as(token).patch('/me').send({ locale: 'ar' }).expect(200);
    expect((await as(token).get('/me')).body.locale).toBe('ar');
  });

  test('validation errors list the fields', async () => {
    const r = await http.post('/auth/anonymous').send({ name: '' }).expect(400);
    expect(r.body.issues[0].path).toBe('name');
  });
});

describe('a trip from start to settled', () => {
  let talal: string;
  let sara: string;
  let groupId: string;
  let ids: Record<string, string>;

  test('create a group with friends by name', async () => {
    talal = (await signUp('Talal')).token;
    const r = await as(talal).post('/groups').send({ name: 'Salalah trip', emoji: '🏝️', currency: 'OMR', members: ['Sara', 'Omar'] }).expect(201);
    groupId = r.body.id;
    expect(r.body.members.map((m: { name: string }) => m.name)).toEqual(['Talal', 'Sara', 'Omar']);
    expect(r.body.members[0]).toMatchObject({ claimed: true, isMe: true });
    ids = Object.fromEntries(r.body.members.map((m: { name: string; id: string }) => [m.name, m.id]));
    const list = await as(talal).get('/groups').expect(200);
    expect(list.body).toHaveLength(1);
    expect(list.body[0]).toMatchObject({ name: 'Salalah trip', memberCount: 3, myBalance: 0, total: 0 });
  });

  test('duplicate names are refused', async () => {
    await as(talal).post('/groups').send({ name: 'x', currency: 'AED', members: ['Sara', 'sara '] }).expect(409);
    await as(talal).post(`/groups/${groupId}/members`).send({ name: 'OMAR' }).expect(409);
  });

  test('equal split in a 3-decimal currency', async () => {
    const r = await as(talal)
      .post(`/groups/${groupId}/expenses`)
      .send({ title: 'Chalet', amount: 100000, paidBy: ids.Talal, mode: 'equal', items: [ids.Talal, ids.Sara, ids.Omar].map((memberId) => ({ memberId, value: 1 })), category: 'stay' })
      .expect(201);
    const d = r.body.detail;
    expect(d.total).toBe(100000);
    expect(d.balances).toEqual({ [ids.Talal]: 66666, [ids.Sara]: -33333, [ids.Omar]: -33333 });
    expect(d.transfers).toHaveLength(2);
  });

  test('bad splits never reach the database', async () => {
    const base = { title: 'Fuel', paidBy: ids.Sara };
    await as(talal)
      .post(`/groups/${groupId}/expenses`)
      .send({ ...base, amount: 9000, mode: 'exact', items: [{ memberId: ids.Talal, value: 4000 }, { memberId: ids.Sara, value: 4000 }] })
      .expect(400)
      .expect((r) => expect(r.body.message).toBe('The amounts must add up to the total.'));
    await as(talal)
      .post(`/groups/${groupId}/expenses`)
      .send({ ...base, amount: 9000, mode: 'percent', items: [{ memberId: ids.Talal, value: 5000 }, { memberId: ids.Sara, value: 4000 }] })
      .expect(400);
    await as(talal)
      .post(`/groups/${groupId}/expenses`)
      .send({ ...base, amount: 9000, currency: 'USD', mode: 'equal', items: [{ memberId: ids.Sara, value: 1 }] })
      .expect(400)
      .expect((r) => expect(r.body.message).toContain('exchange rate'));
    await as(talal)
      .post(`/groups/${groupId}/expenses`)
      .send({ ...base, amount: 9000, mode: 'equal', items: [{ memberId: '00000000-0000-4000-8000-000000000000', value: 1 }] })
      .expect(400);
    const d = (await as(talal).get(`/groups/${groupId}`)).body;
    expect(d.expenses).toHaveLength(1);
  });

  test('a retried create with the same id does not duplicate', async () => {
    const body = {
      id: '7f9c2a4e-1b3d-4e5f-8a6b-9c0d1e2f3a4b',
      title: 'Fuel',
      amount: 12500,
      paidBy: ids.Sara,
      mode: 'shares',
      items: [{ memberId: ids.Talal, value: 2 }, { memberId: ids.Sara, value: 1 }, { memberId: ids.Omar, value: 1 }],
      category: 'transport',
    };
    await as(talal).post(`/groups/${groupId}/expenses`).send(body).expect(201);
    const again = await as(talal).post(`/groups/${groupId}/expenses`).send(body).expect(201);
    expect(again.body.detail.expenses).toHaveLength(2);
    const sum = Object.values(again.body.detail.balances as Record<string, number>).reduce((a, b) => a + b, 0);
    expect(sum).toBe(0);
  });

  test('foreign currency with a rate', async () => {
    const r = await as(talal)
      .post(`/groups/${groupId}/expenses`)
      .send({ title: 'Souvenirs', amount: 2000, currency: 'USD', rate: 0.385, paidBy: ids.Omar, mode: 'equal', items: [{ memberId: ids.Omar, value: 1 }, { memberId: ids.Sara, value: 1 }] })
      .expect(201);
    // USD 20.00 at 0.385 = OMR 7.700
    expect(r.body.detail.total).toBe(100000 + 12500 + 7700);
  });

  test('a stranger sees nothing and changes nothing', async () => {
    const stranger = (await signUp('Mallory')).token;
    await as(stranger).get(`/groups/${groupId}`).expect(404);
    await as(stranger).post(`/groups/${groupId}/expenses`).send({ title: 'x', amount: 100, paidBy: ids.Talal, mode: 'equal', items: [{ memberId: ids.Talal, value: 1 }] }).expect(404);
    await as(stranger).post(`/groups/${groupId}/invites`).expect(404);
    expect((await as(stranger).get('/groups')).body).toEqual([]);
  });

  test('Sara joins from a link as herself, then sees the group', async () => {
    const inv = await as(talal).post(`/groups/${groupId}/invites`).expect(201);
    const preview = await http.get(`/invites/${inv.body.token}`).expect(200);
    expect(preview.body.group.name).toBe('Salalah trip');
    expect(preview.body).not.toHaveProperty('expenses');
    expect(preview.body.members.find((m: { name: string }) => m.name === 'Sara').claimed).toBe(false);

    sara = (await signUp('Sara')).token;
    const joined = await as(sara).post(`/invites/${inv.body.token}/join`).send({ memberId: ids.Sara }).expect(201);
    expect(joined.body.me).toBe(ids.Sara);
    // joining again is harmless
    await as(sara).post(`/invites/${inv.body.token}/join`).send({ memberId: ids.Sara }).expect(201);
    // someone else can't take Sara's place
    const other = (await signUp('Impostor')).token;
    await as(other).post(`/invites/${inv.body.token}/join`).send({ memberId: ids.Sara }).expect(409);
    await as(other).post(`/invites/${inv.body.token}/join`).send({ name: 'Lina' }).expect(201);
    await http.get('/invites/not-a-real-token-at-all-xxxxxxxx').expect(404);
  });

  test('mark as paid until everyone is settled; undo brings a payment back', async () => {
    let d = (await as(sara).get(`/groups/${groupId}`)).body;
    expect(d.transfers.length).toBeGreaterThan(0);
    let lastPayment = '';
    for (const t of d.transfers) {
      const r = await as(sara).post(`/groups/${groupId}/payments`).send(t).expect(201);
      lastPayment = r.body.id;
      d = r.body.detail;
    }
    expect(d.transfers).toEqual([]);
    expect(Object.values(d.balances).every((v) => v === 0)).toBe(true);
    const undone = await as(sara).del(`/payments/${lastPayment}`).expect(200);
    expect(undone.body.transfers).toHaveLength(1);
  });

  test('delete an expense, then restore it', async () => {
    const d = (await as(talal).get(`/groups/${groupId}`)).body;
    const target = d.expenses.find((e: { title: string }) => e.title === 'Souvenirs');
    const after = await as(talal).del(`/expenses/${target.id}`).expect(200);
    expect(after.body.expenses.find((e: { id: string }) => e.id === target.id)).toBeUndefined();
    await as(talal).del(`/expenses/${target.id}`).expect(404);
    const back = await as(talal).post(`/expenses/${target.id}/restore`).expect(201);
    expect(back.body.expenses.find((e: { id: string }) => e.id === target.id)).toBeDefined();
  });

  test('edit an expense', async () => {
    const d = (await as(talal).get(`/groups/${groupId}`)).body;
    const e = d.expenses.find((x: { title: string }) => x.title === 'Fuel');
    const r = await as(sara)
      .patch(`/expenses/${e.id}`)
      .send({ title: 'Fuel and tolls', amount: 15000, paidBy: ids.Sara, mode: 'equal', items: [{ memberId: ids.Talal, value: 1 }, { memberId: ids.Sara, value: 1 }], category: 'transport' })
      .expect(200);
    const edited = r.body.expenses.find((x: { id: string }) => x.id === e.id);
    expect(edited).toMatchObject({ title: 'Fuel and tolls', amount: 15000, mode: 'equal' });
    expect(edited.items).toHaveLength(2);
  });

  test('the version moves forward and changes can be pulled', async () => {
    const d = (await as(talal).get(`/groups/${groupId}`)).body;
    const c = await as(talal).get(`/groups/${groupId}/changes?since=0`).expect(200);
    expect(c.body.version).toBe(d.version);
    expect(c.body.changes.length).toBe(d.version - 1);
    const later = await as(talal).get(`/groups/${groupId}/changes?since=${d.version}`).expect(200);
    expect(later.body.changes).toEqual([]);
  });

  test('currency is locked once there are expenses; only the creator deletes', async () => {
    await as(talal).patch(`/groups/${groupId}`).send({ currency: 'AED' }).expect(409);
    await as(talal).patch(`/groups/${groupId}`).send({ name: 'Salalah 2026' }).expect(200);
    await as(sara).del(`/groups/${groupId}`).expect(403);
  });

  test('deleting an account keeps friends’ balances intact', async () => {
    const before = (await as(talal).get(`/groups/${groupId}`)).body;
    await as(sara).del('/me').expect(204);
    await as(sara).get('/me').expect(401);
    const after = (await as(talal).get(`/groups/${groupId}`)).body;
    expect(after.balances).toEqual(before.balances);
    const former = after.members.find((m: { id: string }) => m.id === ids.Sara);
    expect(former.name).toMatch(/^Former member/);
    expect(former.claimed).toBe(false);
  });

  test('a group nobody else joined is deleted with its creator', async () => {
    const solo = (await signUp('Solo')).token;
    const g = await as(solo).post('/groups').send({ name: 'Just me', currency: 'AED', members: ['Imaginary friend'] }).expect(201);
    await as(solo).post(`/groups/${g.body.id}/expenses`).send({ title: 'Tea', amount: 500, paidBy: g.body.me, mode: 'equal', items: [{ memberId: g.body.me, value: 1 }] }).expect(201);
    await as(solo).del('/me').expect(204);
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    const r = await c.query('select count(*)::int as n from groups where id = $1', [g.body.id]);
    await c.end();
    expect(r.rows[0].n).toBe(0);
  });
});
