-- Hati — settling several bills with one payment (DECISIONS D-67).
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

-- Bea paid for two things; Dana paid for one.
select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Airbnb', 'total_amount', 90000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'), jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'))
)) as airbnb \gset
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Samgyup', 'total_amount', 60000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'), jsonb_build_object('user_id', :'carlo'))
)) as samgyup \gset
select pg_temp.act_as(:'dana');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Gas', 'total_amount', 20000,
  'paid_by', :'dana', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'dana'), jsonb_build_object('user_id', :'carlo'))
)) as gas \gset

select id as s_airbnb from public.bill_shares where bill_id = :'airbnb' and user_id = :'carlo' \gset
select id as s_samgyup from public.bill_shares where bill_id = :'samgyup' and user_id = :'carlo' \gset
select id as s_gas from public.bill_shares where bill_id = :'gas' and user_id = :'carlo' \gset
select id as s_dana from public.bill_shares where bill_id = :'airbnb' and user_id = :'dana' \gset

\echo 'mark_shares_paid refuses a batch that is not one debt:'

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  'select public.mark_shares_paid(array[]::uuid[])', 'HT054',
  'an empty batch'
);
select pg_temp.assert_raises(
  format('select public.mark_shares_paid(array[%L, %L]::uuid[], %L, null, %L)',
         :'s_airbnb', :'s_gas', 'gcash', :'gid' || '/p.jpg'),
  'HT055', 'bills owed to two different people'
);
select pg_temp.assert_raises(
  format('select public.mark_shares_paid(array[%L, %L]::uuid[], %L, null, %L)',
         :'s_airbnb', :'s_dana', 'gcash', :'gid' || '/p.jpg'),
  'HT055', 'someone else''s share'
);
select pg_temp.assert_raises(
  format('select public.mark_shares_paid(array[%L, %L]::uuid[], %L)',
         :'s_airbnb', :'s_samgyup', 'gcash'),
  'HT047', 'no screenshot'
);
select pg_temp.assert(
  (select count(*) from public.payments where from_user = :'carlo') = 0,
  'and a refused batch leaves nothing behind'
);

\echo ''
\echo 'one payment for two bills:'

select public.mark_shares_paid(
  array[:'s_airbnb', :'s_samgyup']::uuid[], 'gcash', 'REF1', :'gid' || '/p.jpg'
) as batch \gset

select pg_temp.assert(
  (select count(*) from public.payments where batch_id = :'batch') = 2,
  'each bill gets its own payment, tied by the batch'
);
select pg_temp.assert(
  (select bool_and(p.amount = s.amount) from public.payments p
   join public.bill_shares s on s.id = p.bill_share_id
   where p.batch_id = :'batch'),
  'each for its whole share (D-06)'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where id in (:'s_airbnb', :'s_samgyup') and status = 'pending_confirmation') = 2,
  'both shares await confirmation'
);
select pg_temp.assert(
  (select status from public.bill_shares where id = :'s_gas') = 'unpaid',
  'the bill owed to someone else is untouched'
);
select pg_temp.assert_raises(
  format('select public.mark_shares_paid(array[%L]::uuid[], %L, null, %L)',
         :'s_airbnb', 'gcash', :'gid' || '/p.jpg'),
  'HT056', 'a share already in flight cannot be batched again'
);

\echo ''
\echo 'confirming and rejecting the batch:'

select pg_temp.assert_raises(
  format('select public.confirm_payment_batch(%L)', :'batch'), 'HT042',
  'only the payer can confirm it'
);

select pg_temp.act_as(:'bea');
select public.confirm_payment_batch(:'batch');
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where id in (:'s_airbnb', :'s_samgyup') and status = 'settled') = 2,
  'one confirmation settles every bill in it'
);
select pg_temp.assert(
  (select status from public.bills where id = :'samgyup') = 'settled',
  'and a bill with nothing left owing is settled'
);

-- A second batch, this time rejected.
select pg_temp.act_as(:'dana');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Tolls', 'total_amount', 10000,
  'paid_by', :'dana', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'dana'), jsonb_build_object('user_id', :'carlo'))
)) as tolls \gset
select id as s_tolls from public.bill_shares where bill_id = :'tolls' and user_id = :'carlo' \gset

select pg_temp.act_as(:'carlo');
select public.mark_shares_paid(
  array[:'s_gas', :'s_tolls']::uuid[], 'maya', null, :'gid' || '/q.jpg'
) as batch2 \gset

select pg_temp.act_as(:'dana');
select public.reject_payment_batch(:'batch2', 'Nothing arrived in Maya');
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where id in (:'s_gas', :'s_tolls') and status = 'unpaid') = 2,
  'rejecting puts every bill back to unpaid'
);
select pg_temp.assert(
  (select count(*) from public.payments
   where batch_id = :'batch2' and rejected_reason = 'Nothing arrived in Maya') = 2,
  'with the reason on each'
);

reset role;

\echo ''
\echo 'All settle-all tests passed.'

rollback;
