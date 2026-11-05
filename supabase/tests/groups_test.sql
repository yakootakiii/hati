-- Hati — group, invite and membership RPC tests (spec §7, §8, §12.3).
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
\set billA   '55555555-5555-5555-5555-555555555555'

select pg_temp.make_user(:'bea',     'Bea',     'bea@example.test');
select pg_temp.make_user(:'carlo',   'Carlo',   'carlo@example.test');
select pg_temp.make_user(:'dana',    'Dana',    'dana@example.test');
select pg_temp.make_user(:'mallory', 'Mallory', 'mallory@example.test');

set local role authenticated;
select pg_temp.act_as(:'bea');

-- ---------------------------------------------------------------------------
\echo 'create_group:'
-- ---------------------------------------------------------------------------

select public.create_group('Tagaytay Staycation') as gid \gset

select pg_temp.assert(
  (select name from public.groups where id = :'gid') = 'Tagaytay Staycation',
  'creates the group'
);
select pg_temp.assert(
  (select role from public.group_members
   where group_id = :'gid' and user_id = :'bea') = 'owner',
  'makes the creator the owner'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'group_created') = 1,
  'emits group_created'
);
select pg_temp.assert_raises(
  $$ select public.create_group('   ') $$, 'HT010',
  'refuses a blank name'
);

-- ---------------------------------------------------------------------------
\echo 'invites:'
-- ---------------------------------------------------------------------------

select public.create_invite(:'gid'::uuid) ->> 'token' as token \gset

select pg_temp.assert(
  length(:'token') >= 22,
  'mints a token of at least 22 characters'
);

select pg_temp.act_as(:'carlo');
select public.get_invite_preview(:'token') as preview \gset

select pg_temp.assert(
  (:'preview'::jsonb ->> 'valid')::boolean
    and :'preview'::jsonb ->> 'group_name' = 'Tagaytay Staycation'
    and (:'preview'::jsonb ->> 'member_count')::int = 1
    and :'preview'::jsonb ->> 'inviter_name' = 'Bea',
  'preview shows the group to a non-member'
);
select pg_temp.assert(
  not (:'preview'::jsonb ->> 'already_member')::boolean,
  'preview reports the viewer is not yet a member'
);

-- ---------------------------------------------------------------------------
\echo 'join_group:'
-- ---------------------------------------------------------------------------

select public.join_group(:'token') as joined_gid \gset

select pg_temp.assert(:'joined_gid' = :'gid', 'returns the group joined');
select pg_temp.assert(
  (select role from public.group_members
   where group_id = :'gid' and user_id = :'carlo') = 'member',
  'adds the joiner as a plain member'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'member_joined') = 1,
  'emits member_joined'
);

set local role postgres;
select pg_temp.assert(
  (select use_count from public.group_invites where token = :'token') = 1,
  'counts the use'
);
set local role authenticated;
select pg_temp.act_as(:'carlo');

-- Idempotency (spec §7): tapping the link again changes nothing.
select public.join_group(:'token') as rejoined \gset
select pg_temp.assert(:'rejoined' = :'gid', 'joining twice returns the same group');

set local role postgres;
select pg_temp.assert(
  (select use_count from public.group_invites where token = :'token') = 1,
  'joining twice does not consume a second use'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'member_joined') = 1,
  'joining twice does not emit a second event'
);
set local role authenticated;
select pg_temp.act_as(:'carlo');

select public.get_invite_preview(:'token') as preview2 \gset
select pg_temp.assert(
  (:'preview2'::jsonb ->> 'already_member')::boolean,
  'preview reports an existing member'
);

select pg_temp.assert_raises(
  format('select public.create_invite(%L::uuid)', :'gid'), 'HT002',
  'a plain member cannot mint an invite'
);
select pg_temp.assert_raises(
  $$ select public.join_group('not-a-real-token') $$, 'HT003',
  'an unknown token is refused'
);

-- ---------------------------------------------------------------------------
\echo 'invite lifecycle:'
-- ---------------------------------------------------------------------------

-- Reset link: the old token dies as the new one is minted (spec §8).
select pg_temp.act_as(:'bea');
select public.create_invite(:'gid'::uuid, null, null, true) ->> 'token' as token2 \gset

select pg_temp.act_as(:'dana');
select public.get_invite_preview(:'token') as revoked_preview \gset

select pg_temp.assert(
  not (:'revoked_preview'::jsonb ->> 'valid')::boolean
    and :'revoked_preview'::jsonb ->> 'reason' = 'revoked',
  'a reset link previews as revoked'
);
select pg_temp.assert(
  :'revoked_preview'::jsonb ->> 'group_name' is null,
  'a revoked link does not leak the group name'
);
select pg_temp.assert_raises(
  format('select public.join_group(%L)', :'token'), 'HT005',
  'a revoked link cannot be joined'
);

-- Expiry.
set local role postgres;
insert into public.group_invites (group_id, token, created_by, expires_at)
values (:'gid', 'expired-token-0000000000', :'bea', now() - interval '1 hour');
set local role authenticated;
select pg_temp.act_as(:'dana');

select public.get_invite_preview('expired-token-0000000000') as expired_preview \gset
select pg_temp.assert(
  :'expired_preview'::jsonb ->> 'reason' = 'expired',
  'an expired link previews as expired'
);
select pg_temp.assert_raises(
  $$ select public.join_group('expired-token-0000000000') $$, 'HT004',
  'an expired link cannot be joined'
);

-- Use limits.
select pg_temp.act_as(:'bea');
select public.create_invite(:'gid'::uuid, null, 1) ->> 'token' as limited \gset

select pg_temp.act_as(:'dana');
select public.join_group(:'limited') as dana_gid \gset
select pg_temp.assert(:'dana_gid' = :'gid', 'the single use is honoured');

select pg_temp.act_as(:'mallory');
select pg_temp.assert_raises(
  format('select public.join_group(%L)', :'limited'), 'HT006',
  'the second use is refused'
);
select pg_temp.assert(
  (select count(*) from public.group_members
   where group_id = :'gid' and user_id = :'mallory') = 0,
  'the refused joiner is not a member'
);

-- ---------------------------------------------------------------------------
\echo 'leaving, blocked by money (spec §12.3):'
-- ---------------------------------------------------------------------------

set local role postgres;
insert into public.bills (id, group_id, title, total_amount, paid_by, created_by, split_mode)
values (:'billA', :'gid', 'Airbnb – 2 nights', 1250000, :'bea', :'bea', 'equal');
insert into public.bill_shares (bill_id, user_id, amount, status) values
  (:'billA', :'bea',   625000, 'settled'),
  (:'billA', :'carlo', 625000, 'unpaid');
set local role authenticated;

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises_mentioning(
  format('select public.leave_group(%L::uuid)', :'gid'),
  'HT007', 'Airbnb',
  'a debtor cannot leave, and the error names the bill'
);

select pg_temp.act_as(:'bea');
select pg_temp.assert_raises_mentioning(
  format('select public.leave_group(%L::uuid)', :'gid'),
  'HT007', 'Airbnb',
  'the payer cannot leave while others owe them'
);
select pg_temp.assert(
  (select count(*) from public.group_leave_blockers(:'gid'::uuid, :'bea')) = 1,
  'blockers are listed for the payer'
);
select pg_temp.assert(
  (select reason from public.group_leave_blockers(:'gid'::uuid, :'bea')) = 'owed_to_you',
  'the payer is blocked as owed_to_you'
);

set local role postgres;
update public.bill_shares set status = 'settled'
where bill_id = :'billA' and user_id = :'carlo';
set local role authenticated;

select pg_temp.act_as(:'bea');
select pg_temp.assert(
  (select count(*) from public.group_leave_blockers(:'gid'::uuid, :'bea')) = 0,
  'settling clears the blockers'
);

-- ---------------------------------------------------------------------------
\echo 'ownership and leaving:'
-- ---------------------------------------------------------------------------

select pg_temp.assert_raises(
  format('select public.leave_group(%L::uuid)', :'gid'), 'HT008',
  'the owner cannot leave while others remain'
);

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.set_member_role(%L::uuid, %L::uuid, %L)', :'gid', :'carlo', 'owner'),
  'HT002',
  'a member cannot make themselves the owner'
);

select pg_temp.act_as(:'bea');
select public.set_member_role(:'gid'::uuid, :'carlo'::uuid, 'owner');

select pg_temp.assert(
  (select role from public.group_members where group_id = :'gid' and user_id = :'carlo') = 'owner'
  and (select role from public.group_members where group_id = :'gid' and user_id = :'bea') = 'admin',
  'handing over ownership demotes the outgoing owner in the same step'
);

select public.leave_group(:'gid'::uuid);

-- Read as postgres: having left, Bea can no longer see the group's rows at
-- all — which is itself the RLS rule working.
set local role postgres;
select pg_temp.assert(
  (select left_at is not null from public.group_members
   where group_id = :'gid' and user_id = :'bea'),
  'leaving is a soft leave that keeps the row'
);
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'member_left') = 1,
  'emits member_left'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
\echo 'remove_member:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');
select pg_temp.assert_raises(
  format('select public.remove_member(%L::uuid, %L::uuid)', :'gid', :'carlo'),
  'HT010',
  'removing yourself points you at Leave group'
);

select public.set_member_role(:'gid'::uuid, :'dana'::uuid, 'admin');
select pg_temp.act_as(:'dana');
select pg_temp.assert_raises(
  format('select public.remove_member(%L::uuid, %L::uuid)', :'gid', :'carlo'),
  'HT009',
  'the owner cannot be removed'
);

select pg_temp.act_as(:'carlo');
select public.remove_member(:'gid'::uuid, :'dana'::uuid);
select pg_temp.assert(
  (select left_at is not null from public.group_members
   where group_id = :'gid' and user_id = :'dana'),
  'the owner can remove an admin'
);

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.activity_events
   where group_id = :'gid' and type = 'member_removed') = 1,
  'emits member_removed'
);
set local role authenticated;

-- Rejoining restores the original row rather than creating a second one.
select pg_temp.act_as(:'carlo');
select public.create_invite(:'gid'::uuid) ->> 'token' as token3 \gset

select pg_temp.act_as(:'dana');
select public.join_group(:'token3');
select pg_temp.assert(
  (select left_at is null from public.group_members
   where group_id = :'gid' and user_id = :'dana'),
  'rejoining clears left_at'
);

set local role postgres;
select pg_temp.assert(
  (select count(*) from public.group_members
   where group_id = :'gid' and user_id = :'dana') = 1,
  'rejoining does not duplicate the membership row'
);

reset role;

\echo ''
\echo 'All group tests passed.'

rollback;
