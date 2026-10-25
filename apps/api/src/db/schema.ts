import { sql } from 'drizzle-orm';
import {
  bigint,
  bigserial,
  check,
  doublePrecision,
  index,
  integer,
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
  createdAt: created(),
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
    currency: text('currency').notNull(),
    /** Increases on every change to the group or anything in it; the sync cursor. */
    version: integer('version').notNull().default(1),
    createdBy: uuid('created_by').references(() => users.id, { onDelete: 'set null' }),
    createdAt: created(),
    updatedAt: updated(),
  },
  (t) => [check('groups_currency_len', sql`char_length(${t.currency}) = 3`), check('groups_name_len', sql`char_length(${t.name}) between 1 and 60`)],
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
    at: timestamp('at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('changes_group_version_idx').on(t.groupId, t.version)],
);

export const schema = { users, sessions, groups, members, expenses, expenseShares, payments, invites, changes };
