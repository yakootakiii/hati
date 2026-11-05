-- Hati — push device registration (DECISIONS D-65).
--
--   tool/run_sql_tests_local.sh

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\set bea   '11111111-1111-1111-1111-111111111111'
\set carlo '22222222-2222-2222-2222-222222222222'

select pg_temp.make_user(:'bea',   'Bea',   'bea@example.test');
select pg_temp.make_user(:'carlo', 'Carlo', 'carlo@example.test');

set local role authenticated;

\echo 'register_device_token:'

select pg_temp.act_as(:'bea');
select public.register_device_token('phone-1', 'android');
select public.register_device_token('phone-1', 'android');
select pg_temp.assert(
  (select count(*) from public.device_tokens where token = 'phone-1') = 1,
  'registering twice keeps one row'
);

-- Carlo signs in on Bea's phone.
select pg_temp.act_as(:'carlo');
select public.register_device_token('phone-1', 'android');
reset role;
select pg_temp.assert(
  (select user_id from public.device_tokens where token = 'phone-1') = :'carlo'::uuid,
  'the phone moves to whoever is signed in, so Bea''s pushes stop going there'
);
set local role authenticated;

\echo ''
\echo 'unregister_device_token:'

select pg_temp.act_as(:'bea');
select public.unregister_device_token('phone-1');
reset role;
select pg_temp.assert(
  (select count(*) from public.device_tokens where token = 'phone-1') = 1,
  'someone else cannot release a phone that is not theirs'
);
set local role authenticated;

select pg_temp.act_as(:'carlo');
select public.unregister_device_token('phone-1');
reset role;
select pg_temp.assert(
  (select count(*) from public.device_tokens where token = 'phone-1') = 0,
  'signing out releases it'
);

\echo ''
\echo 'All push device tests passed.'

rollback;
