-- Hati — activity feed and comments (spec §4.1, §5.3, §10).
--
--   tool/run_sql_tests_local.sh

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\set bea     '11111111-1111-1111-1111-111111111111'
\set carlo   '22222222-2222-2222-2222-222222222222'
\set mallory '33333333-3333-3333-3333-333333333333'

select pg_temp.make_user(:'bea',     'Bea',     'bea@example.test');
select pg_temp.make_user(:'carlo',   'Carlo',   'carlo@example.test');
select pg_temp.make_user(:'mallory', 'Mallory', 'mallory@example.test');

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.create_group('Tagaytay Staycation') as gid \gset
select public.create_invite(:'gid'::uuid) ->> 'token' as tok \gset
select pg_temp.act_as(:'carlo'); select public.join_group(:'tok');

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Airbnb – 2 nights', 'total_amount', 200000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'))
)) as bill \gset

-- A second group, to prove the feeds are scoped.
select public.create_group('Office Lunch') as other_gid \gset

-- ---------------------------------------------------------------------------
\echo 'comments emit activity through a trigger (spec §4.1):'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
insert into public.comments (bill_id, author_id, body)
values (:'bill', :'carlo', 'Booked it, thanks Bea!');

select pg_temp.assert(
  (select count(*) from public.activity_events
   where bill_id = :'bill' and type = 'comment_added') = 1,
  'a comment inserted straight through PostgREST still emits an event'
);
select pg_temp.assert(
  (select payload ->> 'excerpt' from public.activity_events
   where type = 'comment_added') = 'Booked it, thanks Bea!',
  'the event carries an excerpt, so the feed reads without the comment'
);
select pg_temp.assert(
  (select payload ->> 'display_name' from public.activity_events
   where type = 'comment_added') = 'Carlo',
  'and who wrote it'
);
select pg_temp.assert(
  (select comment_id is not null from public.activity_events
   where type = 'comment_added'),
  'and points back at the comment'
);

\echo ''
\echo 'edits are timestamped by the database, not the client:'

select pg_temp.assert(
  (select edited_at is null from public.comments where bill_id = :'bill'),
  'a fresh comment is not marked edited'
);

update public.comments set body = 'Booked it — thanks Bea!'
where bill_id = :'bill' and author_id = :'carlo';

select pg_temp.assert(
  (select edited_at is not null from public.comments where bill_id = :'bill'),
  'changing the body sets edited_at'
);

-- Touching another column must not claim the text changed.
set local role postgres;
update public.comments set edited_at = null where bill_id = :'bill';
set local role authenticated;
select pg_temp.act_as(:'carlo');

update public.comments set deleted_at = now()
where bill_id = :'bill' and author_id = :'carlo';

select pg_temp.assert(
  (select edited_at is null from public.comments where bill_id = :'bill'),
  'a soft delete does not count as an edit'
);

set local role postgres;
update public.comments set deleted_at = null where bill_id = :'bill';
set local role authenticated;
select pg_temp.act_as(:'carlo');

\echo ''
\echo 'comment permissions (spec §5.4):'

-- Note the shape of these two: `authenticated` *has* UPDATE and DELETE on
-- comments, so RLS does not refuse — it narrows the rows the statement can
-- see, and a statement that matches nothing succeeds quietly. The assertion
-- therefore has to be about the effect, not about an error. (The privilege-less
-- tables elsewhere do raise 42501, which is why those tests look different.)
select pg_temp.act_as(:'bea');

update public.comments set body = 'Hijacked' where bill_id = :'bill';
select pg_temp.assert(
  (select body from public.comments where bill_id = :'bill')
    = 'Booked it — thanks Bea!',
  'an update by someone else touches no rows'
);

delete from public.comments where bill_id = :'bill';
select pg_temp.assert(
  (select count(*) from public.comments where bill_id = :'bill') = 1,
  'and neither does a delete'
);

-- An INSERT is different again: a WITH CHECK violation does raise.
select pg_temp.act_as(:'mallory');
select pg_temp.assert_raises(
  format(
    'insert into public.comments (bill_id, author_id, body) values (%L, %L, %L)',
    :'bill', :'mallory', 'Gatecrash'
  ),
  '42501', 'an outsider cannot comment on a bill'
);
select pg_temp.assert_raises(
  format(
    'insert into public.comments (bill_id, author_id, body) values (%L, %L, %L)',
    :'bill', :'carlo', 'Forged authorship'
  ),
  '42501', 'nor can a member post as someone else'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'the group feed:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.get_activity_feed(:'gid'::uuid) as feed \gset

select pg_temp.assert(
  jsonb_array_length(:'feed'::jsonb) = 4,
  format('four events so far, got %s',
         jsonb_array_length(:'feed'::jsonb))
);
select pg_temp.assert(
  (:'feed'::jsonb -> 0 ->> 'type') = 'comment_added',
  'newest first'
);
select pg_temp.assert(
  (:'feed'::jsonb -> 0 ->> 'actor_name') = 'Carlo',
  'the actor name is resolved for the caller'
);
select pg_temp.assert(
  (:'feed'::jsonb -> 0 ->> 'group_name') = 'Tagaytay Staycation',
  'and the group name'
);
select pg_temp.assert(
  not exists (
    select 1 from jsonb_array_elements(:'feed'::jsonb) as e
    where e ->> 'group_id' <> :'gid'
  ),
  'a group feed carries only that group'
);

\echo ''
\echo 'the merged feed (spec §10):'

select public.get_activity_feed() as global \gset
select pg_temp.assert(
  jsonb_array_length(:'global'::jsonb) = 5,
  format('spans both groups, got %s', jsonb_array_length(:'global'::jsonb))
);
select pg_temp.assert(
  (select count(distinct e ->> 'group_id')
   from jsonb_array_elements(:'global'::jsonb) as e) = 2,
  'and names both'
);

\echo ''
\echo 'a non-member sees none of it (spec §14):'

select pg_temp.act_as(:'mallory');
select pg_temp.assert(
  jsonb_array_length(public.get_activity_feed()) = 0,
  'an outsider''s merged feed is empty'
);
select pg_temp.assert(
  jsonb_array_length(public.get_activity_feed(:'gid'::uuid)) = 0,
  'and asking for a specific group changes nothing'
);

select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  jsonb_array_length(public.get_activity_feed(:'other_gid'::uuid)) = 0,
  'a member of one group cannot read another group''s feed'
);

\echo ''
\echo 'paging:'

select pg_temp.act_as(:'bea');
select public.get_activity_feed(null, 2) as page1 \gset
select pg_temp.assert(
  jsonb_array_length(:'page1'::jsonb) = 2,
  'the limit is honoured'
);

select (:'page1'::jsonb -> 1 ->> 'created_at') as cursor \gset
select public.get_activity_feed(null, 10, :'cursor'::timestamptz) as page2 \gset

select pg_temp.assert(
  not exists (
    select 1
    from jsonb_array_elements(:'page1'::jsonb) as a,
         jsonb_array_elements(:'page2'::jsonb) as b
    where a ->> 'id' = b ->> 'id'
  ),
  'the next page does not repeat the first'
);
select pg_temp.assert(
  jsonb_array_length(:'page1'::jsonb) + jsonb_array_length(:'page2'::jsonb) = 5,
  'and together they cover everything'
);

\echo ''
\echo 'the feed still cannot be forged:'

select pg_temp.assert_raises(
  format(
    'insert into public.activity_events (group_id, actor_id, type) values (%L, %L, %L)',
    :'gid', :'bea', 'bill_settled'
  ),
  '42501', 'not even by a member of the group'
);

reset role;

\echo ''
\echo 'All activity tests passed.'

rollback;
