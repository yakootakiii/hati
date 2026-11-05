-- Hati — table privileges (the gate that sits in front of RLS).
--
-- RLS decides which rows a caller sees; privileges decide whether they may
-- touch the table at all. A policy that allows everything is still refused
-- when the privilege was never granted — which is exactly what happened on the
-- first push to a real project (DECISIONS D-27).
--
-- This suite pins the grant matrix to the policy set. A table added in a later
-- milestone without matching grants fails here rather than in production.

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

create or replace function pg_temp.dml_privs(role_name text, tbl text)
returns text
language sql
stable
as $$
  select coalesce(string_agg(v.p, ',' order by v.ord), '-none-')
  from (values ('SELECT', 1), ('INSERT', 2), ('UPDATE', 3), ('DELETE', 4))
       as v(p, ord)
  where has_table_privilege(role_name, ('public.' || tbl)::regclass, v.p);
$$;

-- The expected privileges for `authenticated`, mirroring …0002_rls.sql.
create temporary table expected_grants (tbl text primary key, privs text);
insert into expected_grants values
  -- written directly by their owner
  ('profiles',            'SELECT,UPDATE'),
  ('payment_methods',     'SELECT,INSERT,UPDATE,DELETE'),
  ('device_tokens',       'SELECT,INSERT,UPDATE,DELETE'),
  ('notification_prefs',  'SELECT,INSERT,UPDATE,DELETE'),
  -- written by members of the group
  ('groups',              'SELECT,UPDATE'),
  ('group_invites',       'SELECT,INSERT,UPDATE,DELETE'),
  ('bill_attachments',    'SELECT,INSERT,DELETE'),
  ('comments',            'SELECT,INSERT,UPDATE,DELETE'),
  ('recurring_bills',     'SELECT,INSERT,UPDATE,DELETE'),
  -- read-only to clients: these change through RPCs and triggers only
  ('group_members',       'SELECT'),
  ('group_direct_invites', 'SELECT'),
  ('bills',               'SELECT'),
  ('bill_shares',         'SELECT'),
  ('bill_items',          'SELECT'),
  ('bill_item_assignees', 'SELECT'),
  ('payments',            'SELECT'),
  ('activity_events',     'SELECT'),
  -- read_at is granted at column level, so no table-level UPDATE here
  ('notifications',       'SELECT');

\echo 'authenticated grants match the policy set:'

do $$
declare
  row record;
  actual text;
begin
  for row in select * from expected_grants order by tbl loop
    actual := pg_temp.dml_privs('authenticated', row.tbl);
    perform pg_temp.assert(
      actual = row.privs,
      format('%s: %s', row.tbl, actual)
    );
  end loop;
end;
$$;

\echo ''
\echo 'no table is missing from the matrix:'

do $$
declare
  missing text;
begin
  select string_agg(tablename, ', ')
  into missing
  from pg_tables
  where schemaname = 'public'
    and tablename not in (select tbl from expected_grants);

  perform pg_temp.assert(
    missing is null,
    coalesce('untracked tables: ' || missing, 'every public table is covered')
  );
end;
$$;

\echo ''
\echo 'row level security and anon:'

do $$
declare
  unprotected text;
begin
  select string_agg(c.relname, ', ')
  into unprotected
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

  perform pg_temp.assert(
    unprotected is null,
    coalesce('RLS missing on: ' || unprotected, 'RLS is on for every table')
  );
end;
$$;

do $$
declare
  leaky text;
begin
  select string_agg(tbl, ', ')
  into leaky
  from expected_grants
  where pg_temp.dml_privs('anon', tbl) <> '-none-';

  perform pg_temp.assert(
    leaky is null,
    coalesce('anon can reach: ' || leaky, 'anon has no access to any table')
  );
end;
$$;

\echo ''
\echo 'notifications: read_at only'

select pg_temp.assert(
  has_column_privilege('authenticated', 'public.notifications', 'read_at', 'UPDATE'),
  'authenticated may mark a notification read'
);
select pg_temp.assert(
  not has_column_privilege('authenticated', 'public.notifications', 'title', 'UPDATE'),
  'authenticated may not rewrite a notification'
);

\echo ''
\echo 'RPC execution:'

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.create_group(text, text)',
    'public.create_invite(uuid, int, int, boolean)',
    'public.get_invite_preview(text)',
    'public.join_group(text)',
    'public.leave_group(uuid)',
    'public.remove_member(uuid, uuid)',
    'public.set_member_role(uuid, uuid, text)',
    'public.get_my_groups()',
    'public.compute_split(jsonb)',
    'public.split_distribute(bigint, bigint[])'
  ]
  loop
    perform pg_temp.assert(
      has_function_privilege('authenticated', fn, 'EXECUTE'),
      format('authenticated may call %s', split_part(fn, '(', 1))
    );
    perform pg_temp.assert(
      not has_function_privilege('anon', fn, 'EXECUTE'),
      format('anon may not call %s', split_part(fn, '(', 1))
    );
  end loop;
end;
$$;

\echo ''
\echo ''
\echo 'service_role, for send-push (D-65):'

select pg_temp.assert(
  has_table_privilege('service_role', 'public.notifications', 'select'),
  'send-push can read the notification it delivers'
);
select pg_temp.assert(
  has_column_privilege('service_role', 'public.notifications', 'pushed_at', 'update'),
  'and stamp it as pushed'
);
select pg_temp.assert(
  not has_column_privilege('service_role', 'public.notifications', 'title', 'update'),
  'but cannot rewrite what it says'
);
select pg_temp.assert(
  has_table_privilege('service_role', 'public.device_tokens', 'select')
    and has_table_privilege('service_role', 'public.device_tokens', 'delete'),
  'can read devices and drop dead tokens'
);

\echo 'All grant tests passed.'

rollback;
