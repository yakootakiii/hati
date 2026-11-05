-- Hati — notification fan-out, reminders and nudges (spec §7.2).
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

-- ---------------------------------------------------------------------------
\echo 'member_joined tells the people already there:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo'); select public.join_group(:'tok');

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'member_joined' and user_id = :'bea') = 1,
  'the existing member is told'
);
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'member_joined' and user_id = :'carlo') = 0,
  'the joiner is not told about themselves'
);
select pg_temp.assert(
  (select title from public.notifications where type = 'member_joined')
    = 'Carlo joined Tagaytay Staycation',
  'and the copy names them and the group'
);
set local role authenticated;

select pg_temp.act_as(:'dana'); select public.join_group(:'tok');

-- ---------------------------------------------------------------------------
\echo ''
\echo 'bill_created tells each participant what they owe:'
-- ---------------------------------------------------------------------------

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

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'bill_created') = 2,
  'both other participants are told, and only them'
);
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'bill_created' and user_id = :'bea') = 0,
  'the person who added it is not told'
);
select pg_temp.assert(
  (select title from public.notifications
   where type = 'bill_created' and user_id = :'carlo')
    = 'Bea added Airbnb – 2 nights',
  'the title reads as the spec example does'
);
select pg_temp.assert(
  (select body from public.notifications
   where type = 'bill_created' and user_id = :'carlo') = 'You owe ₱3,000.00.',
  'and the body carries that person''s own share'
);
select pg_temp.assert(
  (select data ->> 'route' from public.notifications
   where type = 'bill_created' and user_id = :'carlo') = '/bills/' || :'bill',
  'tapping it deep-links to the bill (spec §10)'
);
set local role authenticated;

\echo ''
\echo 'preferences are honoured before the row is written:'

select pg_temp.act_as(:'dana');
update public.notification_prefs set new_bill = false where user_id = :'dana';

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Groceries', 'total_amount', 60000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'))
)) as groceries \gset

set local role postgres;
-- Scoped to this bill: Dana was quite properly told about the earlier one.
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'bill_created'
     and user_id = :'dana'
     and data ->> 'route' = '/bills/' || :'groceries') = 0,
  'someone who switched new_bill off gets nothing'
);
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'bill_created'
     and user_id = :'carlo'
     and data ->> 'route' = '/bills/' || :'groceries') = 1,
  'and it does not affect anyone else'
);
set local role authenticated;

select pg_temp.act_as(:'dana');
update public.notification_prefs set new_bill = true where user_id = :'dana';

-- ---------------------------------------------------------------------------
\echo ''
\echo 'the settlement round trip:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select public.mark_share_paid(:'carlo_share'::uuid, 'gcash', 'REF1', :'gid' || '/proof.jpg') as pay \gset

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'payment_marked') = 1,
  'exactly one person is told a payment was marked'
);
select pg_temp.assert(
  (select user_id from public.notifications where type = 'payment_marked')
    = :'bea',
  'and it is the payer of the bill'
);
select pg_temp.assert(
  (select title from public.notifications where type = 'payment_marked')
    = 'Carlo marked ₱3,000.00 as paid',
  'the copy names the debtor and the amount'
);
select pg_temp.assert(
  (select body from public.notifications where type = 'payment_marked')
    like '%Tap to confirm.',
  'and says what to do about it'
);
set local role authenticated;

select pg_temp.act_as(:'bea');
select public.reject_payment(:'pay'::uuid, 'Nothing arrived in GCash');

set local role postgres;
select pg_temp.assert(
  (select user_id from public.notifications where type = 'payment_rejected')
    = :'carlo',
  'a rejection goes back to the debtor'
);
select pg_temp.assert(
  (select body from public.notifications where type = 'payment_rejected')
    like '%Nothing arrived in GCash',
  'carrying the reason the payer gave'
);
set local role authenticated;

select pg_temp.act_as(:'carlo');
select public.mark_share_paid(:'carlo_share'::uuid, 'gcash', 'REF2', :'gid' || '/proof.jpg') as pay2 \gset
select pg_temp.act_as(:'bea');
select public.confirm_payment(:'pay2'::uuid);

set local role postgres;
select pg_temp.assert(
  (select user_id from public.notifications where type = 'payment_confirmed')
    = :'carlo',
  'a confirmation goes to the debtor'
);
select pg_temp.assert(
  (select title from public.notifications where type = 'payment_confirmed')
    = 'Bea confirmed your ₱3,000.00 payment',
  'and reads as the spec example does'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
\echo ''
\echo 'comments tell the whole bill:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'dana');
insert into public.comments (bill_id, author_id, body)
values (:'bill', :'dana', 'Wait, was parking included?');

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications where type = 'comment_added') = 2,
  'the other two participants hear about it'
);
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'comment_added' and user_id = :'dana') = 0,
  'but not the author'
);
select pg_temp.assert(
  (select distinct body from public.notifications where type = 'comment_added')
    = 'Wait, was parking included?',
  'and the excerpt is the body'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
\echo ''
\echo 'reminders (spec §7.2):'
-- ---------------------------------------------------------------------------

set local role postgres;
select count(*) as before_reminders from public.notifications
where type = 'reminder' \gset

select pg_temp.assert(
  public.send_reminders() = 0,
  'nothing is due on a bill added today'
);

-- Four days old: the first reminder is due.
update public.bill_shares set created_at = now() - interval '4 days'
where bill_id = :'groceries';

select pg_temp.assert(
  public.send_reminders() = 2,
  'both unpaid shares get their three-day reminder'
);
select pg_temp.assert(
  public.send_reminders() = 0,
  'and running the job again sends nothing'
);
select pg_temp.assert(
  (select body from public.notifications
   where type = 'reminder' and user_id = :'carlo' limit 1) = 'For Groceries.',
  'the reminder names the bill'
);
select pg_temp.assert(
  (select title from public.notifications
   where type = 'reminder' and user_id = :'carlo' limit 1)
    = 'You still owe Bea ₱300.00',
  'and who is owed what'
);

-- Eight days old, and reminded three days in — the timeline a real share
-- would have. Ageing created_at alone would leave last_reminded_at sitting
-- after a date it actually preceded.
update public.bill_shares
set created_at = now() - interval '8 days',
    last_reminded_at = now() - interval '5 days'
where bill_id = :'groceries';

select pg_temp.assert(
  public.send_reminders() = 2,
  'the seven-day reminder goes out'
);
select pg_temp.assert(
  public.send_reminders() = 0,
  'and then it stops — two reminders, not a stream'
);

update public.bill_shares set created_at = now() - interval '40 days'
where bill_id = :'groceries';
select pg_temp.assert(
  public.send_reminders() = 0,
  'even long afterwards'
);

\echo ''
\echo 'a settled share is never reminded:'

update public.bill_shares
set status = 'settled', last_reminded_at = null, created_at = now() - interval '10 days'
where bill_id = :'groceries';

select pg_temp.assert(
  public.send_reminders() = 0,
  'settling stops the reminders'
);

update public.bill_shares
set status = 'unpaid', last_reminded_at = null
where bill_id = :'groceries';

\echo ''
\echo 'and neither is someone who switched reminders off:'

update public.notification_prefs set reminders = false where user_id = :'dana';
select pg_temp.assert(
  public.send_reminders() = 1,
  'only the one who still wants them'
);
update public.notification_prefs set reminders = true where user_id = :'dana';

-- ---------------------------------------------------------------------------
\echo ''
\echo 'nudge (spec §7.2):'
-- ---------------------------------------------------------------------------

update public.bill_shares set last_reminded_at = null where bill_id = :'bill';
set local role authenticated;

select id as dana_share from public.bill_shares
where bill_id = :'bill' and user_id = :'dana' \gset

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.nudge_share(%L::uuid)', :'dana_share'),
  'HT051', 'only the payer of the bill can nudge'
);

select pg_temp.act_as(:'bea');
select public.nudge_share(:'dana_share'::uuid);

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'nudge' and user_id = :'dana') = 1,
  'the debtor is nudged'
);
select pg_temp.assert(
  (select title from public.notifications where type = 'nudge')
    = 'Bea is waiting on ₱3,000.00',
  'and knows who and how much'
);
select pg_temp.assert(
  (select last_reminded_at is not null from public.bill_shares
   where id = :'dana_share'),
  'the nudge is recorded against the share'
);
set local role authenticated;

select pg_temp.act_as(:'bea');
select pg_temp.assert_raises(
  format('select public.nudge_share(%L::uuid)', :'dana_share'),
  'HT053', 'a second nudge within the day is refused'
);

set local role postgres;
update public.bill_shares set last_reminded_at = now() - interval '25 hours'
where id = :'dana_share';
set local role authenticated;
select pg_temp.act_as(:'bea');

select public.nudge_share(:'dana_share'::uuid);
set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'nudge' and user_id = :'dana') = 2,
  'but a day later is fine'
);
set local role authenticated;

select pg_temp.act_as(:'bea');
select pg_temp.assert_raises(
  format('select public.nudge_share(%L::uuid)', :'carlo_share'),
  'HT052', 'a settled share cannot be nudged'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'notifications are private (spec §5.4):'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'dana');
select pg_temp.assert(
  (select count(*) from public.notifications where user_id <> :'dana') = 0,
  'nobody reads anyone else''s notifications'
);
select pg_temp.assert(
  (select count(*) from public.notifications) > 0,
  'but they do read their own'
);

update public.notifications set read_at = now() where user_id = :'dana';
select pg_temp.assert(
  (select count(*) from public.notifications
   where user_id = :'dana' and read_at is null) = 0,
  'marking as read is allowed'
);

select pg_temp.assert_raises(
  format('update public.notifications set title = %L where user_id = %L',
         'Rewritten', :'dana'),
  '42501', 'but rewriting one is not — read_at is a column-level grant'
);

reset role;

\echo ''
\echo 'All notification tests passed.'

rollback;
