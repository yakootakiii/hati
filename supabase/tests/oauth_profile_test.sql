-- Hati — profile names for sign-ups that did not come from the email form
-- (DECISIONS D-60).
--
--   tool/run_sql_tests_local.sh

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

\echo 'handle_new_user picks a name:'

insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'a1111111-1111-1111-1111-111111111111',
   'authenticated', 'authenticated', 'bea@example.test',
   '{"display_name": "Bea", "full_name": "Beatriz Reyes"}'),
  ('00000000-0000-0000-0000-000000000000', 'a2222222-2222-2222-2222-222222222222',
   'authenticated', 'authenticated', 'carlo.cruz@gmail.test',
   '{"full_name": "Carlo Cruz", "name": "Carlo C.", "avatar_url": "https://x"}'),
  ('00000000-0000-0000-0000-000000000000', 'a3333333-3333-3333-3333-333333333333',
   'authenticated', 'authenticated', 'dana@gmail.test',
   '{"name": "Dana"}'),
  ('00000000-0000-0000-0000-000000000000', 'a4444444-4444-4444-4444-444444444444',
   'authenticated', 'authenticated', 'eli.santos@gmail.test',
   '{"full_name": "   "}');

select pg_temp.assert(
  (select display_name from public.profiles
   where id = 'a1111111-1111-1111-1111-111111111111') = 'Bea',
  'the sign-up form''s display_name still wins'
);
select pg_temp.assert(
  (select display_name from public.profiles
   where id = 'a2222222-2222-2222-2222-222222222222') = 'Carlo Cruz',
  'a Google sign-up is named from full_name'
);
select pg_temp.assert(
  (select display_name from public.profiles
   where id = 'a3333333-3333-3333-3333-333333333333') = 'Dana',
  'then from name'
);
select pg_temp.assert(
  (select display_name from public.profiles
   where id = 'a4444444-4444-4444-4444-444444444444') = 'eli.santos',
  'a blank name falls back to the email''s local part'
);

\echo ''
\echo 'All OAuth profile tests passed.'

rollback;
