-- Shared scaffolding for the SQL test suites. Loaded with \i from each test.
--
-- Everything lives in pg_temp, so it disappears with the session and can never
-- be mistaken for application code.

create or replace function pg_temp.assert(ok boolean, label text)
returns void
language plpgsql
as $$
begin
  if ok then
    raise notice '  ok   %', label;
  else
    raise exception 'FAILED: %', label;
  end if;
end;
$$;

-- Impersonates a user the way PostgREST does: the `authenticated` role plus
-- the JWT claims auth.uid() reads.
create or replace function pg_temp.act_as(user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

-- Runs a statement and asserts it failed with a specific SQLSTATE.
--
-- Matching the exact code matters: `when others` would let an unrelated error —
-- a typo'd column, a missing function — read as the refusal under test.
create or replace function pg_temp.assert_raises(
  stmt text,
  expected_sqlstate text,
  label text
)
returns void
language plpgsql
as $$
declare
  state text;
begin
  begin
    execute stmt;
    state := 'NO ERROR';
  exception when others then
    state := sqlstate;
  end;
  perform pg_temp.assert(
    state = expected_sqlstate,
    label || ' [' || state || ' wanted ' || expected_sqlstate || ']'
  );
end;
$$;

-- Same, but also checks the message mentions something — used where the spec
-- requires the error to name what is blocking (§12.3).
create or replace function pg_temp.assert_raises_mentioning(
  stmt text,
  expected_sqlstate text,
  needle text,
  label text
)
returns void
language plpgsql
as $$
declare
  state text;
  msg text := '';
begin
  begin
    execute stmt;
    state := 'NO ERROR';
  exception when others then
    state := sqlstate;
    msg := sqlerrm;
  end;
  perform pg_temp.assert(
    state = expected_sqlstate and msg like '%' || needle || '%',
    label || ' [' || state || ': ' || msg || ']'
  );
end;
$$;

create or replace function pg_temp.make_user(
  user_id uuid,
  display_name text,
  email text
)
returns void
language plpgsql
as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data)
  values (
    '00000000-0000-0000-0000-000000000000',
    user_id, 'authenticated', 'authenticated', email,
    jsonb_build_object('display_name', display_name)
  );
end;
$$;
