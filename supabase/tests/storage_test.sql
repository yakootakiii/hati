-- Hati — storage RLS (spec §5.2, §14).
--
-- "A user who is not a group member cannot read any of that group's rows or
-- storage objects." Reads here stand in for signed-URL requests: Supabase
-- checks SELECT on storage.objects before it will sign a URL, so a denied
-- select is a denied signed URL.
--
-- Paths carry the id that scopes them, and they are user-supplied, so the
-- malformed-path cases below matter as much as the happy ones.
--
--   tool/run_sql_tests_local.sh

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\set bea     '11111111-1111-1111-1111-111111111111'
\set carlo   '22222222-2222-2222-2222-222222222222'
\set dana    '33333333-3333-3333-3333-333333333333'
\set mallory '44444444-4444-4444-4444-444444444444'

select pg_temp.make_user(:'bea',     'Bea',     'bea@example.test');
select pg_temp.make_user(:'carlo',   'Carlo',   'carlo@example.test');
select pg_temp.make_user(:'dana',    'Dana',    'dana@example.test');
select pg_temp.make_user(:'mallory', 'Mallory', 'mallory@example.test');

set local role authenticated;
select pg_temp.act_as(:'bea');
select public.create_group('Tagaytay Staycation') as gid \gset
select public.create_invite(:'gid'::uuid) ->> 'token' as tok \gset
select pg_temp.act_as(:'carlo'); select public.join_group(:'tok');
select pg_temp.act_as(:'dana');  select public.join_group(:'tok');

select pg_temp.act_as(:'bea');
select public.create_bill(jsonb_build_object(
  'group_id', :'gid', 'title', 'Airbnb', 'total_amount', 300000,
  'paid_by', :'bea', 'split_mode', 'equal',
  'participants', jsonb_build_array(
    jsonb_build_object('user_id', :'bea'),
    jsonb_build_object('user_id', :'carlo'))
)) as bill \gset

-- Objects in every bucket, laid out the way the app writes them.
set local role postgres;
insert into storage.objects (bucket_id, name, owner) values
  ('avatars',        :'bea' || '/me.jpg',                        :'bea'),
  ('payment-qr',     :'bea' || '/gcash.jpg',                     :'bea'),
  ('group-photos',   :'gid' || '/cover.jpg',                     :'bea'),
  ('bill-receipts',  :'gid' || '/' || :'bill' || '/booking.jpg', :'bea'),
  ('payment-proofs', :'gid' || '/carlo-proof.jpg',               :'carlo'),
  -- Paths that do not parse as a uuid must not become a way in.
  ('bill-receipts',  'not-a-uuid/receipt.jpg',                   :'mallory'),
  ('payment-proofs', '../escape.jpg',                            :'mallory');
set local role authenticated;

-- ---------------------------------------------------------------------------
\echo 'a group member reads what they should:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');

select pg_temp.assert(
  (select count(*) from storage.objects
   where bucket_id = 'avatars' and name = :'bea' || '/me.jpg') = 1,
  'a groupmate''s avatar'
);
select pg_temp.assert(
  (select count(*) from storage.objects
   where bucket_id = 'payment-qr' and name = :'bea' || '/gcash.jpg') = 1,
  'a groupmate''s payment QR'
);
select pg_temp.assert(
  (select count(*) from storage.objects
   where bucket_id = 'group-photos') = 1,
  'the group photo'
);
select pg_temp.assert(
  (select count(*) from storage.objects
   where bucket_id = 'bill-receipts' and owner = :'bea') = 1,
  'a bill receipt'
);
select pg_temp.assert(
  (select count(*) from storage.objects
   where bucket_id = 'payment-proofs' and owner = :'carlo') = 1,
  'a payment proof'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'an outsider reads nothing (spec §14):'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'mallory');

select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'avatars') = 0,
  'not a stranger''s avatar'
);
select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'payment-qr') = 0,
  'not a stranger''s payment QR'
);
select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'group-photos') = 0,
  'not the group photo'
);
select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'bill-receipts') = 0,
  'not a bill receipt — including the one they uploaded to a bogus path'
);
select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'payment-proofs') = 0,
  'not a payment proof'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'paths that do not parse are readable by nobody:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'bea');
select pg_temp.assert(
  (select count(*) from storage.objects
   where name in ('not-a-uuid/receipt.jpg', '../escape.jpg')) = 0,
  'a malformed prefix grants no access, even to a member'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'writes are scoped too:'
-- ---------------------------------------------------------------------------

select pg_temp.act_as(:'carlo');

select pg_temp.assert_raises(
  format(
    'insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
    'avatars', :'bea' || '/hijack.jpg', :'carlo'
  ),
  '42501', 'nobody can write into someone else''s avatar folder'
);
select pg_temp.assert_raises(
  format(
    'insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
    'payment-qr', :'bea' || '/fake-qr.jpg', :'carlo'
  ),
  '42501', 'nor into their payment QR folder'
);
select pg_temp.assert_raises(
  format(
    'insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
    'group-photos', :'gid' || '/rude.jpg', :'carlo'
  ),
  '42501', 'a plain member cannot change the group photo'
);

do $$
declare
  ok boolean := false;
begin
  -- A member may upload a receipt to their own group.
  begin
    insert into storage.objects (bucket_id, name, owner)
    values (
      'bill-receipts',
      (select group_id from public.bills limit 1)::text || '/x/mine.jpg',
      auth.uid()
    );
    ok := true;
  exception when others then
    ok := false;
  end;
  perform pg_temp.assert(ok, 'a member can upload a receipt to their group');
end;
$$;

select pg_temp.act_as(:'mallory');
select pg_temp.assert_raises(
  format(
    'insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
    'bill-receipts', :'gid' || '/x/theirs.jpg', :'mallory'
  ),
  '42501', 'an outsider cannot upload into a group they are not in'
);
select pg_temp.assert_raises(
  format(
    'insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
    'payment-proofs', :'gid' || '/theirs.jpg', :'mallory'
  ),
  '42501', 'nor a payment proof'
);

-- ---------------------------------------------------------------------------
\echo ''
\echo 'leaving takes the images away (spec §5.2):'
-- ---------------------------------------------------------------------------

set local role postgres;
update public.group_members set left_at = now()
where group_id = :'gid' and user_id = :'dana';
set local role authenticated;

select pg_temp.act_as(:'dana');
select pg_temp.assert(
  (select count(*) from storage.objects where bucket_id = 'bill-receipts') = 0,
  'a former member loses the receipts, though they keep their bill rows'
);

reset role;

\echo ''
\echo 'All storage tests passed.'

rollback;
