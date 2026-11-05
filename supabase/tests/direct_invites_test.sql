-- Hati — invite by name tests (DECISIONS D-57).
--
--   tool/run_sql_tests_local.sh
--
-- Runs inside a transaction that always rolls back.

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\set bea     '11111111-1111-1111-1111-111111111111'
\set carlo   '22222222-2222-2222-2222-222222222222'
\set dana    '33333333-3333-3333-3333-333333333333'
\set mallory '44444444-4444-4444-4444-444444444444'
\set carla   '66666666-6666-6666-6666-666666666666'

select pg_temp.make_user(:'bea',     'Bea',        'bea@example.test');
select pg_temp.make_user(:'carlo',   'Carlo',      'carlo@example.test');
select pg_temp.make_user(:'dana',    'Dana',       'dana@example.test');
select pg_temp.make_user(:'mallory', 'Mallory',    'mallory@example.test');
select pg_temp.make_user(:'carla',   'Carla 100%', 'carla@example.test');

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.create_group('Baguio Trip') as gid \gset

-- ---------------------------------------------------------------------------
\echo 'search_people:'
-- ---------------------------------------------------------------------------

select pg_temp.assert(
  (select array_agg(display_name order by display_name)
   from public.search_people(:'gid', 'car')) = array['Carla 100%', 'Carlo'],
  'matches names by substring, case-insensitively'
);
select pg_temp.assert(
  not exists (select 1 from public.search_people(:'gid', 'bea')),
  'never returns the caller'
);
select pg_temp.assert(
  (select display_name from public.search_people(:'gid', 'DANA@example.test')) = 'Dana',
  'finds someone by exact email, case-insensitively'
);
select pg_temp.assert(
  not exists (select 1 from public.search_people(:'gid', 'example.test')),
  'a partial email matches nobody'
);
select pg_temp.assert(
  (select count(*) from public.search_people(:'gid', '0%')) = 1,
  'a typed % is literal, not a wildcard'
);
select pg_temp.assert_raises(
  $$ select * from public.search_people('$$ || :'gid' || $$', ' c ') $$, 'HT074',
  'needs two characters after trimming'
);

select pg_temp.act_as(:'mallory');
select pg_temp.assert_raises(
  $$ select * from public.search_people('$$ || :'gid' || $$', 'car') $$, 'HT002',
  'an outsider cannot search on behalf of the group'
);

-- ---------------------------------------------------------------------------
\echo 'invite_person:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select public.invite_person(:'gid', :'carlo') as inv \gset

select pg_temp.assert(
  public.invite_person(:'gid', :'carlo') = :'inv',
  'inviting twice returns the same pending invite'
);

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.notifications
   where user_id = :'carlo' and type = 'group_invite') = 1,
  'notifies the invitee exactly once'
);
select pg_temp.assert(
  (select title from public.notifications
   where user_id = :'carlo' and type = 'group_invite') = 'Bea invited you to Baguio Trip',
  'the notification names the inviter and the group'
);
set local role authenticated;

select pg_temp.assert(
  (select status from public.search_people(:'gid', 'carlo')) = 'pending',
  'search shows the invite as pending'
);
select pg_temp.assert_raises(
  $$ select public.invite_person('$$ || :'gid' || $$', '$$ || :'bea' || $$') $$, 'HT010',
  'cannot invite yourself'
);

select pg_temp.act_as(:'mallory');
select pg_temp.assert_raises(
  $$ select public.invite_person('$$ || :'gid' || $$', '$$ || :'dana' || $$') $$, 'HT002',
  'an outsider cannot invite'
);

-- ---------------------------------------------------------------------------
\echo 'visibility before joining:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  not exists (select 1 from public.groups where id = :'gid'),
  'the invitee still cannot read the group'
);
select pg_temp.assert(
  (select group_name || ' / ' || inviter_name from public.get_my_direct_invites())
    = 'Baguio Trip / Bea',
  'but sees the invite with group and inviter names'
);
select pg_temp.assert(
  (select count(*) from public.group_direct_invites) = 1,
  'the invitee can read their own invite row'
);

select pg_temp.act_as(:'mallory');
select pg_temp.assert(
  (select count(*) from public.group_direct_invites) = 0,
  'nobody else can read it'
);
select pg_temp.assert(
  (select count(*) from public.get_my_direct_invites()) = 0,
  'nor sees it in their own list'
);
select pg_temp.assert_raises(
  $$ select public.respond_to_invite('$$ || :'inv' || $$', true) $$, 'HT070',
  'nor can answer it'
);

-- ---------------------------------------------------------------------------
\echo 'respond_to_invite:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select pg_temp.assert(
  public.respond_to_invite(:'inv', true) = :'gid',
  'accepting returns the group'
);
select pg_temp.assert(
  public.is_group_member(:'gid'),
  'accepting makes them a member'
);
select pg_temp.assert(
  (select data ->> 'status' from public.notifications where type = 'group_invite') = 'accepted'
  and (select read_at from public.notifications where type = 'group_invite') is not null,
  'the notification flips to accepted and is marked read'
);
select pg_temp.assert_raises(
  $$ select public.respond_to_invite('$$ || :'inv' || $$', true) $$, 'HT072',
  'an answered invite cannot be answered again'
);

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'member_joined') = 1,
  'emits member_joined'
);
select pg_temp.assert(
  exists (select 1 from public.notifications
          where user_id = :'bea' and type = 'member_joined'),
  'which tells the rest of the group'
);
set local role authenticated;

select pg_temp.act_as(:'bea');
select pg_temp.assert(
  (select status from public.search_people(:'gid', 'carlo')) = 'member',
  'search now shows them as a member'
);
select pg_temp.assert_raises(
  $$ select public.invite_person('$$ || :'gid' || $$', '$$ || :'carlo' || $$') $$, 'HT071',
  'a member cannot be invited again'
);

-- ---------------------------------------------------------------------------
\echo 'declining:'
-- ---------------------------------------------------------------------------

select public.invite_person(:'gid', :'dana') as inv2 \gset

select pg_temp.act_as(:'dana');
select public.respond_to_invite(:'inv2', false);
select pg_temp.assert(
  not public.is_group_member(:'gid'),
  'declining does not join'
);

select pg_temp.act_as(:'bea');
select pg_temp.assert_raises(
  $$ select public.invite_person('$$ || :'gid' || $$', '$$ || :'dana' || $$') $$, 'HT073',
  'a decline holds for a day'
);

set local role postgres;
update public.group_direct_invites
set responded_at = now() - interval '25 hours'
where id = :'inv2';
set local role authenticated;

select pg_temp.assert(
  public.invite_person(:'gid', :'dana') = :'inv2',
  'after a day they can be invited again, on the same row'
);
set local role postgres;
select pg_temp.assert(
  (select status from public.group_direct_invites where id = :'inv2') = 'pending',
  'which is pending again'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
\echo 'cancel_direct_invite:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  $$ select public.cancel_direct_invite('$$ || :'inv2' || $$') $$, 'HT002',
  'a plain member cannot cancel'
);

select pg_temp.act_as(:'bea');
select public.cancel_direct_invite(:'inv2');

select pg_temp.act_as(:'dana');
select pg_temp.assert(
  (select count(*) from public.get_my_direct_invites()) = 0,
  'a cancelled invite leaves the invitee''s list'
);
select pg_temp.assert(
  (select bool_and(data ->> 'status' = 'cancelled') from public.notifications
   where type = 'group_invite'),
  'and its notifications stop offering Join'
);
select pg_temp.assert_raises(
  $$ select public.respond_to_invite('$$ || :'inv2' || $$', true) $$, 'HT072',
  'and it can no longer be accepted'
);

-- ---------------------------------------------------------------------------
\echo 'rejoining:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select public.leave_group(:'gid');

select pg_temp.act_as(:'bea');
select public.invite_person(:'gid', :'carlo') as inv3 \gset
select pg_temp.assert(
  :'inv3' = :'inv',
  'someone who left can be invited back'
);

select pg_temp.act_as(:'carlo');
select public.respond_to_invite(:'inv3', true);
set local role postgres;
select pg_temp.assert(
  (select count(*) from public.group_members
   where group_id = :'gid' and user_id = :'carlo' and left_at is null) = 1,
  'accepting restores their old membership row'
);

rollback;
