-- Hati — the split engine in SQL, driven by the shared vectors (spec §6, §14).
--
-- Reads the very same supabase/tests/split_vectors.json that
-- test/core/split/split_engine_test.dart reads. Two implementations only stay
-- in step if they are asked identical questions, so the file is loaded rather
-- than transcribed.
--
--   tool/run_sql_tests_local.sh   (or tool/run_rls_tests.sh against a project)

\set ON_ERROR_STOP on

begin;

\i supabase/tests/_helpers.sql

-- psql substitutes the command output, so the vectors arrive as one literal.
\set vectors `cat supabase/tests/split_vectors.json`
-- The differential corpus: every `expect` in it was produced by the Dart
-- engine (tool/gen_fuzz_vectors.dart). Requiring SQL to reproduce all of it is
-- what makes "Dart and SQL results match exactly" (§14) more than a claim.
\set fuzz `cat supabase/tests/split_vectors_fuzz.json`

create temporary table split_vectors as
select
  (c ->> 'name') as name,
  (c -> 'input') as input,
  (c -> 'expect') as expect,
  (c ->> 'error') as expected_error
from jsonb_array_elements((:'vectors')::jsonb -> 'cases') as t(c)
union all
select
  (c ->> 'name'),
  (c -> 'input'),
  (c -> 'expect'),
  null
from jsonb_array_elements((:'fuzz')::jsonb -> 'cases') as t(c);

-- A suite that loaded nothing would pass every assertion below.
select pg_temp.assert(
  (select count(*) from split_vectors) >= 200,
  format('loaded %s vectors', (select count(*) from split_vectors))
);
select pg_temp.assert(
  (select count(*) from split_vectors where name like 'fuzz/%') >= 200,
  'the differential corpus is loaded'
);
select pg_temp.assert(
  (select count(distinct input ->> 'mode') from split_vectors) = 5,
  'all five split modes are exercised'
);
select pg_temp.assert(
  (select count(*) from split_vectors where expected_error is not null) >= 10,
  'the vectors include rejection cases'
);

\echo ''
\echo 'vectors that must compute:'

do $$
declare
  v record;
  actual jsonb;
  total bigint;
  summed bigint;
  checked int := 0;
begin
  for v in select * from split_vectors where expect is not null order by name loop
    actual := public.compute_split(v.input);

    if actual <> v.expect then
      raise exception 'FAILED: % → % (wanted %)', v.name, actual, v.expect;
    end if;

    -- The §6.1 invariant, checked independently of the expected map.
    total := (v.input ->> 'total')::bigint;
    select sum(value::bigint) into summed
    from jsonb_each_text(actual);

    if summed <> total then
      raise exception 'FAILED: % shares summed to % not %', v.name, summed, total;
    end if;

    checked := checked + 1;
  end loop;

  perform pg_temp.assert(
    checked = (select count(*) from split_vectors where expect is not null),
    format('%s vectors computed, every one matching Dart to the centavo', checked)
  );
end;
$$;

\echo ''
\echo 'vectors that must be refused:'

do $$
declare
  v record;
  raised text;
begin
  for v in select * from split_vectors where expected_error is not null order by name loop
    begin
      perform public.compute_split(v.input);
      raised := '-no error-';
    exception when others then
      raised := sqlerrm;
    end;

    perform pg_temp.assert(
      raised = v.expected_error,
      format('%s → %s', v.name, raised)
    );
  end loop;
end;
$$;

\echo ''
\echo 'the remainder rule directly (spec §6.2):'

select pg_temp.assert(
  public.split_distribute(7, array[1, 1, 2]::bigint[]) = array[2, 2, 3]::bigint[],
  'leftovers go to the largest remainders first'
);
select pg_temp.assert(
  public.split_distribute(10000, array[1, 1, 1]::bigint[]) = array[3334, 3333, 3333]::bigint[],
  'ties break by participant order'
);
select pg_temp.assert(
  public.split_distribute(1, array[1, 1, 1]::bigint[]) = array[1, 0, 0]::bigint[],
  'one centavo lands on the first participant'
);

do $$
declare
  n int;
  t bigint;
  amounts bigint[];
  summed bigint;
  i int;
begin
  foreach t in array array[1::bigint, 7, 100, 9999, 1250000, 1000000000] loop
    for n in 1..50 loop
      amounts := public.split_distribute(t, array_fill(1::bigint, array[n]));
      summed := 0;
      for i in 1..n loop
        summed := summed + amounts[i];
      end loop;
      if summed <> t then
        raise exception 'FAILED: % split % ways summed to %', t, n, summed;
      end if;
    end loop;
  end loop;
  perform pg_temp.assert(true, 'every total splits exactly, 1 to 50 ways');
end;
$$;

\echo ''
\echo 'All split tests passed.'

rollback;
