-- Hati — recurring bills (spec §7.1, §12.6, §12.7, §14).
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
select public.create_group('Kasama sa Bahay') as gid \gset
select public.create_invite(:'gid'::uuid) ->> 'token' as tok \gset
select pg_temp.act_as(:'carlo'); select public.join_group(:'tok');
select pg_temp.act_as(:'dana');  select public.join_group(:'tok');

-- ---------------------------------------------------------------------------
\echo 'the anchor day survives short months (spec §12.7):'
-- ---------------------------------------------------------------------------

select pg_temp.assert(
  public.advance_run_date('2026-01-31', 'monthly', 1, 31) = '2026-02-28',
  'the 31st becomes the 28th in February'
);
select pg_temp.assert(
  public.advance_run_date('2026-02-28', 'monthly', 1, 31) = '2026-03-31',
  'and climbs back to the 31st in March — it does not stay at 28'
);
select pg_temp.assert(
  public.advance_run_date('2026-03-31', 'monthly', 1, 31) = '2026-04-30',
  'April, which has thirty days'
);
select pg_temp.assert(
  public.advance_run_date('2028-01-31', 'monthly', 1, 31) = '2028-02-29',
  'and a leap February gets the 29th'
);
select pg_temp.assert(
  public.advance_run_date('2026-01-15', 'monthly', 2, 15) = '2026-03-15',
  'an interval of two skips a month'
);
select pg_temp.assert(
  public.advance_run_date('2026-01-05', 'weekly', 1, null) = '2026-01-12',
  'weekly adds seven days'
);
select pg_temp.assert(
  public.advance_run_date('2026-01-05', 'weekly', 2, null) = '2026-01-19',
  'fortnightly adds fourteen'
);
select pg_temp.assert(
  public.advance_run_date('2028-02-29', 'yearly', 1, null) = '2029-02-28',
  'a yearly bill dated 29 February lands on the 28th'
);
select pg_temp.assert_raises(
  $$ select public.advance_run_date('2026-01-01', 'hourly', 1, null) $$,
  'HT062', 'an unknown frequency is refused'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'creating a template:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.create_recurring_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Rent', 'total_amount', 3000000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'frequency', 'monthly', 'interval', 1, 'anchor_day', 1,
  'next_run_on', '2026-01-01',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'))
)) as rent \gset

select pg_temp.assert(
  (select title from public.recurring_bills where id = :'rent') = 'Rent',
  'the template is stored'
);
select pg_temp.assert(
  (select jsonb_array_length(split_config -> 'participants')
   from public.recurring_bills where id = :'rent') = 3,
  'with its participants'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'recurring_created') = 1,
  'and emits recurring_created'
);

select pg_temp.assert_raises(
  format('select public.create_recurring_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', 'Groceries', 'total_amount', 100000,
    'paid_by', :'bea', 'split_mode', 'itemized', 'frequency', 'monthly',
    'participants', jsonb_build_array(jsonb_build_object('user_id', :'bea'))
  )), 'HT062', 'a template cannot be itemized (spec §5.1)'
);
select pg_temp.assert_raises(
  format('select public.create_recurring_bill(%L::jsonb)', jsonb_build_object(
    'group_id', :'gid', 'title', 'Bad split', 'total_amount', 100000,
    'paid_by', :'bea', 'split_mode', 'percent', 'frequency', 'monthly',
    'participants', jsonb_build_array(
      jsonb_build_object('user_id', :'bea', 'input', 4000))
  )), 'HT024', 'a split that does not add up is caught at set-up, not at 6am'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'generating (spec §7.1):'
-- ---------------------------------------------------------------------------

set local role postgres;
select public.generate_recurring_bills('2026-01-01') as run1 \gset

select pg_temp.assert(
  (:'run1'::jsonb ->> 'created')::int = 1,
  'one bill is generated'
);
select pg_temp.assert(
  (select count(*) from public.bills where recurring_template_id = :'rent') = 1,
  'and it exists'
);
select pg_temp.assert(
  (select bill_date from public.bills where recurring_template_id = :'rent')
    = '2026-01-01',
  'dated the run date, not today'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares s
   join public.bills b on b.id = s.bill_id
   where b.recurring_template_id = :'rent') = 3,
  'the split is applied'
);
select pg_temp.assert(
  (select s.status from public.bill_shares s
   join public.bills b on b.id = s.bill_id
   where b.recurring_template_id = :'rent' and s.user_id = :'bea') = 'settled',
  'and the payer''s own share is settled, as on any other bill'
);
select pg_temp.assert(
  (select next_run_on from public.recurring_bills where id = :'rent')
    = '2026-02-01',
  'the template moves on to next month'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'recurring_generated') = 1,
  'emits recurring_generated'
);
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'recurring_generated') = 2,
  'and the two debtors are told'
);

\echo ''
\echo 'running it twice produces exactly one bill (spec §14):'

select public.generate_recurring_bills('2026-01-01') as run2 \gset
select pg_temp.assert(
  (:'run2'::jsonb ->> 'created')::int = 0,
  'the second run creates nothing'
);
select pg_temp.assert(
  (select count(*) from public.bills where recurring_template_id = :'rent') = 1,
  'and there is still exactly one bill'
);

\echo ''
\echo 'even if next_run_on is somehow rewound — the unique index holds:'

update public.recurring_bills set next_run_on = '2026-01-01' where id = :'rent';
select public.generate_recurring_bills('2026-01-01') as run3 \gset

select pg_temp.assert(
  (:'run3'::jsonb ->> 'created')::int = 0
    and (:'run3'::jsonb ->> 'already_existed')::int = 1,
  'the insert is refused and reported as already existing'
);
select pg_temp.assert(
  (select count(*) from public.bills where recurring_template_id = :'rent') = 1,
  'still one bill'
);

\echo ''
\echo 'catching up on missed runs:'

update public.recurring_bills set next_run_on = '2026-02-01' where id = :'rent';
select public.generate_recurring_bills('2026-04-15') as caught \gset

select pg_temp.assert(
  (:'caught'::jsonb ->> 'created')::int = 3,
  'February, March and April are all generated'
);
select pg_temp.assert(
  (select next_run_on from public.recurring_bills where id = :'rent')
    = '2026-05-01',
  'and the template is up to date'
);

\echo ''
\echo 'editing a template revalidates the split:'

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.update_recurring_bill(:'rent'::uuid, jsonb_build_object(
  'title', 'Rent and utilities', 'total_amount', 3600000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'frequency', 'monthly', 'interval', 1, 'anchor_day', 1,
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'),
    jsonb_build_object('user_id', :'dana'))
));

select pg_temp.assert(
  (select title from public.recurring_bills where id = :'rent')
    = 'Rent and utilities',
  'the template is updated'
);
select pg_temp.assert_raises(
  format('select public.update_recurring_bill(%L::uuid, %L::jsonb)', :'rent',
    jsonb_build_object(
      'title', 'Broken', 'total_amount', 100000, 'paid_by', :'bea',
      'split_mode', 'percent', 'frequency', 'monthly',
      'participants', jsonb_build_array(
        jsonb_build_object('user_id', :'bea', 'input', 9000)))),
  'HT024', 'an edit that breaks the split is refused'
);
select pg_temp.assert(
  (select total_amount from public.recurring_bills where id = :'rent')
    = 3600000,
  'and the refused edit changed nothing'
);

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.update_recurring_bill(%L::uuid, %L::jsonb)', :'rent',
    jsonb_build_object(
      'title', 'Hijacked', 'total_amount', 100, 'paid_by', :'bea',
      'split_mode', 'equal', 'frequency', 'monthly',
      'participants', jsonb_build_array(jsonb_build_object('user_id', :'bea')))),
  'HT061', 'a plain member cannot edit someone else''s template'
);

set local role postgres;

\echo ''
\echo 'a paused template does nothing:'

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.set_recurring_paused(:'rent'::uuid, true);

set local role postgres;
select public.generate_recurring_bills('2026-06-01') as paused_run \gset
select pg_temp.assert(
  (:'paused_run'::jsonb ->> 'created')::int = 0,
  'nothing is generated while paused'
);

set local role authenticated;
select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.set_recurring_paused(%L::uuid, false)', :'rent'),
  'HT061', 'a plain member cannot resume someone else''s template'
);

select pg_temp.act_as(:'bea');
select public.set_recurring_paused(:'rent'::uuid, false);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'people who leave (spec §12.6):'
-- ---------------------------------------------------------------------------

set local role postgres;
update public.bill_shares set status = 'settled'
where user_id = :'dana';
update public.group_members set left_at = now()
where group_id = :'gid' and user_id = :'dana';

update public.recurring_bills set next_run_on = '2026-07-01' where id = :'rent';
select public.generate_recurring_bills('2026-07-01');

select pg_temp.assert(
  (select count(*) from public.bill_shares s
   join public.bills b on b.id = s.bill_id
   where b.recurring_template_id = :'rent' and b.bill_date = '2026-07-01') = 2,
  'someone who left is skipped'
);
select pg_temp.assert(
  (select count(*) from public.bill_shares s
   join public.bills b on b.id = s.bill_id
   where b.recurring_template_id = :'rent'
     and b.bill_date = '2026-07-01' and s.user_id = :'dana') = 0,
  'and gets no share'
);

\echo ''
\echo 'if the payer leaves, the template stops and someone is told:'

update public.group_members set left_at = now()
where group_id = :'gid' and user_id = :'bea';
update public.recurring_bills set next_run_on = '2026-08-01' where id = :'rent';

select public.generate_recurring_bills('2026-08-01') as gone \gset

select pg_temp.assert(
  (:'gone'::jsonb ->> 'paused')::int = 1,
  'the run reports it paused something'
);
select pg_temp.assert(
  (select paused from public.recurring_bills where id = :'rent'),
  'the template is paused'
);
select pg_temp.assert(
  (select count(*) from public.bills
   where recurring_template_id = :'rent' and bill_date = '2026-08-01') = 0,
  'no bill is generated'
);
select pg_temp.assert(
  (select count(*) from public.notifications
   where type = 'recurring_paused') > 0,
  'and somebody is told why'
);
select pg_temp.assert(
  (select body from public.notifications
   where type = 'recurring_paused' limit 1) like '%has left the group%',
  'with the reason spelled out'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'an end date stops it:'
-- ---------------------------------------------------------------------------

update public.group_members set left_at = null
where group_id = :'gid' and user_id = :'bea';

update public.recurring_bills
set paused = false, next_run_on = '2026-09-01', ends_on = '2026-09-15'
where id = :'rent';

select public.generate_recurring_bills('2026-12-01') as ending \gset
select pg_temp.assert(
  (:'ending'::jsonb ->> 'created')::int = 1,
  'only the run inside the window happens'
);
select pg_temp.assert(
  (select paused from public.recurring_bills where id = :'rent'),
  'and the template pauses itself once it is past its end date'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'deleting a template leaves its bills alone (spec §10):'
-- ---------------------------------------------------------------------------

-- Counted across the group, not by title: the edit above renamed the
-- template, so later bills carry a different one.
select count(*) as bills_before from public.bills
where group_id = :'gid' \gset

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.delete_recurring_bill(:'rent'::uuid);

select pg_temp.assert(
  (select count(*) from public.recurring_bills where id = :'rent') = 0,
  'the template is gone'
);

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.bills where group_id = :'gid')
    = :'bills_before'::int,
  'the bills it made survive, detached from it'
);
select pg_temp.assert(
  (select count(*) from public.bills
   where recurring_template_id = :'rent') = 0,
  'and no longer point at a template that is gone'
);

\echo ''
\echo 'the daily job does both things:'

select public.run_daily_jobs() as daily \gset
select pg_temp.assert(
  :'daily'::jsonb ? 'recurring' and :'daily'::jsonb ? 'reminders_sent',
  'one job, both responsibilities'
);

reset role;

\echo ''
\echo 'All recurring tests passed.'

rollback;
