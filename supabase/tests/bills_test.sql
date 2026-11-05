-- Hati — bill RPC tests (spec §7, §12.1, §12.2), including the §1 reference
-- scenario as far as M4 reaches.
--
--   tool/run_sql_tests_local.sh

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\set bea   '11111111-1111-1111-1111-111111111111'
\set carlo '22222222-2222-2222-2222-222222222222'
\set dana  '33333333-3333-3333-3333-333333333333'
\set eli   '44444444-4444-4444-4444-444444444444'
\set mallory '55555555-5555-5555-5555-555555555555'

select pg_temp.make_user(:'bea',     'Bea',     'bea@example.test');
select pg_temp.make_user(:'carlo',   'Carlo',   'carlo@example.test');
select pg_temp.make_user(:'dana',    'Dana',    'dana@example.test');
select pg_temp.make_user(:'eli',     'Eli',     'eli@example.test');
select pg_temp.make_user(:'mallory', 'Mallory', 'mallory@example.test');

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.create_group('Tagaytay Staycation') as gid \gset
select public.create_invite(:'gid'::uuid) ->> 'token' as tok \gset

-- Joined in this order, which is the order the split engine must use (§6.1).
select pg_temp.act_as(:'carlo');  select public.join_group(:'tok');
select pg_temp.act_as(:'dana');   select public.join_group(:'tok');
select pg_temp.act_as(:'eli');    select public.join_group(:'tok');

-- ---------------------------------------------------------------------------
\echo 'the reference scenario (spec §1):'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid',
  'title', 'Airbnb – 2 nights',
  'total_amount', 1250000,
  'paid_by', :'bea',
  'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'),
    jsonb_build_object('user_id', :'eli')
  )
)) as airbnb \gset

select pg_temp.assert(
  (select count(*) from public.bill_shares where bill_id = :'airbnb') = 4,
  'four shares, one per member'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where bill_id = :'airbnb' and amount = 312500) = 4,
  'everyone owes ₱3,125.00'
);
select pg_temp.assert(
  (select status from public.bill_shares
   where bill_id = :'airbnb' and user_id = :'bea') = 'settled',
  'the payer''s own share is settled on the spot (spec §6.3)'
);
select pg_temp.assert(
  (select settled_at is not null from public.bill_shares
   where bill_id = :'airbnb' and user_id = :'bea'),
  'the payer''s share carries a settled timestamp'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where bill_id = :'airbnb' and user_id <> :'bea' and status = 'unpaid') = 3,
  'everyone else still owes'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'airbnb' and type = 'bill_created') = 1,
  'emits bill_created'
);

\echo ''
\echo 'balances:'

select pg_temp.act_as(:'carlo');
select public.get_my_balances() -> 0 as carlo_bal \gset
select pg_temp.assert(
  (:'carlo_bal'::jsonb ->> 'owed_by_me')::bigint = 312500
    and (:'carlo_bal'::jsonb ->> 'owed_to_me')::bigint = 0,
  'a debtor owes ₱3,125.00 and is owed nothing'
);
select pg_temp.assert(
  jsonb_array_length(public.get_my_open_shares()) = 1,
  'the debtor has one share needing attention'
);

select pg_temp.act_as(:'bea');
select public.get_my_balances() -> 0 as bea_bal \gset
select pg_temp.assert(
  (:'bea_bal'::jsonb ->> 'owed_to_me')::bigint = 937500
    and (:'bea_bal'::jsonb ->> 'owed_by_me')::bigint = 0,
  'the payer is owed ₱9,375.00 and owes nothing'
);
select pg_temp.assert(
  jsonb_array_length(public.get_my_open_shares()) = 0,
  'the payer has nothing to pay'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'participant order is the server''s to decide (spec §6.1):'
-- ---------------------------------------------------------------------------

-- ₱100.00 three ways leaves one centavo over, and it belongs to whoever joined
-- first — regardless of the order the client sent.
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Reversed order', 'total_amount', 10000,
  'paid_by', :'eli', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'dana'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'bea')
  )
)) as reversed \gset

select pg_temp.assert(
  (select amount from public.bill_shares
   where bill_id = :'reversed' and user_id = :'bea') = 3334,
  'the earliest joiner gets the leftover centavo whatever order was sent'
);
select pg_temp.assert(
  (select sum(amount) from public.bill_shares where bill_id = :'reversed') = 10000,
  'and the shares still add up'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where bill_id = :'reversed' and user_id = :'eli') = 0,
  'a payer who is not a participant gets no share (spec §12.4)'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'itemized bills:'
-- ---------------------------------------------------------------------------

select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Groceries', 'total_amount', 50000,
  'paid_by', :'dana', 'split_mode', 'itemized',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana')
  ),
  'items', jsonb_build_array(
    jsonb_build_object('name', 'Sisig', 'amount', 30000,
      'assignees', jsonb_build_array(:'bea', :'carlo')),
    jsonb_build_object('name', 'Rice', 'amount', 5000,
      'assignees', jsonb_build_array(:'bea', :'carlo', :'dana')),
    jsonb_build_object('name', 'Halo-halo', 'amount', 15000,
      'assignees', jsonb_build_array(:'dana'))
  ),
  'extras', jsonb_build_object('service_charge', 5000, 'tax', 0, 'discount', 5000)
)) as groceries \gset

select pg_temp.assert(
  (select count(*) from public.bill_items where bill_id = :'groceries') = 3,
  'stores the line items'
);
select pg_temp.assert(
  (select count(*) from public.bill_item_assignees a
   join public.bill_items i on i.id = a.item_id
   where i.bill_id = :'groceries') = 6,
  'stores who shares each line'
);
select pg_temp.assert(
  (select amount from public.bill_shares
   where bill_id = :'groceries' and user_id = :'bea') = 16667
  and (select amount from public.bill_shares
   where bill_id = :'groceries' and user_id = :'dana') = 16666,
  'matches the shared split vector to the centavo'
);
select pg_temp.assert(
  (select itemized_extras ->> 'service_charge' from public.bills
   where id = :'groceries') = '5000',
  'keeps the extras on the bill'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'create_bill refusals:'
-- ---------------------------------------------------------------------------

select pg_temp.assert_raises(
  format('select public.create_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', '   ', 'total_amount', 1000,
    'paid_by', :'bea', 'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'bea'))
  )), 'HT010', 'a blank title is refused'
);
select pg_temp.assert_raises(
  format('select public.create_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', 'Outsider pays', 'total_amount', 1000,
    'paid_by', :'mallory', 'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'bea'))
  )), 'HT031', 'a payer outside the group is refused'
);
select pg_temp.assert_raises(
  format('select public.create_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', 'Outsider owes', 'total_amount', 1000,
    'paid_by', :'bea', 'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'mallory'))
  )), 'HT032', 'a participant outside the group is refused'
);
select pg_temp.assert_raises(
  format('select public.create_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', 'Bad split', 'total_amount', 100000,
    'paid_by', :'bea', 'split_mode', 'percent',
    'participants', jsonb_build_array(
      jsonb_build_object('user_id', :'bea', 'input', 4000),
      jsonb_build_object('user_id', :'carlo', 'input', 4000))
  )), 'HT024', 'the split engine''s own refusal comes through untouched'
);

select pg_temp.act_as(:'mallory');
select pg_temp.assert_raises(
  format('select public.create_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', 'Gatecrash', 'total_amount', 1000,
    'paid_by', :'mallory', 'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'mallory'))
  )), 'HT001', 'a non-member cannot add a bill to the group'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'update_bill:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.update_bill(:'airbnb'::uuid, jsonb_build_object(
  'title', 'Airbnb – 3 nights',
  'total_amount', 1500000,
  'paid_by', :'bea',
  'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'),
    jsonb_build_object('user_id', :'eli')
  )
));

select pg_temp.assert(
  (select title from public.bills where id = :'airbnb') = 'Airbnb – 3 nights',
  'the bill is renamed'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares
   where bill_id = :'airbnb' and amount = 375000) = 4,
  'shares are recomputed'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'airbnb' and type = 'bill_edited') = 1,
  'emits bill_edited'
);

-- Dropping a participant removes their share and reweights the rest.
select public.update_bill(:'airbnb'::uuid, jsonb_build_object(
  'title', 'Airbnb – 3 nights', 'total_amount', 1500000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana')
  )
));
select pg_temp.assert(
  (select count(*) from public.bill_shares where bill_id = :'airbnb') = 3
    and (select count(*) from public.bill_shares
         where bill_id = :'airbnb' and user_id = :'eli') = 0,
  'a dropped participant loses their share'
);
select pg_temp.assert(
  (select sum(amount) from public.bill_shares where bill_id = :'airbnb') = 1500000,
  'and the remaining shares still add up'
);

select pg_temp.act_as(:'dana');
select pg_temp.assert_raises(
  format('select public.update_bill(%L::uuid, %L::jsonb)', :'airbnb', jsonb_build_object(
    'title', 'Hijacked', 'total_amount', 1000, 'paid_by', :'bea',
    'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'bea'))
  )), 'HT035', 'only the creator or the payer may edit'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'editing stops once money is in flight (spec §12.1):'
-- ---------------------------------------------------------------------------

set local role postgres;
insert into public.payments (bill_share_id, from_user, to_user, amount, status)
select s.id, s.user_id, b.paid_by, s.amount, 'pending'
from public.bill_shares s
join public.bills b on b.id = s.bill_id
where s.bill_id = :'airbnb' and s.user_id = :'carlo';
update public.bill_shares set status = 'pending_confirmation'
where bill_id = :'airbnb' and user_id = :'carlo';
set local role authenticated;

select pg_temp.act_as(:'bea');
select pg_temp.assert_raises(
  format('select public.update_bill(%L::uuid, %L::jsonb)', :'airbnb', jsonb_build_object(
    'title', 'Too late', 'total_amount', 1500000, 'paid_by', :'bea',
    'split_mode', 'equal',
    'participants', jsonb_build_array(
      jsonb_build_object('user_id', :'bea'),
      jsonb_build_object('user_id', :'carlo'),
      jsonb_build_object('user_id', :'dana'))
  )), 'HT033', 'a pending payment locks the bill'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'void_bill (spec §12.2):'
-- ---------------------------------------------------------------------------

select public.void_bill(:'airbnb'::uuid, 'Booking cancelled');

select pg_temp.assert(
  (select status from public.bills where id = :'airbnb') = 'void',
  'the bill is voided'
);
select pg_temp.assert(
  (select p.status from public.payments p
   join public.bill_shares s on s.id = p.bill_share_id
   where s.bill_id = :'airbnb') = 'rejected',
  'the pending payment is auto-rejected'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'airbnb' and type = 'bill_voided') = 1,
  'emits bill_voided'
);
select public.void_bill(:'airbnb'::uuid);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'airbnb' and type = 'bill_voided') = 1,
  'voiding twice is a no-op'
);
select pg_temp.assert_raises(
  format('select public.update_bill(%L::uuid, %L::jsonb)', :'airbnb', jsonb_build_object(
    'title', 'Revive', 'total_amount', 1000, 'paid_by', :'bea',
    'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'bea'))
  )), 'HT036', 'a void bill cannot be edited back to life'
);

-- Carlo still owes on the other bills, so scope this to the voided one.
select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  not exists (
    select 1 from jsonb_array_elements(public.get_my_open_shares()) as e
    where e ->> 'bill_id' = :'airbnb'
  ),
  'a voided bill drops out of what you owe'
);
select pg_temp.assert(
  (select (public.get_my_balances() -> 0 ->> 'owed_by_me')::bigint) > 0,
  'but the other bills still count'
);

\echo ''
\echo 'a confirmed payment blocks voiding (spec §12.2):'

select pg_temp.act_as(:'dana');
set local role postgres;
insert into public.payments (bill_share_id, from_user, to_user, amount, status, confirmed_at)
select s.id, s.user_id, b.paid_by, s.amount, 'confirmed', now()
from public.bill_shares s
join public.bills b on b.id = s.bill_id
where s.bill_id = :'groceries' and s.user_id = :'bea';
set local role authenticated;
select pg_temp.act_as(:'dana');

select pg_temp.assert_raises(
  format('select public.void_bill(%L::uuid)', :'groceries'),
  'HT034', 'a settled bill cannot be voided'
);
select pg_temp.assert_raises(
  format('select public.update_bill(%L::uuid, %L::jsonb)', :'groceries', jsonb_build_object(
    'title', 'Nope', 'total_amount', 50000, 'paid_by', :'dana',
    'split_mode', 'equal',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'dana'))
  )), 'HT033', 'a settled bill cannot be edited'
);

reset role;

\echo ''
\echo 'All bill tests passed.'

rollback;
