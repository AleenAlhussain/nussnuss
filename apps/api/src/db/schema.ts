import { sql } from 'drizzle-orm';
import {
  bigint,
  bigserial,
  check,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

const created = () => timestamp('created_at', { withTimezone: true }).notNull().defaultNow();
const updated = () => timestamp('updated_at', { withTimezone: true }).notNull().defaultNow();

/** A person using the app. Anonymous by default: no email, no password. */
export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  displayName: text('display_name').notNull(),
  locale: text('locale').notNull().default('en'),
  /** SHA-256 of the recovery code the person saved, if they made one. */
  recoveryHash: text('recovery_hash'),
  recoveryCreatedAt: timestamp('recovery_created_at', { withTimezone: true }),
  /** How friends can pay this person: IBAN, InstaPay, a payment link and so on. */
  payTo: jsonb('pay_to').$type<PayTo[]>().notNull().default([]),
  /** How the person looks to friends: their initial, an emoji or a photo, on a tone they chose. */
  avatar: jsonb('avatar').$type<AvatarSetting>(),
  /** When they last opened Activity, so new items show a dot. */
  activitySeenAt: timestamp('activity_seen_at', { withTimezone: true }),
  createdAt: created(),
});

export type AvatarSetting =
  | { kind: 'initial'; tone: string }
  | { kind: 'emoji'; value: string; tone: string }
  | { kind: 'photo'; id: string; tone: string };

/** Profile photos, small (the apps send at most 256×256 JPEG or WebP). Served at /avatars/:id. */
export const avatars = pgTable(
  'avatars',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    mime: text('mime').notNull(),
    data: text('data').notNull(),
    createdAt: created(),
  },
  (t) => [index('avatars_user_idx').on(t.userId), check('avatars_mime', sql`${t.mime} in ('image/jpeg','image/png','image/webp')`)],
);

export type PayToKind = 'iban' | 'instapay' | 'stcpay' | 'phone' | 'paypal' | 'wise' | 'link';
export interface PayTo {
  kind: PayToKind;
  value: string;
  label?: string;
}

/** Sign in with Apple or Google, linked to an account. */
export const identities = pgTable(
  'identities',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    provider: text('provider').notNull(),
    subject: text('subject').notNull(),
    email: text('email'),
    createdAt: created(),
  },
  (t) => [uniqueIndex('identities_provider_subject_key').on(t.provider, t.subject), check('identities_provider', sql`${t.provider} in ('apple','google')`)],
);

/** Short-lived codes that sign the same account in on another device. */
export const linkCodes = pgTable(
  'link_codes',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    codeHash: text('code_hash').notNull(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    usedAt: timestamp('used_at', { withTimezone: true }),
    createdAt: created(),
  },
  (t) => [uniqueIndex('link_codes_hash_key').on(t.codeHash)],
);

/** Passkeys (WebAuthn credentials). */
export const passkeys = pgTable(
  'passkeys',
  {
    id: text('id').primaryKey(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    publicKey: text('public_key').notNull(),
    counter: bigint('counter', { mode: 'number' }).notNull().default(0),
    transports: jsonb('transports').$type<string[]>().notNull().default([]),
    createdAt: created(),
    lastUsedAt: timestamp('last_used_at', { withTimezone: true }),
  },
  (t) => [index('passkeys_user_idx').on(t.userId)],
);

/** Pending WebAuthn challenges, kept a few minutes. */
export const challenges = pgTable('webauthn_challenges', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').references(() => users.id, { onDelete: 'cascade' }),
  challenge: text('challenge').notNull(),
  kind: text('kind').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
});

/** One per device. Only the SHA-256 of the token is stored. */
export const sessions = pgTable(
  'sessions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull(),
    device: text('device'),
    createdAt: created(),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('sessions_token_hash_key').on(t.tokenHash), index('sessions_user_idx').on(t.userId)],
);

export const groups = pgTable(
  'groups',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    name: text('name').notNull(),
    emoji: text('emoji').notNull().default('🍽️'),
    /** A drawn icon on a two-tone cover ("plane:sky"). Older groups have none and show one from the emoji. */
    cover: text('cover'),
    currency: text('currency').notNull(),
    /** Increases on every change to the group or anything in it; the sync cursor. */
    version: integer('version').notNull().default(1),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    /** Automatic weekly reminders to people who owe (Plus). */
    remindEvery: text('remind_every').notNull().default('off'),
    lastReminderAt: timestamp('last_reminder_at', { withTimezone: true }),
    createdAt: created(),
    updatedAt: updated(),
  },
  (t) => [
    check('groups_currency_len', sql`char_length(${t.currency}) = 3`),
    check('groups_name_len', sql`char_length(${t.name}) between 1 and 60`),
    check('groups_remind_every', sql`${t.remindEvery} in ('off','week')`),
  ],
);

/** A name in a group. `userId` is set once someone claims the name (or for the creator). */
export const members = pgTable(
  'members',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    userId: uuid('user_id').references(() => users.id, { onDelete: 'set null' }),
    name: text('name').notNull(),
    /** lower-cased, trimmed name: two people can't share a name in one group */
    nameKey: text('name_key').notNull(),
    /** Insertion order, so people always appear in the order they were added. */
    seq: bigserial('seq', { mode: 'number' }).notNull(),
    createdAt: created(),
  },
  (t) => [
    uniqueIndex('members_group_name_key').on(t.groupId, t.nameKey),
    uniqueIndex('members_group_user_key').on(t.groupId, t.userId).where(sql`${t.userId} is not null`),
    index('members_user_idx').on(t.userId),
  ],
);

export const expenses = pgTable(
  'expenses',
  {
    /** Client-made UUIDs, so a retried create never duplicates. */
    id: uuid('id').primaryKey(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    title: text('title').notNull(),
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    currency: text('currency').notNull(),
    rate: doublePrecision('rate').notNull().default(1),
    paidBy: uuid('paid_by').notNull().references(() => members.id, { onDelete: 'no action' }),
    splitMode: text('split_mode').notNull(),
    category: text('category').notNull().default('other'),
    spentAt: timestamp('spent_at', { withTimezone: true }).notNull().defaultNow(),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    createdAt: created(),
    updatedAt: updated(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    index('expenses_group_spent_idx').on(t.groupId, t.spentAt),
    check('expenses_amount_positive', sql`${t.amountMinor} > 0`),
    check('expenses_rate_positive', sql`${t.rate} > 0`),
    check('expenses_split_mode', sql`${t.splitMode} in ('equal','exact','percent','shares')`),
  ],
);

export const expenseShares = pgTable(
  'expense_shares',
  {
    expenseId: uuid('expense_id').notNull().references(() => expenses.id, { onDelete: 'cascade' }),
    memberId: uuid('member_id').notNull().references(() => members.id, { onDelete: 'no action' }),
    value: bigint('value', { mode: 'number' }).notNull(),
  },
  (t) => [primaryKey({ columns: [t.expenseId, t.memberId] }), check('expense_shares_value', sql`${t.value} >= 0`)],
);

export const payments = pgTable(
  'payments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    fromMember: uuid('from_member').notNull().references(() => members.id, { onDelete: 'no action' }),
    toMember: uuid('to_member').notNull().references(() => members.id, { onDelete: 'no action' }),
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    paidAt: timestamp('paid_at', { withTimezone: true }).notNull().defaultNow(),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    index('payments_group_idx').on(t.groupId),
    check('payments_amount_positive', sql`${t.amountMinor} > 0`),
    check('payments_not_self', sql`${t.fromMember} <> ${t.toMember}`),
  ],
);

/** The link friends open. Only the hash of the token is stored. */
export const invites = pgTable(
  'invites',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull(),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    createdAt: created(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  },
  (t) => [uniqueIndex('invites_token_hash_key').on(t.tokenHash)],
);

/** Every change, in order, per group. Clients pull "changes since version N". */
export const changes = pgTable(
  'changes',
  {
    id: bigserial('id', { mode: 'number' }).primaryKey(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    version: integer('version').notNull(),
    entity: text('entity').notNull(),
    entityId: uuid('entity_id').notNull(),
    op: text('op').notNull(),
    /** Who made the change, when a person did (Activity shows it). */
    actor: uuid('actor').references(() => users.id, { onDelete: 'set null' }),
    at: timestamp('at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('changes_group_version_idx').on(t.groupId, t.version), index('changes_group_at_idx').on(t.groupId, t.at)],
);

/** Plus, Trip Pass and Looks. One row per store transaction. */
export const entitlements = pgTable(
  'entitlements',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').references(() => users.id, { onDelete: 'cascade' }),
    kind: text('kind').notNull(),
    productId: text('product_id').notNull(),
    /** Trip Pass only: the group it unlocks. */
    groupId: uuid('group_id').references(() => groups.id, { onDelete: 'cascade' }),
    platform: text('platform').notNull(),
    transactionId: text('transaction_id').notNull(),
    /** Null for things bought for good, such as a look. */
    expiresAt: timestamp('expires_at', { withTimezone: true }),
    createdAt: created(),
  },
  (t) => [
    uniqueIndex('entitlements_tx_key').on(t.platform, t.transactionId),
    index('entitlements_user_idx').on(t.userId),
    index('entitlements_group_idx').on(t.groupId),
    check('entitlements_kind', sql`${t.kind} in ('plus','trip_pass','look')`),
    check('entitlements_platform', sql`${t.platform} in ('apple','google','dev')`),
  ],
);

/** A bill that comes back: rent, internet, a weekly cleaner (Plus). */
export const recurring = pgTable(
  'recurring',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    title: text('title').notNull(),
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    paidBy: uuid('paid_by').notNull().references(() => members.id, { onDelete: 'no action' }),
    splitMode: text('split_mode').notNull(),
    items: jsonb('items').$type<{ memberId: string; value: number }[]>().notNull(),
    category: text('category').notNull().default('bills'),
    every: text('every').notNull(),
    /** Day of the month a monthly bill falls on (1-31, clamped to short months). */
    anchorDay: integer('anchor_day').notNull(),
    nextAt: timestamp('next_at', { withTimezone: true }).notNull(),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    createdAt: created(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    index('recurring_due_idx').on(t.nextAt),
    check('recurring_every', sql`${t.every} in ('week','month')`),
    check('recurring_amount_positive', sql`${t.amountMinor} > 0`),
  ],
);

/** A money circle (جمعية): everyone pays in each round and one person takes the pot, in turn. */
export const circles = pgTable(
  'circles',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    groupId: uuid('group_id').notNull().references(() => groups.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    amountMinor: bigint('amount_minor', { mode: 'number' }).notNull(),
    every: text('every').notNull(),
    startOn: text('start_on').notNull(),
    /** Member ids in the order they take the pot. */
    turns: jsonb('turns').$type<string[]>().notNull(),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    createdAt: created(),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
  },
  (t) => [
    index('circles_group_idx').on(t.groupId),
    check('circles_every', sql`${t.every} in ('week','month')`),
    check('circles_amount_positive', sql`${t.amountMinor} > 0`),
  ],
);

export const circlePayments = pgTable(
  'circle_payments',
  {
    circleId: uuid('circle_id').notNull().references(() => circles.id, { onDelete: 'cascade' }),
    round: integer('round').notNull(),
    memberId: uuid('member_id').notNull().references(() => members.id, { onDelete: 'no action' }),
    paidAt: timestamp('paid_at', { withTimezone: true }).notNull().defaultNow(),
    markedBy: uuid('marked_by').references(() => users.id, { onDelete: 'set null' }),
  },
  (t) => [primaryKey({ columns: [t.circleId, t.round, t.memberId] })],
);

/** Phones and browsers that accept push notifications. */
export const devices = pgTable(
  'devices',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    platform: text('platform').notNull(),
    token: text('token').notNull(),
    createdAt: created(),
    lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('devices_token_key').on(t.token), check('devices_platform', sql`${t.platform} in ('ios','android','web')`)],
);

/** In-app notices, such as a weekly reminder of what someone owes. */
export const notifications = pgTable(
  'notifications',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    groupId: uuid('group_id').references(() => groups.id, { onDelete: 'cascade' }),
    kind: text('kind').notNull(),
    data: jsonb('data').$type<Record<string, unknown>>().notNull().default({}),
    createdAt: created(),
    readAt: timestamp('read_at', { withTimezone: true }),
    pushedAt: timestamp('pushed_at', { withTimezone: true }),
  },
  (t) => [index('notifications_user_idx').on(t.userId, t.createdAt)],
);

export const schema = {
  users,
  avatars,
  sessions,
  identities,
  linkCodes,
  passkeys,
  challenges,
  groups,
  members,
  expenses,
  expenseShares,
  payments,
  invites,
  changes,
  entitlements,
  recurring,
  circles,
  circlePayments,
  devices,
  notifications,
};
