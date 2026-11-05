-- Hati — deleting your own account (DECISIONS D-64).
--
--   tool/run_sql_tests_local.sh

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\set bea   '11111111-1111-1111-1111-111111111111'
\set carlo '22222222-2222-2222-2222-222222222222'
\set dana  '33333333-3333-3333-3333-333333333333'

select pg_temp.make_user(:'bea',   'Bea',   'bea@example.test');
select pg_temp.make_user(:'carlo', 'Carlo', 'carlo@example.test');
select pg_temp.make_user(:'dana',  'Dana',  'dana@example.test');

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.create_group('Tagaytay Staycation') as gid \gset
select public.create_invite(:'gid'::uuid) ->> 'token' as tok \gset
select pg_temp.act_as(:'carlo'); select public.join_group(:'tok');
select pg_temp.act_as(:'dana');  select public.join_group(:'tok');

select pg_temp.act_as(:'bea');
select public.set_member_role(:'gid'::uuid, :'dana'::uuid, 'admin');
insert into public.payment_methods (user_id, type, account_name, account_number, qr_image_path)
values (:'bea', 'gcash', 'Bea Reyes', '09171234567', :'bea' || '/qr.png');

select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Airbnb', 'total_amount', 90000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'))
)) as bill \gset

select public.create_recurring_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Rent', 'total_amount', 3000000,
  'paid_by', :'carlo', 'split_mode', 'equal',
  'frequency', 'monthly', 'interval', 1, 'anchor_day', 1,
  'next_run_on', '2026-01-01',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'))
)) as rent \gset

-- ---------------------------------------------------------------------------
\echo 'open money blocks deletion (HT057):'
-- ---------------------------------------------------------------------------

select pg_temp.assert(
  (select count(*) from public.account_deletion_blockers()) = 1,
  'the payer sees the bill others still owe on'
);
select pg_temp.assert_raises(
  'select public.prepare_account_deletion()', 'HT057',
  'someone who is still owed money cannot delete'
);

select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  (select reason from public.account_deletion_blockers()) = 'you_owe',
  'a debtor sees what they still owe'
);
select pg_temp.assert_raises(
  'select public.prepare_account_deletion()', 'HT057',
  'someone who still owes cannot delete'
);

-- Everyone settles.
select id as carlo_share from public.bill_shares
where bill_id = :'bill' and user_id = :'carlo' \gset
select id as dana_share from public.bill_shares
where bill_id = :'bill' and user_id = :'dana' \gset
select public.mark_share_paid(:'carlo_share'::uuid, 'gcash', null, :'gid' || '/p1.jpg') as p1 \gset
select pg_temp.act_as(:'dana');
select public.mark_share_paid(:'dana_share'::uuid, 'gcash', null, :'gid' || '/p2.jpg') as p2 \gset
select pg_temp.act_as(:'bea');
select public.confirm_payment(:'p1'::uuid);
select public.confirm_payment(:'p2'::uuid);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'prepare_account_deletion:'
-- ---------------------------------------------------------------------------

select pg_temp.assert(
  (select count(*) from public.account_deletion_blockers()) = 0,
  'nothing blocks once everyone is square'
);
select public.prepare_account_deletion();

reset role;

select pg_temp.assert(
  (select display_name from public.profiles where id = :'bea') = 'Deleted user',
  'the name becomes Deleted user'
);
select pg_temp.assert(
  (select count(*) from public.payment_methods where user_id = :'bea') = 0,
  'payment methods and their QR references are gone'
);
select pg_temp.assert(
  (select count(*) from public.notification_prefs where user_id = :'bea') = 0,
  'settings are gone'
);
select pg_temp.assert(
  (select left_at from public.group_members
   where group_id = :'gid' and user_id = :'bea') is not null,
  'they have left the group'
);
select pg_temp.assert(
  (select role from public.group_members
   where group_id = :'gid' and user_id = :'dana') = 'owner',
  'ownership passes to the admin'
);
select pg_temp.assert(
  (select count(*) from public.bills where id = :'bill') = 1,
  'the bill stays in the group''s history'
);
select pg_temp.assert(
  (select paid_by from public.bills where id = :'bill') = :'bea'::uuid,
  'still attributed to the same (now anonymous) person'
);
select pg_temp.assert(
  not exists (
    select 1 from public.activity_events
    where actor_id = :'bea' and payload ->> 'display_name' = 'Bea'
  ),
  'their name is scrubbed from past activity'
);
select pg_temp.assert(
  (select paused from public.recurring_bills where id = :'rent'),
  'repeating bills that involve them are paused'
);

\echo ''
\echo 'All account deletion tests passed.'

rollback;
