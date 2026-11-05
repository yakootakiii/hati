-- Hati — bill creation, editing, voiding and balances (spec §7).
--
-- Bills and shares are not client-writable, so everything here is the only way
-- they change. Each function re-runs the split through compute_split rather
-- than trusting the amounts the client sends: §4.1 makes the server the source
-- of truth for split validity, and the client's numbers are only a preview.
--
--   HT030  bill not found
--   HT031  the payer is not a member of the group
--   HT032  a participant is not a member of the group
--   HT033  the bill is locked — a payment is pending or confirmed
--   HT034  the bill has a confirmed payment
--   HT035  not allowed to edit or void this bill
--   HT036  the bill is void
--
-- Split failures surface as HT020–HT029 from compute_split, untouched.

-- Participant order decides who receives a leftover centavo (spec §6.2), so it
-- cannot be left to however the client happened to send the list. The
-- canonical order is `group_members.joined_at`, then `user_id` (spec §6.1),
-- and this is the one place it is established (DECISIONS D-31).
create or replace function public.canonical_participants(
  p_group_id uuid,
  p_participants jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_ordered jsonb;
  v_unknown text;
begin
  select string_agg(e ->> 'user_id', ', ')
  into v_unknown
  from jsonb_array_elements(coalesce(p_participants, '[]'::jsonb)) as e
  where not exists (
    select 1 from group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = (e ->> 'user_id')::uuid
      and gm.left_at is null
  );

  if v_unknown is not null then
    raise exception 'not in this group: %', v_unknown using errcode = 'HT032';
  end if;

  select coalesce(jsonb_agg(e order by gm.joined_at, gm.user_id), '[]'::jsonb)
  into v_ordered
  from jsonb_array_elements(coalesce(p_participants, '[]'::jsonb)) as e
  join group_members gm
    on gm.group_id = p_group_id
   and gm.user_id = (e ->> 'user_id')::uuid;

  return v_ordered;
end;
$$;

-- Writes shares, items and assignees for a bill whose row already exists.
-- Shared by create_bill and update_bill so the two cannot drift.
create or replace function public.apply_bill_split(
  p_bill_id uuid,
  p_group_id uuid,
  p_paid_by uuid,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_participants jsonb := public.canonical_participants(
    p_group_id, p_payload -> 'participants'
  );
  v_mode text := p_payload ->> 'split_mode';
  v_split jsonb;
  v_item jsonb;
  v_item_id uuid;
  v_position int := 0;
begin
  v_split := public.compute_split(
    jsonb_build_object(
      'total', (p_payload ->> 'total_amount')::bigint,
      'mode', v_mode,
      'participants', v_participants,
      'items', coalesce(p_payload -> 'items', '[]'::jsonb),
      'extras', coalesce(p_payload -> 'extras', '{}'::jsonb)
    )
  );

  -- Participants who are no longer on the bill lose their share. Their
  -- payments go with it, but an edit is only permitted while none is pending
  -- or confirmed, so at most a rejected one is lost.
  delete from bill_shares
  where bill_id = p_bill_id
    and user_id not in (
      select (key)::uuid from jsonb_each_text(v_split)
    );

  -- Continuing participants keep their row — and any rejected payment history
  -- hanging off it — with the amount brought up to date.
  insert into bill_shares (bill_id, user_id, amount, split_input, status, settled_at)
  select
    p_bill_id,
    (s.key)::uuid,
    (s.value)::bigint,
    p.input,
    -- The payer never owes themselves: if they share the cost, their share is
    -- settled on the spot (spec §6.3).
    case when (s.key)::uuid = p_paid_by then 'settled' else 'unpaid' end,
    case when (s.key)::uuid = p_paid_by then now() else null end
  from jsonb_each_text(v_split) as s(key, value)
  left join lateral (
    select (e ->> 'input')::numeric as input
    from jsonb_array_elements(v_participants) as e
    where e ->> 'user_id' = s.key
    limit 1
  ) as p on true
  on conflict (bill_id, user_id) do update
  set amount = excluded.amount,
      split_input = excluded.split_input,
      status = excluded.status,
      settled_at = excluded.settled_at,
      last_reminded_at = null;

  -- Items are rebuilt wholesale; nothing hangs off them.
  delete from bill_items where bill_id = p_bill_id;

  if v_mode = 'itemized' then
    for v_item in
      select value from jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb))
    loop
      v_position := v_position + 1;

      insert into bill_items (bill_id, name, amount, position)
      values (
        p_bill_id,
        coalesce(nullif(btrim(v_item ->> 'name'), ''), 'Item ' || v_position),
        (v_item ->> 'amount')::bigint,
        v_position
      )
      returning id into v_item_id;

      insert into bill_item_assignees (item_id, user_id)
      select v_item_id, (a #>> '{}')::uuid
      from jsonb_array_elements(coalesce(v_item -> 'assignees', '[]'::jsonb)) as a;
    end loop;
  end if;
end;
$$;

create or replace function public.create_bill(p_payload jsonb)
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
  v_bill_id uuid;
  v_path text;
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
  if not exists (
    select 1 from group_members
    where group_id = v_group_id and user_id = v_paid_by and left_at is null
  ) then
    raise exception 'The payer is not in this group' using errcode = 'HT031';
  end if;

  insert into bills (
    group_id, title, notes, category, total_amount, paid_by, created_by,
    split_mode, bill_date, itemized_extras
  )
  values (
    v_group_id,
    v_title,
    nullif(btrim(coalesce(p_payload ->> 'notes', '')), ''),
    nullif(btrim(coalesce(p_payload ->> 'category', '')), ''),
    (p_payload ->> 'total_amount')::bigint,
    v_paid_by,
    v_uid,
    v_mode,
    coalesce((p_payload ->> 'bill_date')::date, current_date),
    case when v_mode = 'itemized'
      then coalesce(p_payload -> 'extras', '{}'::jsonb)
      else '{}'::jsonb
    end
  )
  returning id into v_bill_id;

  perform public.apply_bill_split(v_bill_id, v_group_id, v_paid_by, p_payload);

  for v_path in
    select a #>> '{}'
    from jsonb_array_elements(coalesce(p_payload -> 'attachment_paths', '[]'::jsonb)) as a
  loop
    insert into bill_attachments (bill_id, path, uploaded_by)
    values (v_bill_id, v_path, v_uid);
  end loop;

  insert into activity_events (group_id, actor_id, type, bill_id, payload)
  values (
    v_group_id, v_uid, 'bill_created', v_bill_id,
    jsonb_build_object(
      'bill_title', v_title,
      'total_amount', (p_payload ->> 'total_amount')::bigint,
      'split_mode', v_mode
    )
  );

  return v_bill_id;
end;
$$;

create or replace function public.update_bill(p_bill_id uuid, p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_bill bills%rowtype;
  v_paid_by uuid;
  v_title text := btrim(coalesce(p_payload ->> 'title', ''));
  v_mode text := p_payload ->> 'split_mode';
  v_blocking int;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_bill from bills where id = p_bill_id;
  if not found then
    raise exception 'That bill no longer exists' using errcode = 'HT030';
  end if;
  if not public.is_group_member(v_bill.group_id) then
    raise exception 'Not a member of that group' using errcode = 'HT001';
  end if;
  if v_bill.status = 'void' then
    raise exception 'That bill was voided' using errcode = 'HT036';
  end if;
  if v_uid <> v_bill.created_by and v_uid <> v_bill.paid_by then
    raise exception 'Only whoever added the bill, or the payer, can edit it'
      using errcode = 'HT035';
  end if;

  -- Spec §12.1: editing stops the moment money is in flight. The UI offers
  -- "void and recreate" instead.
  select count(*)
  into v_blocking
  from payments p
  join bill_shares s on s.id = p.bill_share_id
  where s.bill_id = p_bill_id
    and p.status in ('pending', 'confirmed');

  if v_blocking > 0 then
    raise exception 'Someone has already paid — void the bill and add it again'
      using errcode = 'HT033';
  end if;

  v_paid_by := coalesce((p_payload ->> 'paid_by')::uuid, v_bill.paid_by);

  if not exists (
    select 1 from group_members
    where group_id = v_bill.group_id and user_id = v_paid_by and left_at is null
  ) then
    raise exception 'The payer is not in this group' using errcode = 'HT031';
  end if;
  if v_title = '' then
    raise exception 'Give the bill a title' using errcode = 'HT010';
  end if;

  update bills
  set title = v_title,
      notes = nullif(btrim(coalesce(p_payload ->> 'notes', '')), ''),
      category = nullif(btrim(coalesce(p_payload ->> 'category', '')), ''),
      total_amount = (p_payload ->> 'total_amount')::bigint,
      paid_by = v_paid_by,
      split_mode = v_mode,
      bill_date = coalesce((p_payload ->> 'bill_date')::date, v_bill.bill_date),
      itemized_extras = case when v_mode = 'itemized'
        then coalesce(p_payload -> 'extras', '{}'::jsonb)
        else '{}'::jsonb
      end,
      status = 'open'
  where id = p_bill_id;

  perform public.apply_bill_split(
    p_bill_id, v_bill.group_id, v_paid_by, p_payload
  );

  insert into activity_events (group_id, actor_id, type, bill_id, payload)
  values (
    v_bill.group_id, v_uid, 'bill_edited', p_bill_id,
    jsonb_build_object(
      'bill_title', v_title,
      'total_amount', (p_payload ->> 'total_amount')::bigint
    )
  );
end;
$$;

create or replace function public.void_bill(p_bill_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_bill bills%rowtype;
  v_confirmed int;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_bill from bills where id = p_bill_id;
  if not found then
    raise exception 'That bill no longer exists' using errcode = 'HT030';
  end if;
  if not public.is_group_member(v_bill.group_id) then
    raise exception 'Not a member of that group' using errcode = 'HT001';
  end if;
  if v_bill.status = 'void' then
    return;  -- already void; voiding twice is a no-op
  end if;

  if v_uid <> v_bill.created_by
     and v_uid <> v_bill.paid_by
     and not public.has_group_role(v_bill.group_id, array['owner', 'admin']) then
    raise exception 'Only the bill owner, the payer or a group admin can void it'
      using errcode = 'HT035';
  end if;

  select count(*)
  into v_confirmed
  from payments p
  join bill_shares s on s.id = p.bill_share_id
  where s.bill_id = p_bill_id and p.status = 'confirmed';

  if v_confirmed > 0 then
    raise exception 'Someone has already settled this bill'
      using errcode = 'HT034';
  end if;

  -- Pending payments are rejected rather than left dangling (spec §7).
  update payments p
  set status = 'rejected',
      rejected_reason = coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Bill voided')
  from bill_shares s
  where s.id = p.bill_share_id
    and s.bill_id = p_bill_id
    and p.status = 'pending';

  update bill_shares
  set status = 'unpaid', settled_at = null
  where bill_id = p_bill_id;

  update bills set status = 'void' where id = p_bill_id;

  insert into activity_events (group_id, actor_id, type, bill_id, payload)
  values (
    v_bill.group_id, v_uid, 'bill_voided', p_bill_id,
    jsonb_build_object(
      'bill_title', v_bill.title,
      'reason', nullif(btrim(coalesce(p_reason, '')), '')
    )
  );
end;
$$;

-- Powers the Home screen (spec §7, §10): per group, what the caller owes and
-- what they are owed, across open shares only.
create or replace function public.get_my_balances()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with mine as (
    select group_id from group_members
    where user_id = auth.uid() and left_at is null
  ),
  open_shares as (
    select b.group_id, b.paid_by, s.user_id, s.amount
    from bills b
    join bill_shares s on s.bill_id = b.id
    where b.status <> 'void'
      and s.status in ('unpaid', 'pending_confirmation')
      and b.group_id in (select group_id from mine)
  )
  select coalesce(jsonb_agg(entry order by group_name), '[]'::jsonb)
  from (
    select
      g.name as group_name,
      jsonb_build_object(
        'group_id', g.id,
        'group_name', g.name,
        'owed_by_me', coalesce(sum(o.amount) filter (
          where o.user_id = auth.uid() and o.paid_by <> auth.uid()
        ), 0),
        'owed_to_me', coalesce(sum(o.amount) filter (
          where o.paid_by = auth.uid() and o.user_id <> auth.uid()
        ), 0)
      ) as entry
    from groups g
    left join open_shares o on o.group_id = g.id
    where g.id in (select group_id from mine)
    group by g.id, g.name
  ) rows;
$$;

-- "Needs your attention" on Home (spec §10): the shares the caller still owes.
create or replace function public.get_my_open_shares()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(entry order by bill_date desc, bill_title), '[]'::jsonb)
  from (
    select
      b.bill_date,
      b.title as bill_title,
      jsonb_build_object(
        'bill_id', b.id,
        'bill_title', b.title,
        'bill_date', b.bill_date,
        'group_id', b.group_id,
        'group_name', g.name,
        'payer_id', b.paid_by,
        'payer_name', p.display_name,
        'amount', s.amount,
        'status', s.status
      ) as entry
    from bill_shares s
    join bills b on b.id = s.bill_id
    join groups g on g.id = b.group_id
    join profiles p on p.id = b.paid_by
    where s.user_id = auth.uid()
      and s.status in ('unpaid', 'pending_confirmation')
      and b.status <> 'void'
      and b.paid_by <> auth.uid()
  ) rows;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.canonical_participants(uuid, jsonb)',
    'public.apply_bill_split(uuid, uuid, uuid, jsonb)',
    'public.create_bill(jsonb)',
    'public.update_bill(uuid, jsonb)',
    'public.void_bill(uuid, text)',
    'public.get_my_balances()',
    'public.get_my_open_shares()'
  ]
  loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;

-- apply_bill_split is an internal helper: create_bill and update_bill enforce
-- the permission and lock rules before calling it, so it must not be reachable
-- on its own.
revoke execute on function public.apply_bill_split(uuid, uuid, uuid, jsonb)
  from authenticated;
