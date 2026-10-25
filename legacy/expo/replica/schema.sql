-- NussNuss v2 sync schema (Supabase / Postgres). Not used by v1 (local-first).
-- Access: row level security; a user sees a group only if they are a member with a linked user_id.

create table groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  emoji text not null default '🍽️',
  currency char(3) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on groups (owner_id);

create table members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,  -- null = a name only, no account
  name text not null check (char_length(name) between 1 and 40),
  created_at timestamptz not null default now()
);
create index on members (group_id);
create index on members (user_id);

create table expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  rate numeric(18,8) not null default 1 check (rate > 0),   -- to the group's currency
  paid_by uuid not null references members(id) on delete restrict,
  split_mode text not null check (split_mode in ('equal','exact','percent','shares')),
  split jsonb not null,                                      -- [{member_id, value}]
  category text not null default 'other',
  spent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on expenses (group_id, spent_at desc);
create index on expenses (paid_by);

create table payments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  from_member uuid not null references members(id) on delete restrict,
  to_member uuid not null references members(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  paid_at timestamptz not null default now(),
  constraint not_self check (from_member <> to_member)
);
create index on payments (group_id);

alter table groups enable row level security;
alter table members enable row level security;
alter table expenses enable row level security;
alter table payments enable row level security;

create function is_member(g uuid) returns boolean language sql stable security definer as $$
  select exists (select 1 from members m where m.group_id = g and m.user_id = auth.uid())
      or exists (select 1 from groups gr where gr.id = g and gr.owner_id = auth.uid());
$$;

create policy group_rw on groups for all using (is_member(id)) with check (owner_id = auth.uid() or is_member(id));
create policy member_rw on members for all using (is_member(group_id)) with check (is_member(group_id));
create policy expense_rw on expenses for all using (is_member(group_id)) with check (is_member(group_id));
create policy payment_rw on payments for all using (is_member(group_id)) with check (is_member(group_id));
