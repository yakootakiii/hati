-- Hati — recurring bills (spec §7.1, §12.6, §12.7).
--
-- The spec puts the generator in an Edge Function. It is implemented here in
-- PL/pgSQL instead (DECISIONS D-49): pg_cron already calls SQL directly, the
-- whole run is one transaction, and — the deciding reason — a SQL function can
-- be tested on this machine, while an Edge Function cannot. The idempotency
-- guarantee §14 asks for is worth having proof of rather than a promise.
--
--   HT060  that template no longer exists
--   HT061  not allowed to change this template
--   HT062  the recurrence does not make sense

-- Days in the month a date falls in.
create or replace function public.days_in_month(p_date date)
returns int
language sql
immutable
as $$
  select extract(
    day from (date_trunc('month', p_date::timestamp) + interval '1 month - 1 day')
  )::int;
$$;

-- The next run date after [p_from].
--
-- Monthly keeps to its anchor day, clamped to the end of a short month — so a
-- template anchored on the 31st lands on the 30th in April and the 28th in
-- February, then returns to the 31st (spec §12.7). Clamping the anchor rather
-- than carrying the previous date forward is what stops a 31st template from
-- walking backwards to the 28th and staying there.
create or replace function public.advance_run_date(
  p_from date,
  p_frequency text,
  p_interval int,
  p_anchor_day int default null
)
returns date
language plpgsql
immutable
as $$
declare
  v_every int := greatest(coalesce(p_interval, 1), 1);
  v_month_start date;
  v_anchor int;
begin
  if p_frequency = 'weekly' then
    return p_from + (7 * v_every);

  elsif p_frequency = 'monthly' then
    v_month_start := (
      date_trunc('month', p_from::timestamp) + make_interval(months => v_every)
    )::date;
    v_anchor := coalesce(p_anchor_day, extract(day from p_from)::int);
    return v_month_start
      + (least(v_anchor, public.days_in_month(v_month_start)) - 1);

  elsif p_frequency = 'yearly' then
    v_month_start := (
      date_trunc('month', p_from::timestamp) + make_interval(years => v_every)
    )::date;
    -- 29 February becomes 28 February in a common year.
    v_anchor := coalesce(p_anchor_day, extract(day from p_from)::int);
    return v_month_start
      + (least(v_anchor, public.days_in_month(v_month_start)) - 1);
  end if;

  raise exception 'Unknown frequency: %', p_frequency using errcode = 'HT062';
end;
$$;

-- ---------------------------------------------------------------------------
-- managing templates
-- ---------------------------------------------------------------------------

create or replace function public.create_recurring_bill(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_group_id uuid := (p_payload ->> 'group_id')::uuid;
  v_paid_by uuid := coalesce((p_payload ->> 'paid_by')::uuid, v_uid);
  v_title text := btrim(coalesce(p_payload ->> 'title', ''));
  v_mode text := p_payload ->> 'split_mode';
  v_frequency text := p_payload ->> 'frequency';
  v_next_run date := coalesce((p_payload ->> 'next_run_on')::date, current_date);
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if not public.is_group_member(v_group_id) then
    raise exception 'Not a member of that group' using errcode = 'HT001';
  end if;
  if v_title = '' then
    raise exception 'Give the bill a title' using errcode = 'HT010';
  end if;
  -- A template cannot carry line items (spec §5.1).
  if v_mode not in ('equal', 'exact', 'percent', 'shares') then
    raise exception 'A repeating bill cannot be itemized' using errcode = 'HT062';
  end if;
  if v_frequency not in ('weekly', 'monthly', 'yearly') then
    raise exception 'Pick weekly, monthly or yearly' using errcode = 'HT062';
  end if;
  if not exists (
    select 1 from group_members
    where group_id = v_group_id and user_id = v_paid_by and left_at is null
  ) then
    raise exception 'The payer is not in this group' using errcode = 'HT031';
  end if;

  -- Validate the split now rather than at 6am on the day it first runs.
  perform public.compute_split(
    jsonb_build_object(
      'total', (p_payload ->> 'total_amount')::bigint,
      'mode', v_mode,
      'participants', public.canonical_participants(
        v_group_id, p_payload -> 'participants'
      )
    )
  );

  insert into recurring_bills (
    group_id, created_by, title, category, notes, total_amount, paid_by,
    split_mode, split_config, frequency, "interval", anchor_day,
    next_run_on, ends_on
  )
  values (
    v_group_id, v_uid, v_title,
    nullif(btrim(coalesce(p_payload ->> 'category', '')), ''),
    nullif(btrim(coalesce(p_payload ->> 'notes', '')), ''),
    (p_payload ->> 'total_amount')::bigint,
    v_paid_by,
    v_mode,
    jsonb_build_object(
      'participants',
      public.canonical_participants(v_group_id, p_payload -> 'participants')
    ),
    v_frequency,
    greatest(coalesce((p_payload ->> 'interval')::int, 1), 1),
    case when v_frequency = 'monthly'
      then coalesce((p_payload ->> 'anchor_day')::int,
                    extract(day from v_next_run)::int)
      else nullif(p_payload ->> 'anchor_day', '')::int
    end,
    v_next_run,
    nullif(p_payload ->> 'ends_on', '')::date
  )
  returning id into v_id;

  insert into activity_events (group_id, actor_id, type, payload)
  values (
    v_group_id, v_uid, 'recurring_created',
    jsonb_build_object('bill_title', v_title, 'frequency', v_frequency)
  );

  return v_id;
end;
$$;

-- Only the creator or a group owner/admin may change a template (spec §5.4).
create or replace function public.assert_can_edit_template(p_template recurring_bills)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() = p_template.created_by then
    return;
  end if;
  if public.has_group_role(p_template.group_id, array['owner', 'admin']) then
    return;
  end if;
  raise exception 'Only whoever set this up, or a group admin, can change it'
    using errcode = 'HT061';
end;
$$;

-- Editing goes through an RPC rather than a direct update, so the split is
-- validated the same way it was at creation. RLS would allow the update, but
-- not check that the numbers still add up.
create or replace function public.update_recurring_bill(
  p_template_id uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_template recurring_bills%rowtype;
  v_paid_by uuid;
  v_title text := btrim(coalesce(p_payload ->> 'title', ''));
  v_mode text := coalesce(p_payload ->> 'split_mode', '');
  v_frequency text := coalesce(p_payload ->> 'frequency', '');
  v_participants jsonb;
begin
  select * into v_template from recurring_bills where id = p_template_id;
  if not found then
    raise exception 'That repeating bill no longer exists' using errcode = 'HT060';
  end if;
  perform public.assert_can_edit_template(v_template);

  if v_title = '' then
    raise exception 'Give the bill a title' using errcode = 'HT010';
  end if;
  if v_mode not in ('equal', 'exact', 'percent', 'shares') then
    raise exception 'A repeating bill cannot be itemized' using errcode = 'HT062';
  end if;
  if v_frequency not in ('weekly', 'monthly', 'yearly') then
    raise exception 'Pick weekly, monthly or yearly' using errcode = 'HT062';
  end if;

  v_paid_by := coalesce((p_payload ->> 'paid_by')::uuid, v_template.paid_by);
  if not exists (
    select 1 from group_members
    where group_id = v_template.group_id
      and user_id = v_paid_by
      and left_at is null
  ) then
    raise exception 'The payer is not in this group' using errcode = 'HT031';
  end if;

  v_participants := public.canonical_participants(
    v_template.group_id, p_payload -> 'participants'
  );

  perform public.compute_split(
    jsonb_build_object(
      'total', (p_payload ->> 'total_amount')::bigint,
      'mode', v_mode,
      'participants', v_participants
    )
  );

  update recurring_bills
  set title = v_title,
      category = nullif(btrim(coalesce(p_payload ->> 'category', '')), ''),
      notes = nullif(btrim(coalesce(p_payload ->> 'notes', '')), ''),
      total_amount = (p_payload ->> 'total_amount')::bigint,
      paid_by = v_paid_by,
      split_mode = v_mode,
      split_config = jsonb_build_object('participants', v_participants),
      frequency = v_frequency,
      "interval" = greatest(coalesce((p_payload ->> 'interval')::int, 1), 1),
      anchor_day = case when v_frequency = 'monthly'
        then coalesce((p_payload ->> 'anchor_day')::int, anchor_day)
        else null
      end,
      next_run_on = coalesce(
        (p_payload ->> 'next_run_on')::date, next_run_on
      ),
      ends_on = nullif(p_payload ->> 'ends_on', '')::date
  where id = p_template_id;
end;
$$;

create or replace function public.set_recurring_paused(
  p_template_id uuid,
  p_paused boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_template recurring_bills%rowtype;
begin
  select * into v_template from recurring_bills where id = p_template_id;
  if not found then
    raise exception 'That repeating bill no longer exists' using errcode = 'HT060';
  end if;
  perform public.assert_can_edit_template(v_template);

  update recurring_bills set paused = p_paused where id = p_template_id;
end;
$$;

-- Deleting a template leaves the bills it already generated alone (spec §10).
create or replace function public.delete_recurring_bill(p_template_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_template recurring_bills%rowtype;
begin
  select * into v_template from recurring_bills where id = p_template_id;
  if not found then
    return;  -- deleting twice is a no-op
  end if;
  perform public.assert_can_edit_template(v_template);

  delete from recurring_bills where id = p_template_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- the generator
-- ---------------------------------------------------------------------------

-- Pauses a template that can no longer run and tells the people who can fix it.
create or replace function public.pause_and_report(
  p_template recurring_bills,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update recurring_bills set paused = true where id = p_template.id;

  insert into notifications (user_id, type, title, body, data)
  select distinct recipient, 'recurring_paused',
    format('%s stopped repeating', p_template.title),
    p_reason,
    jsonb_build_object(
      'route', '/groups/' || p_template.group_id || '/recurring',
      'group_id', p_template.group_id,
      'event_type', 'recurring_paused'
    )
  from (
    select p_template.created_by as recipient
    union
    select m.user_id
    from group_members m
    where m.group_id = p_template.group_id
      and m.left_at is null
      and m.role in ('owner', 'admin')
  ) as people
  where recipient is not null;
end;
$$;

-- Generates whatever is due, and is safe to run more than once a day.
--
-- Idempotency comes from two places: a template is only picked up while
-- next_run_on is in the past, and that advances as soon as a bill is made; and
-- the unique index on bills(recurring_template_id, bill_date) refuses a second
-- bill for the same template and date, which covers a crash between the insert
-- and the advance (spec §7.1, §14).
create or replace function public.generate_recurring_bills(
  p_today date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_template recurring_bills%rowtype;
  v_participants jsonb;
  v_payer_gone boolean;
  v_bill_id uuid;
  v_run_on date;
  v_created int := 0;
  v_paused int := 0;
  v_skipped int := 0;
  v_guard int;
begin
  for v_template in
    select * from recurring_bills
    where not paused
      and next_run_on <= p_today
      and (ends_on is null or ends_on >= next_run_on)
    order by next_run_on
  loop
    -- Participants who have left the group are dropped (spec §12.6).
    select coalesce(jsonb_agg(e order by gm.joined_at, gm.user_id), '[]'::jsonb)
    into v_participants
    from jsonb_array_elements(
      coalesce(v_template.split_config -> 'participants', '[]'::jsonb)
    ) as e
    join group_members gm
      on gm.group_id = v_template.group_id
     and gm.user_id = (e ->> 'user_id')::uuid
     and gm.left_at is null;

    select not exists (
      select 1 from group_members
      where group_id = v_template.group_id
        and user_id = v_template.paid_by
        and left_at is null
    ) into v_payer_gone;

    if v_payer_gone then
      perform public.pause_and_report(
        v_template,
        'Whoever was paying has left the group. Pick someone else to restart it.'
      );
      v_paused := v_paused + 1;
      continue;
    end if;

    if jsonb_array_length(v_participants) = 0 then
      perform public.pause_and_report(
        v_template,
        'Nobody on it is still in the group. Add people to restart it.'
      );
      v_paused := v_paused + 1;
      continue;
    end if;

    -- Catch up on missed runs, bounded so a long outage cannot flood a group
    -- (DECISIONS D-50).
    v_guard := 0;
    v_run_on := v_template.next_run_on;

    while v_run_on <= p_today
      and (v_template.ends_on is null or v_run_on <= v_template.ends_on)
      and v_guard < 12
    loop
      v_guard := v_guard + 1;

      insert into bills (
        group_id, title, notes, category, total_amount, paid_by, created_by,
        split_mode, bill_date, recurring_template_id
      )
      values (
        v_template.group_id, v_template.title, v_template.notes,
        v_template.category, v_template.total_amount, v_template.paid_by,
        coalesce(v_template.created_by, v_template.paid_by),
        v_template.split_mode, v_run_on, v_template.id
      )
      -- bills_recurring_once_per_date is a partial index, so its predicate
      -- has to be repeated here for the arbiter to match.
      on conflict (recurring_template_id, bill_date)
        where recurring_template_id is not null
      do nothing
      returning id into v_bill_id;

      if v_bill_id is null then
        -- Already generated for this date: nothing to do but move on.
        v_skipped := v_skipped + 1;
      else
        perform public.apply_bill_split(
          v_bill_id,
          v_template.group_id,
          v_template.paid_by,
          jsonb_build_object(
            'total_amount', v_template.total_amount,
            'split_mode', v_template.split_mode,
            'participants', v_participants
          )
        );

        insert into activity_events (
          group_id, actor_id, type, bill_id, payload
        )
        values (
          v_template.group_id, v_template.created_by, 'recurring_generated',
          v_bill_id,
          jsonb_build_object(
            'bill_title', v_template.title,
            'total_amount', v_template.total_amount,
            'template_id', v_template.id
          )
        );

        v_created := v_created + 1;
      end if;

      v_run_on := public.advance_run_date(
        v_run_on, v_template.frequency, v_template."interval",
        v_template.anchor_day
      );
    end loop;

    update recurring_bills
    set next_run_on = v_run_on,
        paused = case
          when ends_on is not null and v_run_on > ends_on then true
          else paused
        end
    where id = v_template.id;
  end loop;

  return jsonb_build_object(
    'created', v_created,
    'paused', v_paused,
    'already_existed', v_skipped
  );
end;
$$;

-- One daily job, now doing both things (spec §7.1).
create or replace function public.run_daily_jobs()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reminders int;
  v_recurring jsonb;
begin
  -- Bills first: a bill generated today should not also be reminded about
  -- today, and send_reminders only looks at shares three days old anyway.
  v_recurring := public.generate_recurring_bills();
  v_reminders := public.send_reminders();

  return jsonb_build_object(
    'recurring', v_recurring,
    'reminders_sent', v_reminders,
    'ran_at', now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- grants
-- ---------------------------------------------------------------------------

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.generate_recurring_bills(date)',
    'public.pause_and_report(recurring_bills, text)',
    'public.assert_can_edit_template(recurring_bills)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
  end loop;

  foreach fn in array array[
    'public.create_recurring_bill(jsonb)',
    'public.update_recurring_bill(uuid, jsonb)',
    'public.set_recurring_paused(uuid, boolean)',
    'public.delete_recurring_bill(uuid)',
    'public.advance_run_date(date, text, int, int)',
    'public.days_in_month(date)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;
