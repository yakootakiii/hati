-- Hati — settlement tests (spec §7, §12.9, §14).
--
-- Carries the §1 reference scenario to its end: Carlo pays, Bea confirms,
-- Carlo's share reads Settled.
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
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Airbnb – 2 nights', 'total_amount', 900000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'))
)) as bill \gset

select id as carlo_share from public.bill_shares
where bill_id = :'bill' and user_id = :'carlo' \gset
select id as dana_share from public.bill_shares
where bill_id = :'bill' and user_id = :'dana' \gset

-- ---------------------------------------------------------------------------
\echo 'mark_share_paid:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select public.mark_share_paid(:'carlo_share'::uuid, 'gcash', 'REF123', :'gid' || '/proof-1.jpg') as pay1 \gset

select pg_temp.assert(
  (select status from public.bill_shares where id = :'carlo_share')
    = 'pending_confirmation',
  'the share moves to awaiting confirmation'
);
select pg_temp.assert(
  (select amount from public.payments where id = :'pay1') = 300000,
  'the payment is for the whole share (DECISIONS D-06)'
);
select pg_temp.assert(
  (select to_user from public.payments where id = :'pay1') = :'bea',
  'the payment is addressed to the bill payer'
);
select pg_temp.assert(
  (select reference_no from public.payments where id = :'pay1') = 'REF123',
  'the reference number is kept'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'payment_marked') = 1,
  'emits payment_marked'
);

\echo ''
\echo 'duplicate taps are a no-op (spec §12.9):'

select public.mark_share_paid(:'carlo_share'::uuid, 'gcash', 'REF123', :'gid' || '/proof-1.jpg') as pay1b \gset
select pg_temp.assert(
  :'pay1b' = :'pay1',
  'marking paid twice returns the same payment'
);
select pg_temp.assert(
  (select count(*) from public.payments where bill_share_id = :'carlo_share') = 1,
  'and creates no second payment'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'payment_marked') = 1,
  'and emits no second event'
);

\echo ''
\echo 'who may do what (spec §14):'

select pg_temp.assert_raises(
  format('select public.confirm_payment(%L::uuid)', :'pay1'), 'HT042',
  'a debtor cannot confirm their own payment'
);
select pg_temp.act_as(:'dana');
select pg_temp.assert_raises(
  format('select public.confirm_payment(%L::uuid)', :'pay1'), 'HT042',
  'a bystander cannot confirm someone else''s payment'
);
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid)', :'carlo_share'), 'HT041',
  'nobody can mark someone else''s share paid'
);
select pg_temp.assert_raises(
  format('select public.record_payment_received(%L::uuid)', :'carlo_share'),
  'HT042', 'only the bill payer can record cash'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'confirm_payment:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.confirm_payment(:'pay1'::uuid);

select pg_temp.assert(
  (select status from public.bill_shares where id = :'carlo_share') = 'settled',
  'the share is settled'
);
select pg_temp.assert(
  (select settled_at is not null from public.bill_shares
   where id = :'carlo_share'),
  'and carries a settled timestamp'
);
select pg_temp.assert(
  (select status from public.payments where id = :'pay1') = 'confirmed',
  'the payment is confirmed'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'payment_confirmed') = 1,
  'emits payment_confirmed'
);
select pg_temp.assert(
  (select status from public.bills where id = :'bill') = 'open',
  'the bill stays open while someone still owes'
);

select public.confirm_payment(:'pay1'::uuid);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'payment_confirmed') = 1,
  'confirming twice is a no-op (spec §12.9)'
);

select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  not exists (
    select 1 from jsonb_array_elements(public.get_my_open_shares()) as e
    where e ->> 'bill_id' = :'bill'
  ),
  'a settled share drops off the debtor''s to-do list'
);
select pg_temp.assert(
  (select (public.get_my_balances() -> 0 ->> 'owed_by_me')::bigint) = 0,
  'and out of what they owe'
);

select pg_temp.act_as(:'bea');
select pg_temp.assert(
  (select (public.get_my_balances() -> 0 ->> 'owed_to_me')::bigint) = 300000,
  'the payer is still owed the one remaining share'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'reject_payment:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'dana');
select public.mark_share_paid(:'dana_share'::uuid, 'maya', null, :'gid' || '/proof-2.jpg') as pay2 \gset

select pg_temp.act_as(:'bea');
select public.reject_payment(:'pay2'::uuid, 'Nothing arrived in Maya');

select pg_temp.assert(
  (select status from public.bill_shares where id = :'dana_share') = 'unpaid',
  'a rejected payment puts the share back to unpaid'
);
select pg_temp.assert(
  (select rejected_reason from public.payments where id = :'pay2')
    = 'Nothing arrived in Maya',
  'the reason is kept for the debtor to read'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'payment_rejected') = 1,
  'emits payment_rejected'
);
select public.reject_payment(:'pay2'::uuid);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'payment_rejected') = 1,
  'rejecting twice is a no-op'
);
select pg_temp.assert_raises(
  format('select public.reject_payment(%L::uuid)', :'pay1'), 'HT045',
  'a confirmed payment cannot then be rejected'
);

\echo ''
\echo 'the debtor can try again after a rejection:'

select pg_temp.act_as(:'dana');
select public.mark_share_paid(:'dana_share'::uuid, 'gcash', 'REF999', :'gid' || '/proof-3.jpg') as pay3 \gset
select pg_temp.assert(
  :'pay3' <> :'pay2',
  'a fresh attempt is a new payment, not the rejected one'
);
select pg_temp.assert(
  (select count(*) from public.payments where bill_share_id = :'dana_share') = 2,
  'and the rejected attempt is kept as history'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'record_payment_received (cash in person):'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.record_payment_received(:'dana_share'::uuid, 'cash') as pay4 \gset

select pg_temp.assert(
  :'pay4' = :'pay3',
  'recording cash confirms the payment already in flight rather than duplicating it'
);
select pg_temp.assert(
  (select status from public.bill_shares where id = :'dana_share') = 'settled',
  'the share is settled'
);

\echo ''
\echo 'the last confirmation settles the bill (spec §7):'

select pg_temp.assert(
  (select status from public.bills where id = :'bill') = 'settled',
  'the bill is marked settled'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'bill_settled') = 1,
  'emits bill_settled exactly once'
);
select pg_temp.assert(
  (select (public.get_my_balances() -> 0 ->> 'owed_to_me')::bigint) = 0,
  'and nobody owes the payer anything'
);

\echo ''
\echo 'settled shares are closed:'

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid)', :'carlo_share'), 'HT043',
  'a settled share cannot be marked paid again'
);

\echo ''
\echo 'a voided bill cannot be paid:'

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Cancelled trip', 'total_amount', 20000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'))
)) as dead_bill \gset
select id as dead_share from public.bill_shares
where bill_id = :'dead_bill' and user_id = :'carlo' \gset
select public.void_bill(:'dead_bill'::uuid, 'Trip cancelled');

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid)', :'dead_share'), 'HT046',
  'a voided bill cannot be settled'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'proof of payment is required (HT047):'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Samgyup', 'total_amount', 120000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'))
)) as samgyup \gset
select id as samgyup_share from public.bill_shares
where bill_id = :'samgyup' and user_id = :'carlo' \gset

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid, %L)', :'samgyup_share', 'gcash'),
  'HT047', 'marking paid with no screenshot is refused'
);
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid, %L, null, %L)',
         :'samgyup_share', 'gcash', '   '),
  'HT047', 'a blank screenshot path is no screenshot'
);
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid, %L, null, %L)',
         :'samgyup_share', 'gcash', gen_random_uuid() || '/proof.jpg'),
  'HT047', 'a screenshot outside the bill''s group folder is refused'
);
select pg_temp.assert(
  (select status from public.bill_shares where id = :'samgyup_share') = 'unpaid',
  'and the share stays unpaid'
);

select public.mark_share_paid(
  :'samgyup_share'::uuid, 'gotyme', null, :'gid' || '/proof-4.jpg'
) as pay5 \gset
select pg_temp.assert(
  (select method from public.payments where id = :'pay5') = 'gotyme',
  'the newer e-wallets are accepted as a method'
);
select pg_temp.assert(
  public.mark_share_paid(:'samgyup_share'::uuid) = :'pay5'::uuid,
  'a duplicate tap still returns the claim in flight without a screenshot'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'cash needs no screenshot (D-70):'

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Taho', 'total_amount', 4000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'))
)) as taho \gset
select id as taho_share from public.bill_shares
where bill_id = :'taho' and user_id = :'carlo' \gset

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.mark_share_paid(%L::uuid, %L)', :'taho_share', 'maya'),
  'HT047', 'a wallet payment still needs its screenshot'
);
select public.mark_share_paid(:'taho_share'::uuid, 'cash') as cash_pay \gset
select pg_temp.assert(
  (select status from public.payments where id = :'cash_pay') = 'pending',
  'a cash claim goes through without one, awaiting the payer'
);
select pg_temp.assert(
  (select method from public.payments where id = :'cash_pay') = 'cash',
  'and is recorded as cash'
);

\echo ''
\echo 'set_bill_receive_method:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
insert into public.payment_methods (user_id, type, account_name, account_number, qr_image_path)
values (:'bea', 'shopeepay', 'Bea Reyes', '09171234567', :'bea' || '/qr.png')
returning id as bea_shopeepay \gset

select pg_temp.act_as(:'carlo');
insert into public.payment_methods (user_id, type, account_name, account_number)
values (:'carlo', 'gcash', 'Carlo Cruz', '09181234567')
returning id as carlo_gcash \gset

insert into public.payment_methods (user_id, type, account_name, account_number)
values (:'carlo', 'maribank', 'Carlo Cruz', '1234 5678 9012')
returning id as carlo_maribank \gset
select pg_temp.assert(
  (select type from public.payment_methods where id = :'carlo_maribank') = 'maribank',
  'MariBank is accepted as a payment method'
);

select pg_temp.assert_raises(
  format('select public.set_bill_receive_method(%L::uuid, %L::uuid)',
         :'samgyup', :'carlo_gcash'),
  'HT042', 'only the payer chooses where to be paid'
);

select pg_temp.act_as(:'bea');
select pg_temp.assert_raises(
  format('select public.set_bill_receive_method(%L::uuid, %L::uuid)',
         :'samgyup', :'carlo_gcash'),
  'HT048', 'the payer cannot point the bill at someone else''s wallet'
);

select public.set_bill_receive_method(:'samgyup'::uuid, :'bea_shopeepay'::uuid);
select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  (select receive_method_id from public.bills where id = :'samgyup')
    = :'bea_shopeepay'::uuid,
  'the choice is visible to the debtor'
);

select pg_temp.act_as(:'bea');
select public.set_bill_receive_method(:'samgyup'::uuid, null);
select pg_temp.assert(
  (select receive_method_id from public.bills where id = :'samgyup') is null,
  'null goes back to any wallet'
);

select public.set_bill_receive_method(:'samgyup'::uuid, :'bea_shopeepay'::uuid);
delete from public.payment_methods where id = :'bea_shopeepay';
select pg_temp.assert(
  (select receive_method_id from public.bills where id = :'samgyup') is null,
  'deleting the wallet falls back to any wallet'
);

select pg_temp.assert_raises(
  format('select public.set_bill_receive_method(%L::uuid)', :'dead_bill'),
  'HT046', 'a voided bill takes no choice'
);

\echo ''
\echo 'profiles.receive_method_id (D-66):'

select pg_temp.act_as(:'carlo');
update public.profiles set receive_method_id = :'carlo_gcash' where id = :'carlo';
select pg_temp.assert(
  (select receive_method_id from public.profiles where id = :'carlo') = :'carlo_gcash'::uuid,
  'you can set your own default wallet'
);
select pg_temp.act_as(:'bea');
select pg_temp.assert(
  (select receive_method_id from public.profiles where id = :'carlo') = :'carlo_gcash'::uuid,
  'and groupmates can see it, to know where to pay'
);
select pg_temp.assert_raises(
  format('update public.profiles set receive_method_id = %L where id = %L',
         :'carlo_gcash', :'bea'),
  'HT048', 'nobody can make someone else''s wallet their default'
);

reset role;
select pg_temp.act_as(:'bea');
insert into public.payment_methods (user_id, type, account_name, account_number)
values (:'bea', 'maya', 'Bea Reyes', '09171234567')
returning id as bea_maya \gset
set local role authenticated;
select public.set_bill_receive_method(:'samgyup'::uuid, :'bea_maya'::uuid);
reset role;
update public.bills set paid_by = :'carlo' where id = :'samgyup';
select pg_temp.assert(
  (select receive_method_id from public.bills where id = :'samgyup') is null,
  'a change of payer clears the old payer''s choice'
);

reset role;

\echo ''
\echo 'All payment tests passed.'

rollback;
