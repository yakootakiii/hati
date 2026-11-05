-- Hati — the split engine in PL/pgSQL (spec §6).
--
-- The twin of lib/core/split/split_engine.dart. The client computes a live
-- preview; this is what actually decides what anyone owes, because §4.1 makes
-- the server the source of truth for split validity.
--
-- Both are driven by supabase/tests/split_vectors.json. Keeping two
-- implementations honest is only possible if they answer the same questions,
-- so every change to one belongs in the same commit as the other.
--
-- Failures raise a slug as the message and a specific SQLSTATE:
--
--   HT020  no_participants          HT025  non_positive_weight
--   HT021  duplicate_participant    HT026  item_without_assignees
--   HT022  invalid_total            HT027  unknown_assignee
--   HT023  exact_sum_mismatch       HT028  items_total_mismatch
--   HT024  percent_sum_mismatch     HT029  negative_share

create or replace function public.split_fail(p_slug text)
returns void
language plpgsql
immutable
as $$
begin
  raise exception '%', p_slug
    using errcode = case p_slug
      when 'no_participants'        then 'HT020'
      when 'duplicate_participant'  then 'HT021'
      when 'invalid_total'          then 'HT022'
      when 'exact_sum_mismatch'     then 'HT023'
      when 'percent_sum_mismatch'   then 'HT024'
      when 'non_positive_weight'    then 'HT025'
      when 'item_without_assignees' then 'HT026'
      when 'unknown_assignee'       then 'HT027'
      when 'items_total_mismatch'   then 'HT028'
      when 'negative_share'         then 'HT029'
      else 'HT010'
    end;
end;
$$;

-- The remainder rule (spec §6.2).
--
-- Floor each share, then hand the leftover centavos out one each by largest
-- remainder, ties broken by position. All integer arithmetic: the numerator is
-- kept whole and the modulus carries the fraction, so nothing is approximated
-- and the result matches the Dart engine bit for bit.
create or replace function public.split_distribute(
  p_total bigint,
  p_weights bigint[]
)
returns bigint[]
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  n int := coalesce(array_length(p_weights, 1), 0);
  weight_sum bigint := 0;
  amounts bigint[] := array_fill(0::bigint, array[greatest(n, 1)]);
  remainders bigint[] := array_fill(0::bigint, array[greatest(n, 1)]);
  order_idx int[];
  numerator bigint;
  leftover bigint;
  i int;
begin
  if n = 0 then
    perform public.split_fail('no_participants');
  end if;

  for i in 1..n loop
    weight_sum := weight_sum + p_weights[i];
  end loop;

  if weight_sum <= 0 then
    perform public.split_fail('non_positive_weight');
  end if;

  for i in 1..n loop
    numerator := p_total * p_weights[i];
    amounts[i] := numerator / weight_sum;
    remainders[i] := numerator % weight_sum;
  end loop;

  leftover := p_total;
  for i in 1..n loop
    leftover := leftover - amounts[i];
  end loop;

  select array_agg(g.i order by remainders[g.i] desc, g.i asc)
  into order_idx
  from generate_series(1, n) as g(i);

  for i in 1..leftover loop
    amounts[order_idx[i]] := amounts[order_idx[i]] + 1;
  end loop;

  return amounts[1:n];
end;
$$;

-- Spreads one extra across participants in proportion to their item subtotals.
-- With no subtotals to go on — every item was free — proportion is meaningless,
-- so it is shared equally (DECISIONS D-28).
create or replace function public.split_spread(
  p_amount bigint,
  p_subtotals bigint[]
)
returns bigint[]
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  n int := coalesce(array_length(p_subtotals, 1), 0);
  total bigint := 0;
  i int;
begin
  for i in 1..n loop
    total := total + p_subtotals[i];
  end loop;

  if total > 0 then
    return public.split_distribute(p_amount, p_subtotals);
  end if;
  return public.split_distribute(p_amount, array_fill(1::bigint, array[n]));
end;
$$;

create or replace function public.split_itemized(
  p_total bigint,
  p_ids text[],
  p_items jsonb,
  p_extras jsonb
)
returns bigint[]
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  n int := coalesce(array_length(p_ids, 1), 0);
  subtotals bigint[] := array_fill(0::bigint, array[n]);
  amounts bigint[];
  portions bigint[];
  item jsonb;
  assignees text[];
  positions int[];
  assignee text;
  pos int;
  k int;
  subtotal bigint := 0;
  service_charge bigint := coalesce((p_extras ->> 'service_charge')::bigint, 0);
  tax bigint := coalesce((p_extras ->> 'tax')::bigint, 0);
  discount bigint := coalesce((p_extras ->> 'discount')::bigint, 0);
  expected bigint;
begin
  -- Each item is split equally among its assignees, remainder rule applied per
  -- item, so no fraction is ever carried between lines.
  for item in
    select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    select array_agg(t.a #>> '{}' order by t.ord)
    into assignees
    from jsonb_array_elements(coalesce(item -> 'assignees', '[]'::jsonb))
         with ordinality as t(a, ord);

    if assignees is null or cardinality(assignees) = 0 then
      perform public.split_fail('item_without_assignees');
    end if;

    positions := '{}';
    foreach assignee in array assignees loop
      pos := array_position(p_ids, assignee);
      if pos is null then
        perform public.split_fail('unknown_assignee');
      end if;
      positions := positions || pos;
    end loop;

    portions := public.split_distribute(
      (item ->> 'amount')::bigint,
      array_fill(1::bigint, array[cardinality(positions)])
    );

    for k in 1..cardinality(positions) loop
      subtotals[positions[k]] := subtotals[positions[k]] + portions[k];
    end loop;
  end loop;

  for k in 1..n loop
    subtotal := subtotal + subtotals[k];
  end loop;

  expected := subtotal + service_charge + tax - discount;
  if expected <> p_total then
    perform public.split_fail('items_total_mismatch');
  end if;

  amounts := subtotals;

  -- Service charge, then tax, then discount — a fixed order, because it
  -- decides who receives a leftover centavo (DECISIONS D-05).
  if service_charge <> 0 then
    portions := public.split_spread(service_charge, subtotals);
    for k in 1..n loop
      amounts[k] := amounts[k] + portions[k];
    end loop;
  end if;

  if tax <> 0 then
    portions := public.split_spread(tax, subtotals);
    for k in 1..n loop
      amounts[k] := amounts[k] + portions[k];
    end loop;
  end if;

  if discount <> 0 then
    portions := public.split_spread(discount, subtotals);
    for k in 1..n loop
      amounts[k] := amounts[k] - portions[k];
    end loop;
  end if;

  return amounts;
end;
$$;

-- The entry point. Takes the same payload shape the Dart engine parses and
-- returns {user_id: centavos}.
create or replace function public.compute_split(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_total bigint := (p_payload ->> 'total')::bigint;
  v_mode text := p_payload ->> 'mode';
  v_ids text[];
  v_inputs bigint[];
  n int;
  amounts bigint[];
  weights bigint[];
  input_sum bigint := 0;
  i int;
begin
  select array_agg(t.p ->> 'user_id' order by t.ord),
         array_agg((t.p ->> 'input')::bigint order by t.ord)
  into v_ids, v_inputs
  from jsonb_array_elements(coalesce(p_payload -> 'participants', '[]'::jsonb))
       with ordinality as t(p, ord);

  n := coalesce(array_length(v_ids, 1), 0);

  if n = 0 then
    perform public.split_fail('no_participants');
  end if;
  if (select count(distinct x) from unnest(v_ids) as x) <> n then
    perform public.split_fail('duplicate_participant');
  end if;
  if v_total <= 0 or v_total > public.max_bill_centavos() then
    perform public.split_fail('invalid_total');
  end if;

  if v_mode = 'equal' then
    amounts := public.split_distribute(v_total, array_fill(1::bigint, array[n]));

  elsif v_mode = 'exact' then
    weights := '{}';
    for i in 1..n loop
      weights[i] := coalesce(v_inputs[i], 0);
      input_sum := input_sum + weights[i];
    end loop;
    if input_sum <> v_total then
      perform public.split_fail('exact_sum_mismatch');
    end if;
    amounts := weights;

  elsif v_mode = 'percent' then
    weights := '{}';
    for i in 1..n loop
      weights[i] := coalesce(v_inputs[i], 0);
      if weights[i] < 0 then
        perform public.split_fail('non_positive_weight');
      end if;
      input_sum := input_sum + weights[i];
    end loop;
    -- Percentages arrive as hundredths, so 100.00% is exactly 10000 and the
    -- check needs no tolerance.
    if input_sum <> 10000 then
      perform public.split_fail('percent_sum_mismatch');
    end if;
    amounts := public.split_distribute(v_total, weights);

  elsif v_mode = 'shares' then
    weights := '{}';
    for i in 1..n loop
      weights[i] := coalesce(v_inputs[i], 0);
      if weights[i] <= 0 then
        perform public.split_fail('non_positive_weight');
      end if;
    end loop;
    amounts := public.split_distribute(v_total, weights);

  elsif v_mode = 'itemized' then
    amounts := public.split_itemized(
      v_total,
      v_ids,
      p_payload -> 'items',
      coalesce(p_payload -> 'extras', '{}'::jsonb)
    );

  else
    perform public.split_fail('invalid_total');
  end if;

  for i in 1..n loop
    if amounts[i] < 0 then
      perform public.split_fail('negative_share');
    end if;
  end loop;

  return (
    select jsonb_object_agg(v_ids[g.i], amounts[g.i])
    from generate_series(1, n) as g(i)
  );
end;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.split_fail(text)',
    'public.split_distribute(bigint, bigint[])',
    'public.split_spread(bigint, bigint[])',
    'public.split_itemized(bigint, text[], jsonb, jsonb)',
    'public.compute_split(jsonb)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;
