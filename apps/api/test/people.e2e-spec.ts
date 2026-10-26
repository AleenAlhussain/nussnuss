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
process.env.RECURRING_TICK_MS = '0';
process.env.REMINDERS_TICK_MS = '0';

let app: INestApplication;
let http: ReturnType<typeof request>;

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
const equal = (ids: string[]) => ids.map((memberId) => ({ memberId, value: 1 }));

beforeAll(async () => {
  const c = new pg.Client({ connectionString: url });
  await c.connect();
  await c.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
  await c.end();
  await runMigrations(url);
  const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
  app = configureApp(mod.createNestApplication());
  await app.listen(0, '127.0.0.1');
  http = request(app.getHttpServer());
});

afterAll(async () => {
  await app?.close();
});

/** Talal has a trip in AED with Sara and Omar, and a flat in OMR with Omar. Omar joins both from links. */
async function world() {
  const talal = await signUp('Talal');
  const omar = await signUp('Omar');
  const trip = (await as(talal.token).post('/groups').send({ name: 'Salalah trip', emoji: '✈️', currency: 'AED', members: ['Sara', 'Omar'] }).expect(201)).body;
  const flat = (await as(talal.token).post('/groups').send({ name: 'Flat 9', cover: 'home:mint', currency: 'OMR', members: ['Omar'] }).expect(201)).body;
  const id = (g: { members: { id: string; name: string }[] }, n: string) => g.members.find((m) => m.name === n)!.id;
  // Talal pays 300 AED for all three; Omar pays 12.000 OMR for both in the flat.
  await as(talal.token)
    .post(`/groups/${trip.id}/expenses`)
    .send({ title: 'Hotel', amount: 30000, paidBy: trip.me, mode: 'equal', items: equal(trip.members.map((m: { id: string }) => m.id)), category: 'stay' })
    .expect(201);
  await as(talal.token)
    .post(`/groups/${flat.id}/expenses`)
    .send({ title: 'Internet', amount: 12000, paidBy: id(flat, 'Omar'), mode: 'equal', items: equal(flat.members.map((m: { id: string }) => m.id)), category: 'bills' })
    .expect(201);
  // Omar joins the flat from a short link; in the trip he is still an unclaimed name.
  const inv = (await as(talal.token).post(`/groups/${flat.id}/invites`).expect(201)).body;
  await as(omar.token).post(`/invites/${inv.token}/join`).send({ memberId: id(flat, 'Omar') }).expect(201);
  return { talal, omar, trip, flat, id };
}

describe('Home, people and settling with a person', () => {
  test('overview: overall balance per currency, the next step and the people strip', async () => {
    const { talal } = await world();
    const o = (await as(talal.token).get('/overview').expect(200)).body;
    // Trip: Talal gets back 200 AED. Flat: Talal owes Omar 6.000 OMR.
    expect(o.totals).toEqual([
      { currency: 'AED', amount: 20000 },
      { currency: 'OMR', amount: -6000 },
    ]);
    expect(o.groups).toBe(2);
    // Paying what you owe comes first.
    expect(o.next).toMatchObject({ kind: 'pay', amount: 6000, currency: 'OMR', person: { name: 'Omar' }, group: { name: 'Flat 9', cover: 'home:mint' } });
    // The unclaimed "Omar" in the trip is the same person as the Omar who joined the flat.
    const omar = o.people.find((p: { name: string }) => p.name === 'Omar');
    expect(omar.groups).toBe(2);
    expect(omar.balances).toEqual([
      { currency: 'AED', amount: 10000 },
      { currency: 'OMR', amount: -6000 },
    ]);
    expect(o.people.map((p: { name: string }) => p.name).sort()).toEqual(['Omar', 'Sara']);
    expect(o.people[0].avatar.kind).toBe('initial');
  });

  test('person view, settle everything and undo', async () => {
    const { talal, trip } = await world();
    const o = (await as(talal.token).get('/overview').expect(200)).body;
    const key = o.people.find((p: { name: string }) => p.name === 'Omar').key;
    expect(key).toMatch(/^u[0-9a-f]{20}$/);
    const p = (await as(talal.token).get(`/people/${key}`).expect(200)).body;
    expect(p.groups.map((g: { name: string; amount: number }) => [g.name, g.amount]).sort()).toEqual([
      ['Flat 9', -6000],
      ['Salalah trip', 10000],
    ]);
    expect(p.shared.map((s: { title: string; amount: number }) => [s.title, s.amount]).sort()).toEqual([
      ['Hotel', 10000],
      ['Internet', -6000],
    ]);

    const done = (await as(talal.token).post(`/people/${key}/settle`).send({}).expect(201)).body;
    expect(done.payments).toHaveLength(2);
    expect(done.person.groups.every((g: { amount: number }) => g.amount === 0)).toBe(true);
    const tripNow = (await as(talal.token).get(`/groups/${trip.id}`).expect(200)).body;
    expect(tripNow.payments).toHaveLength(1);

    await as(talal.token).post('/payments/undo').send({ ids: done.payments.map((x: { id: string }) => x.id) }).expect(200);
    const back = (await as(talal.token).get(`/people/${key}`).expect(200)).body;
    expect(back.balances).toEqual([
      { currency: 'AED', amount: 10000 },
      { currency: 'OMR', amount: -6000 },
    ]);
    // Someone outside these groups can't see or settle the person.
    const stranger = await signUp('Nobody');
    await as(stranger.token).get(`/people/${key}`).expect(404);
    await as(stranger.token).post('/payments/undo').send({ ids: done.payments.map((x: { id: string }) => x.id) }).expect(400);
    await as(talal.token).get('/people/not-a-key').expect(404);
  });

  test('Activity: who did what, your share, unread until seen, filter by group', async () => {
    const { talal, omar, flat, id } = await world();
    // Omar adds an expense in the flat after joining.
    await as(omar.token)
      .post(`/groups/${flat.id}/expenses`)
      .send({ title: 'Cleaner', amount: 4000, paidBy: id(flat, 'Omar'), mode: 'equal', items: equal(flat.members.map((m: { id: string }) => m.id)), category: 'bills' })
      .expect(201);
    const a = (await as(talal.token).get('/activity').expect(200)).body;
    expect(a.items[0]).toMatchObject({ kind: 'expense', actor: { name: 'Omar', me: false }, expense: { title: 'Cleaner', impact: -2000 }, unread: true });
    const mine = a.items.find((i: { expense?: { title: string } }) => i.expense?.title === 'Hotel');
    expect(mine).toMatchObject({ actor: { name: 'Talal', me: true }, unread: false, expense: { impact: 20000 } });
    expect(a.unread).toBeGreaterThanOrEqual(1);
    expect((await as(talal.token).get('/overview').expect(200)).body.unread).toBe(a.unread);
    expect((await as(talal.token).get('/activity/unread').expect(200)).body.unread).toBe(a.unread);
    await as(talal.token).post('/activity/seen').expect(204);
    expect((await as(talal.token).get('/activity').expect(200)).body.unread).toBe(0);
    const onlyFlat = (await as(talal.token).get(`/activity?group=${flat.id}`).expect(200)).body;
    expect(onlyFlat.items.every((i: { group: { id: string } }) => i.group.id === flat.id)).toBe(true);
  });

  test('group cards carry the cover, the latest activity and whether everyone is even', async () => {
    const { talal } = await world();
    const list = (await as(talal.token).get('/groups').expect(200)).body;
    const trip = list.find((g: { name: string }) => g.name === 'Salalah trip');
    expect(trip).toMatchObject({ cover: 'plane:sky', settled: false, expenseCount: 1, lastActivity: { kind: 'expense', title: 'Hotel', who: { name: 'Talal', me: true } } });
    expect(trip.members[0].avatar.kind).toBe('initial');
    await as(talal.token).patch(`/groups/${trip.id}`).send({ cover: 'beach:saffron' }).expect(200);
    await as(talal.token).patch(`/groups/${trip.id}`).send({ cover: 'rocket:blue' }).expect(400);
    expect((await as(talal.token).get(`/groups/${trip.id}`).expect(200)).body.cover).toBe('beach:saffron');
  });
});

describe('avatars and invite links', () => {
  test('emoji and photo avatars show to friends; photos are served for any origin', async () => {
    const { talal, omar, flat } = await world();
    const me = (await as(omar.token).patch('/me').send({ avatar: { kind: 'emoji', value: '🦊', tone: 'coral' } }).expect(200)).body;
    expect(me.avatar).toEqual({ kind: 'emoji', value: '🦊', tone: 'coral' });
    await as(omar.token).patch('/me').send({ avatar: { kind: 'emoji', value: 'not an emoji', tone: 'coral' } }).expect(400);
    // A 1×1 PNG.
    const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' + 'A'.repeat(40);
    const withPhoto = (await as(omar.token).post('/me/photo').send({ data: `data:image/png;base64,${png}` }).expect(201)).body;
    expect(withPhoto.avatar).toMatchObject({ kind: 'photo', tone: 'coral' });
    const img = await http.get(withPhoto.avatar.url).expect(200);
    expect(img.headers['content-type']).toBe('image/png');
    expect(img.headers['cross-origin-resource-policy']).toBe('cross-origin');
    await as(omar.token).post('/me/photo').send({ data: Buffer.from('hello, this is not an image at all'.repeat(5)).toString('base64') }).expect(400);
    const g = (await as(talal.token).get(`/groups/${flat.id}`).expect(200)).body;
    expect(g.members.find((m: { name: string }) => m.name === 'Omar').avatar.kind).toBe('photo');
    const removed = (await as(omar.token).del('/me/photo').expect(200)).body;
    expect(removed.avatar).toEqual({ kind: 'initial', tone: 'coral' });
    await http.get(withPhoto.avatar.url).expect(404);
  });

  test('invite links are short, case-insensitive, and show who invited you', async () => {
    const { talal, trip } = await world();
    const inv = (await as(talal.token).post(`/groups/${trip.id}/invites`).expect(201)).body;
    expect(inv.token).toMatch(/^[2-9a-hjkmnp-z]{10}$/);
    expect(inv.path).toBe(`/j/${inv.token}`);
    const pv = (await http.get(`/invites/${inv.token.toUpperCase()}`).expect(200)).body;
    expect(pv.group).toMatchObject({ name: 'Salalah trip', cover: 'plane:sky' });
    expect(pv.invitedBy).toMatchObject({ name: 'Talal', avatar: { kind: 'initial' } });
    expect(pv.members.map((m: { name: string }) => m.name)).toEqual(['Talal', 'Sara', 'Omar']);
    await http.get('/invites/zzzzzzzzzz').expect(404);
  });

  test('task timings are accepted without an account and say nothing about the person', async () => {
    await http.post('/telemetry/timing').send({ app: 'web', version: '2.0.0', job: 'add_expense', ms: 6400, ok: true }).expect(204);
    await http.post('/telemetry/timing').send({ app: 'web', version: '2.0.0', job: 'add_expense', ms: 6400, ok: true, userId: 'x' }).expect(204);
    await http.post('/telemetry/timing').send({ app: 'web', version: '2.0.0', job: 'spy', ms: 1, ok: true }).expect(400);
  });
});
