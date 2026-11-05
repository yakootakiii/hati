-- Hati — RLS tests (spec §14: "A user who is not a group member cannot read
-- any of that group's rows or storage objects").
--
-- Runs as the database owner inside a transaction that always rolls back, so
-- it is safe against a real project. Impersonation works the way PostgREST
-- does it: switch to the `authenticated` role and set the JWT claims that
-- auth.uid() reads.
--
--   tool/run_rls_tests.sh  (or: psql "$DATABASE_URL" -f supabase/tests/rls_test.sql)

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

-- ---------------------------------------------------------------------------
-- fixture: Bea and Carlo share "Tagaytay Staycation"; Mallory is an outsider
-- ---------------------------------------------------------------------------

\set bea     '11111111-1111-1111-1111-111111111111'
\set carlo   '22222222-2222-2222-2222-222222222222'
\set mallory '33333333-3333-3333-3333-333333333333'
\set grp     '44444444-4444-4444-4444-444444444444'
\set bill    '55555555-5555-5555-5555-555555555555'

select pg_temp.make_user(:'bea',     'Bea',     'bea@example.test');
select pg_temp.make_user(:'carlo',   'Carlo',   'carlo@example.test');
select pg_temp.make_user(:'mallory', 'Mallory', 'mallory@example.test');

-- The signup trigger should have produced exactly one profile each, carrying
-- the submitted display name (M1 exit criterion).
select pg_temp.assert(
  (select count(*) from public.profiles where id in (:'bea', :'carlo', :'mallory')) = 3,
  'signup trigger creates one profile per user'
);
select pg_temp.assert(
  (select display_name from public.profiles where id = :'bea') = 'Bea',
  'profile carries the submitted display name'
);
select pg_temp.assert(
  (select count(*) from public.notification_prefs where user_id = :'bea') = 1,
  'signup trigger creates notification preferences'
);

insert into public.groups (id, name, created_by) values (:'grp', 'Tagaytay Staycation', :'bea');
insert into public.group_members (group_id, user_id, role) values
  (:'grp', :'bea', 'owner'),
  (:'grp', :'carlo', 'member');

insert into public.bills (id, group_id, title, total_amount, paid_by, created_by, split_mode)
values (:'bill', :'grp', 'Airbnb – 2 nights', 1250000, :'bea', :'bea', 'equal');

insert into public.bill_shares (bill_id, user_id, amount, status) values
  (:'bill', :'bea', 625000, 'settled'),
  (:'bill', :'carlo', 625000, 'unpaid');

insert into public.activity_events (group_id, actor_id, type, bill_id)
values (:'grp', :'bea', 'bill_created', :'bill');

insert into public.comments (bill_id, author_id, body)
values (:'bill', :'bea', 'Booked it!');

insert into public.payment_methods (user_id, type, account_name, account_number)
values (:'bea', 'gcash', 'Bea R.', '09171234567');

insert into storage.objects (bucket_id, name, owner)
values ('bill-receipts', :'grp' || '/' || :'bill' || '/booking.jpg', :'bea');

-- ---------------------------------------------------------------------------
-- a member sees the group
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as(:'carlo');

\echo 'member (Carlo):'
select pg_temp.assert((select count(*) from public.groups        where id = :'grp')       = 1, 'reads the group');
select pg_temp.assert((select count(*) from public.group_members where group_id = :'grp') = 2, 'reads the membership list');
select pg_temp.assert((select count(*) from public.bills         where id = :'bill')      = 1, 'reads the bill');
select pg_temp.assert((select count(*) from public.bill_shares   where bill_id = :'bill') = 2, 'reads every share on the bill');
-- Two events: the one inserted above, plus the one the comments trigger emits
-- for the comment in this fixture.
select pg_temp.assert((select count(*) from public.activity_events where group_id = :'grp') = 2, 'reads the activity feed');
select pg_temp.assert((select count(*) from public.comments      where bill_id = :'bill') = 1, 'reads comments');
select pg_temp.assert((select count(*) from public.profiles      where id = :'bea')       = 1, 'reads a groupmate''s profile');
select pg_temp.assert((select count(*) from public.payment_methods where user_id = :'bea') = 1, 'reads a groupmate''s payment method');
select pg_temp.assert((select count(*) from storage.objects      where bucket_id = 'bill-receipts') = 1, 'reads the receipt object');

-- ---------------------------------------------------------------------------
-- an outsider sees nothing (spec §14)
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'mallory');

\echo 'outsider (Mallory):'
select pg_temp.assert((select count(*) from public.groups)          = 0, 'cannot read the group');
select pg_temp.assert((select count(*) from public.group_members)   = 0, 'cannot read the membership list');
select pg_temp.assert((select count(*) from public.group_invites)   = 0, 'cannot read invites');
select pg_temp.assert((select count(*) from public.bills)           = 0, 'cannot read bills');
select pg_temp.assert((select count(*) from public.bill_shares)     = 0, 'cannot read shares');
select pg_temp.assert((select count(*) from public.bill_items)      = 0, 'cannot read items');
select pg_temp.assert((select count(*) from public.payments)        = 0, 'cannot read payments');
select pg_temp.assert((select count(*) from public.bill_attachments) = 0, 'cannot read attachments');
select pg_temp.assert((select count(*) from public.comments)        = 0, 'cannot read comments');
select pg_temp.assert((select count(*) from public.activity_events) = 0, 'cannot read the activity feed');
select pg_temp.assert((select count(*) from public.recurring_bills) = 0, 'cannot read recurring templates');
select pg_temp.assert(
  (select count(*) from public.profiles where id <> :'mallory') = 0,
  'cannot read a stranger''s profile'
);
select pg_temp.assert(
  (select count(*) from public.payment_methods where user_id <> :'mallory') = 0,
  'cannot read a stranger''s payment methods'
);
select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'bill-receipts') = 0,
  'cannot read the receipt object'
);

-- ---------------------------------------------------------------------------
-- writes the client must never be able to make directly
-- ---------------------------------------------------------------------------

\echo 'write refusals:'
do $$
declare
  state text;
begin
  -- Joining a group is join_group's job, not an insert.
  begin
    insert into public.group_members (group_id, user_id)
    values ('44444444-4444-4444-4444-444444444444', auth.uid());
    state := 'NOT REFUSED';
  exception when others then
    state := sqlstate;
  end;
  perform pg_temp.assert(
    state = '42501',
    'outsider cannot insert themselves as a member (sqlstate ' || state || ')'
  );
end;
$$;

do $$
declare
  state text;
begin
  -- Bills are created through create_bill, which validates the split.
  begin
    insert into public.bills (group_id, title, total_amount, paid_by, created_by, split_mode)
    values ('44444444-4444-4444-4444-444444444444', 'Fake', 100, auth.uid(), auth.uid(), 'equal');
    state := 'NOT REFUSED';
  exception when others then
    state := sqlstate;
  end;
  perform pg_temp.assert(
    state = '42501',
    'nobody can insert a bill directly (sqlstate ' || state || ')'
  );
end;
$$;

do $$
declare
  state text;
begin
  -- Activity events are written by triggers so they cannot be spoofed (§4.1).
  begin
    insert into public.activity_events (group_id, actor_id, type)
    values ('44444444-4444-4444-4444-444444444444', auth.uid(), 'bill_created');
    state := 'NOT REFUSED';
  exception when others then
    state := sqlstate;
  end;
  perform pg_temp.assert(
    state = '42501',
    'nobody can forge an activity event (sqlstate ' || state || ')'
  );
end;
$$;

-- A member is still not allowed to write these either.
select pg_temp.act_as(:'carlo');
do $$
declare
  state text;
begin

  begin
    update public.bill_shares set status = 'settled'
    where user_id = auth.uid();
    state := 'NOT REFUSED';
  exception when others then
    state := sqlstate;
  end;
  perform pg_temp.assert(
    state = '42501',
    'a debtor cannot settle their own share by UPDATE (sqlstate ' || state || ')'
  );
end;
$$;

reset role;

\echo ''
\echo 'All RLS tests passed.'

rollback;
