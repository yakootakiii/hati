-- Hati — schema (spec §5.1).
--
-- Conventions, applied everywhere:
--   * ids are uuid, defaulted with gen_random_uuid()
--   * money is bigint centavos, never numeric or float (spec §4.1)
--   * mutable tables carry updated_at, maintained by a trigger
--
-- RLS lives in the next migration; storage in the one after.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- shared helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Parses a uuid, returning null instead of raising. Storage policies match on
-- path segments, which are attacker-controlled, so a bad path must not error.
create or replace function public.try_uuid(value text)
returns uuid
language plpgsql
immutable
as $$
begin
  return value::uuid;
exception
  when others then
    return null;
end;
$$;

-- Itemized extras (spec §6.3, DECISIONS D-02): an object whose keys are a
-- subset of the three known extras and whose values are non-negative integer
-- centavos.
create or replace function public.is_valid_itemized_extras(extras jsonb)
returns boolean
language sql
immutable
as $$
  select jsonb_typeof(extras) = 'object'
     and not exists (
       select 1
       from jsonb_each(extras) as e(key, value)
       where e.key not in ('service_charge', 'tax', 'discount')
          or jsonb_typeof(e.value) <> 'number'
          or (e.value)::numeric < 0
          or (e.value)::numeric <> trunc((e.value)::numeric)
     );
$$;

-- Largest bill allowed, in centavos: ₱10,000,000.00 (spec §12.10). Mirrors
-- kMaxBillCentavos in lib/core/money/money.dart.
create or replace function public.max_bill_centavos()
returns bigint
language sql
immutable
as $$ select 1000000000::bigint $$;

-- ---------------------------------------------------------------------------
-- profiles & payment methods
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 50),
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  type text not null check (type in ('gcash', 'maya', 'bank', 'other')),
  label text,
  account_name text not null,
  account_number text not null,
  qr_image_path text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- At most one default method per user.
create unique index payment_methods_one_default
  on public.payment_methods (user_id)
  where is_default;

-- ---------------------------------------------------------------------------
-- groups, membership, invites
-- ---------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  photo_path text,
  created_by uuid references public.profiles,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  -- Soft leave: history stays intact and former members keep read access to
  -- the bills they took part in (spec §5.4).
  left_at timestamptz,
  primary key (group_id, user_id)
);

create index group_members_user_id_idx on public.group_members (user_id);

-- Exactly one owner per group at a time.
create unique index group_members_single_owner
  on public.group_members (group_id)
  where role = 'owner' and left_at is null;

create table public.group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  token text unique not null check (char_length(token) >= 22),
  created_by uuid references public.profiles,
  expires_at timestamptz,          -- null = never expires
  max_uses int check (max_uses is null or max_uses > 0),  -- null = unlimited
  use_count int not null default 0 check (use_count >= 0),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index group_invites_group_id_idx on public.group_invites (group_id);

-- ---------------------------------------------------------------------------
-- recurring templates
--
-- Declared before bills so that bills.recurring_template_id can reference it;
-- the spec lists it last (DECISIONS D-04).
-- ---------------------------------------------------------------------------

create table public.recurring_bills (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  created_by uuid references public.profiles,
  title text not null check (char_length(title) between 1 and 120),
  category text,
  notes text,
  total_amount bigint not null
    check (total_amount > 0 and total_amount <= public.max_bill_centavos()),
  paid_by uuid references public.profiles,
  -- Itemized is deliberately absent: a template cannot carry line items.
  split_mode text not null check (split_mode in ('equal', 'exact', 'percent', 'shares')),
  split_config jsonb not null,
  frequency text not null check (frequency in ('weekly', 'monthly', 'yearly')),
  "interval" int not null default 1 check ("interval" >= 1),
  anchor_day int check (anchor_day between 1 and 31),
  next_run_on date not null,
  ends_on date,
  paused boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index recurring_bills_due_idx
  on public.recurring_bills (next_run_on)
  where not paused;

-- ---------------------------------------------------------------------------
-- bills
-- ---------------------------------------------------------------------------

create table public.bills (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  notes text,
  category text,
  total_amount bigint not null
    check (total_amount > 0 and total_amount <= public.max_bill_centavos()),
  paid_by uuid not null references public.profiles,
  created_by uuid not null references public.profiles,
  split_mode text not null
    check (split_mode in ('equal', 'exact', 'percent', 'shares', 'itemized')),
  bill_date date not null default current_date,
  recurring_template_id uuid references public.recurring_bills on delete set null,
  status text not null default 'open' check (status in ('open', 'settled', 'void')),
  -- {"service_charge": 5000, "tax": 0, "discount": 2000} (DECISIONS D-02)
  itemized_extras jsonb not null default '{}'::jsonb
    check (public.is_valid_itemized_extras(itemized_extras)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index bills_group_date_idx on public.bills (group_id, bill_date desc);

-- One generated bill per template per run date, so a double cron run is a
-- no-op the second time (spec §7.1, §14).
create unique index bills_recurring_once_per_date
  on public.bills (recurring_template_id, bill_date)
  where recurring_template_id is not null;

create table public.bill_shares (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bills on delete cascade,
  user_id uuid not null references public.profiles,
  amount bigint not null check (amount >= 0),
  -- Raw per-mode input: exact centavos, hundredths of a percent, or
  -- thousandths of a share. Null for equal and itemized.
  split_input numeric,
  status text not null default 'unpaid'
    check (status in ('unpaid', 'pending_confirmation', 'settled')),
  settled_at timestamptz,
  -- Backs both the 3/7-day reminders and the 24h Nudge limit (DECISIONS D-03).
  last_reminded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (bill_id, user_id)
);

create index bill_shares_user_status_idx on public.bill_shares (user_id, status);

create table public.bill_items (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bills on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  amount bigint not null check (amount >= 0),
  position int,
  created_at timestamptz not null default now()
);

create index bill_items_bill_id_idx on public.bill_items (bill_id, position);

create table public.bill_item_assignees (
  item_id uuid not null references public.bill_items on delete cascade,
  user_id uuid not null references public.profiles,
  primary key (item_id, user_id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  bill_share_id uuid not null references public.bill_shares on delete cascade,
  from_user uuid not null references public.profiles,   -- debtor
  to_user uuid not null references public.profiles,     -- payer of the bill
  -- v1 has no partial payments: enforced in the RPCs, since the rule is
  -- cross-table (DECISIONS D-06).
  amount bigint not null check (amount >= 0),
  method text check (method in ('gcash', 'maya', 'bank', 'cash', 'other')),
  reference_no text,
  proof_path text,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'rejected')),
  rejected_reason text,
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create index payments_bill_share_id_idx on public.payments (bill_share_id);

-- A share can have at most one payment awaiting confirmation, which is what
-- makes a double tap on "I've paid" a no-op (spec §12.9).
create unique index payments_one_pending_per_share
  on public.payments (bill_share_id)
  where status = 'pending';

create table public.bill_attachments (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bills on delete cascade,
  path text not null,
  uploaded_by uuid references public.profiles,
  created_at timestamptz not null default now()
);

create index bill_attachments_bill_id_idx on public.bill_attachments (bill_id);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bills on delete cascade,
  author_id uuid not null references public.profiles,
  body text not null check (char_length(body) between 1 and 1000),
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create index comments_bill_created_idx on public.comments (bill_id, created_at);

-- ---------------------------------------------------------------------------
-- activity feed
-- ---------------------------------------------------------------------------

create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  actor_id uuid references public.profiles,
  type text not null check (type in (
    'group_created', 'member_joined', 'member_left', 'member_removed',
    'bill_created', 'bill_edited', 'bill_voided',
    'payment_marked', 'payment_confirmed', 'payment_rejected', 'bill_settled',
    'comment_added', 'recurring_created', 'recurring_generated'
  )),
  bill_id uuid references public.bills on delete cascade,
  payment_id uuid references public.payments on delete set null,
  comment_id uuid references public.comments on delete set null,
  -- Denormalized display data (titles, amounts) so the feed renders without
  -- joining tables the reader may no longer be allowed to see.
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index activity_events_group_created_idx
  on public.activity_events (group_id, created_at desc);

-- ---------------------------------------------------------------------------
-- notifications & devices
-- ---------------------------------------------------------------------------

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  token text unique not null,
  platform text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_id_idx on public.device_tokens (user_id);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,   -- e.g. {"route": "/bills/<id>"}
  read_at timestamptz,
  pushed_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_unread_idx
  on public.notifications (user_id, created_at desc);

create table public.notification_prefs (
  user_id uuid primary key references public.profiles on delete cascade,
  new_bill boolean not null default true,
  payment_marked boolean not null default true,
  payment_confirmed boolean not null default true,
  comments boolean not null default true,
  reminders boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'payment_methods', 'groups', 'bills', 'recurring_bills',
    'device_tokens', 'notification_prefs'
  ]
  loop
    execute format(
      'create trigger %I_set_updated_at
         before update on public.%I
         for each row execute function public.set_updated_at()',
      t, t
    );
  end loop;
end;
$$;
