-- Hati — Row Level Security (spec §5.4).
--
-- Clients talk to Postgres directly; there is no API server. RLS is therefore
-- the only thing standing between one barkada's bills and another's.
--
-- Two rules shape everything below:
--   1. A table with RLS enabled and no policy for an action denies it. Tables
--      the spec marks "via RPC only" get select policies and nothing else.
--   2. Membership checks go through security-definer helpers. A policy on
--      group_members that queried group_members would recurse forever; the
--      helper runs as owner, skipping RLS, and breaks the cycle.

-- ---------------------------------------------------------------------------
-- membership helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_group_member(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members
    where group_id = gid
      and user_id = auth.uid()
      and left_at is null
  );
$$;

create or replace function public.has_group_role(gid uuid, allowed text[])
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members
    where group_id = gid
      and user_id = auth.uid()
      and left_at is null
      and role = any(allowed)
  );
$$;

-- Do the caller and other_user share at least one group they are both still in?
-- Gates visibility of profiles and payment methods.
create or replace function public.shares_group_with(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.group_members mine
    join public.group_members theirs using (group_id)
    where mine.user_id = auth.uid()
      and mine.left_at is null
      and theirs.user_id = other_user
      and theirs.left_at is null
  );
$$;

-- Current members see every bill in the group. Former members keep read access
-- to just the bills they took part in, so their own history stays legible
-- (spec §5.4, closing note).
create or replace function public.can_read_bill(bid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.bills b
    where b.id = bid
      and (
        public.is_group_member(b.group_id)
        or exists (
          select 1
          from public.bill_shares s
          where s.bill_id = b.id
            and s.user_id = auth.uid()
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- enable RLS everywhere
--
-- ENABLE, deliberately not FORCE. FORCE would subject the table owner to
-- policies too, and the owner is exactly who the security-definer helpers run
-- as — is_group_member would then hit group_members' own policy, which calls
-- is_group_member, and recurse until the stack gives out.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'payment_methods', 'groups', 'group_members', 'group_invites',
    'bills', 'bill_shares', 'bill_items', 'bill_item_assignees', 'payments',
    'bill_attachments', 'comments', 'activity_events', 'recurring_bills',
    'device_tokens', 'notifications', 'notification_prefs'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end;
$$;

-- Nothing in this app is readable without a session.
revoke all on all tables in schema public from anon;

-- ---------------------------------------------------------------------------
-- profiles & payment methods
-- ---------------------------------------------------------------------------

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_group_with(id));

-- Insert is the signup trigger's job (security definer), not the client's.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy payment_methods_select on public.payment_methods
  for select to authenticated
  using (user_id = auth.uid() or public.shares_group_with(user_id));

create policy payment_methods_write_self on public.payment_methods
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- groups, membership, invites
-- ---------------------------------------------------------------------------

create policy groups_select on public.groups
  for select to authenticated
  using (public.is_group_member(id));

create policy groups_update_admin on public.groups
  for update to authenticated
  using (public.has_group_role(id, array['owner', 'admin']))
  with check (public.has_group_role(id, array['owner', 'admin']));

-- Membership changes go through join_group / leave_group / remove_member,
-- which enforce the outstanding-balance rules (spec §7). No client writes.
create policy group_members_select on public.group_members
  for select to authenticated
  using (public.is_group_member(group_id));

create policy group_invites_select on public.group_invites
  for select to authenticated
  using (public.has_group_role(group_id, array['owner', 'admin']));

create policy group_invites_write on public.group_invites
  for all to authenticated
  using (public.has_group_role(group_id, array['owner', 'admin']))
  with check (public.has_group_role(group_id, array['owner', 'admin']));

-- ---------------------------------------------------------------------------
-- bills and everything hanging off them — reads only; writes are RPC-only
-- ---------------------------------------------------------------------------

create policy bills_select on public.bills
  for select to authenticated
  using (public.can_read_bill(id));

create policy bill_shares_select on public.bill_shares
  for select to authenticated
  using (public.can_read_bill(bill_id));

create policy bill_items_select on public.bill_items
  for select to authenticated
  using (public.can_read_bill(bill_id));

create policy bill_item_assignees_select on public.bill_item_assignees
  for select to authenticated
  using (
    public.can_read_bill(
      (select i.bill_id from public.bill_items i where i.id = item_id)
    )
  );

create policy payments_select on public.payments
  for select to authenticated
  using (
    public.can_read_bill(
      (select s.bill_id from public.bill_shares s where s.id = bill_share_id)
    )
  );

-- ---------------------------------------------------------------------------
-- attachments & comments — members write these directly
-- ---------------------------------------------------------------------------

create policy bill_attachments_select on public.bill_attachments
  for select to authenticated
  using (public.can_read_bill(bill_id));

create policy bill_attachments_insert on public.bill_attachments
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.bills b
      where b.id = bill_id and public.is_group_member(b.group_id)
    )
  );

create policy bill_attachments_delete on public.bill_attachments
  for delete to authenticated
  using (
    uploaded_by = auth.uid()
    or exists (
      select 1 from public.bills b
      where b.id = bill_id and b.created_by = auth.uid()
    )
  );

create policy comments_select on public.comments
  for select to authenticated
  using (public.can_read_bill(bill_id));

create policy comments_insert on public.comments
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.bills b
      where b.id = bill_id and public.is_group_member(b.group_id)
    )
  );

create policy comments_update_own on public.comments
  for update to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

create policy comments_delete_own on public.comments
  for delete to authenticated
  using (author_id = auth.uid());

-- ---------------------------------------------------------------------------
-- activity feed — trigger-written, never client-written (spec §4.1)
-- ---------------------------------------------------------------------------

create policy activity_events_select on public.activity_events
  for select to authenticated
  using (public.is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- recurring templates
-- ---------------------------------------------------------------------------

create policy recurring_bills_select on public.recurring_bills
  for select to authenticated
  using (public.is_group_member(group_id));

create policy recurring_bills_insert on public.recurring_bills
  for insert to authenticated
  with check (created_by = auth.uid() and public.is_group_member(group_id));

create policy recurring_bills_update on public.recurring_bills
  for update to authenticated
  using (
    created_by = auth.uid()
    or public.has_group_role(group_id, array['owner', 'admin'])
  )
  with check (public.is_group_member(group_id));

create policy recurring_bills_delete on public.recurring_bills
  for delete to authenticated
  using (
    created_by = auth.uid()
    or public.has_group_role(group_id, array['owner', 'admin'])
  );

-- ---------------------------------------------------------------------------
-- per-user tables
-- ---------------------------------------------------------------------------

create policy device_tokens_self on public.device_tokens
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy notifications_select_self on public.notifications
  for select to authenticated
  using (user_id = auth.uid());

-- Marking as read is the only edit a client may make. The column grant below
-- is what actually restricts it to read_at — an RLS policy cannot express
-- "these columns only".
create policy notifications_update_self on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy notification_prefs_self on public.notification_prefs
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- column- and table-level grants
--
-- Defence in depth behind RLS: even a policy mistake cannot let a client
-- insert a bill or forge an activity event, because the privilege is not
-- granted in the first place.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  foreach t in array array[
    'group_members', 'bills', 'bill_shares', 'bill_items',
    'bill_item_assignees', 'payments', 'activity_events'
  ]
  loop
    execute format(
      'revoke insert, update, delete on public.%I from authenticated', t
    );
  end loop;
end;
$$;

revoke insert on public.profiles from authenticated;
revoke delete on public.profiles from authenticated;
revoke insert, delete on public.groups from authenticated;
revoke update, insert, delete on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
