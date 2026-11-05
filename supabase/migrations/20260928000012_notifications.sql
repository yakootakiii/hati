-- Hati — notifications (spec §7.2).
--
-- A trigger on activity_events fans out one notifications row per recipient.
-- Putting it here rather than in the RPCs means every event notifies, and the
-- recipient list and copy live in one place instead of thirteen.
--
-- Preferences are applied here too, so an unwanted notification is never
-- written — not written and then filtered on the way out.
--
--   HT050  that share no longer exists
--   HT051  only the payer of the bill can nudge
--   HT052  that share is already settled
--   HT053  nudged too recently

-- ₱12,500.00 from 1250000. numeric division is exact, so no money is lost on
-- the way to the text.
create or replace function public.peso(centavos bigint)
returns text
language sql
immutable
as $$
  select '₱' || to_char(centavos::numeric / 100, 'FM999,999,990.00');
$$;

-- ---------------------------------------------------------------------------
-- fan-out
-- ---------------------------------------------------------------------------

-- notification_prefs has five switches (§5.1) and §5.3 has fourteen event
-- types, so the mapping is explicit rather than one-to-one:
--
--   new_bill           bill_created, recurring_generated, bill_edited,
--                      bill_voided
--   payment_marked     payment_marked
--   payment_confirmed  payment_confirmed, payment_rejected
--   comments           comment_added
--   reminders          the daily reminder and the payer's Nudge
--
-- member_joined has no switch and always sends; the remaining types notify
-- nobody, because §7.2 does not list them (DECISIONS D-44).
create or replace function public.fan_out_notifications()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bill bills%rowtype;
  v_group groups%rowtype;
  v_actor text;
  v_title text;
  v_route jsonb;
  v_amount bigint := nullif(new.payload ->> 'amount', '')::bigint;
  v_reason text := nullif(new.payload ->> 'reason', '');
  v_excerpt text := nullif(new.payload ->> 'excerpt', '');
  v_debtor uuid := nullif(new.payload ->> 'debtor_id', '')::uuid;
begin
  select display_name into v_actor from profiles where id = new.actor_id;
  v_actor := coalesce(v_actor, 'Someone');

  select * into v_group from groups where id = new.group_id;

  if new.bill_id is not null then
    select * into v_bill from bills where id = new.bill_id;
  end if;

  v_route := jsonb_build_object(
    'route',
    case when new.bill_id is null
      then '/groups/' || new.group_id
      else '/bills/' || new.bill_id
    end,
    'group_id', new.group_id,
    'event_type', new.type
  );

  -- ── a bill appeared, changed or went away ────────────────────────────────
  if new.type in ('bill_created', 'recurring_generated', 'bill_edited', 'bill_voided') then
    v_title := case new.type
      when 'bill_edited' then format('%s updated %s', v_actor, v_bill.title)
      when 'bill_voided' then format('%s voided %s', v_actor, v_bill.title)
      when 'recurring_generated' then format('%s was added automatically', v_bill.title)
      else format('%s added %s', v_actor, v_bill.title)
    end;

    insert into notifications (user_id, type, title, body, data)
    select
      s.user_id,
      new.type,
      v_title,
      case
        when new.type = 'bill_voided' then
          coalesce(v_reason, 'It no longer counts towards your balance.')
        when s.user_id = v_bill.paid_by then 'You paid for this one.'
        when new.type = 'bill_edited' then
          format('Your share is now %s.', public.peso(s.amount))
        else format('You owe %s.', public.peso(s.amount))
      end,
      v_route
    from bill_shares s
    left join notification_prefs p on p.user_id = s.user_id
    where s.bill_id = new.bill_id
      and s.user_id is distinct from new.actor_id
      and coalesce(p.new_bill, true);

  -- ── somebody says they paid ──────────────────────────────────────────────
  elsif new.type = 'payment_marked' then
    insert into notifications (user_id, type, title, body, data)
    select
      v_bill.paid_by,
      new.type,
      format('%s marked %s as paid', v_actor, public.peso(v_amount)),
      format('For %s. Tap to confirm.', v_bill.title),
      v_route
    -- No FROM: this selects one row, or none when the guard fails.
    where v_bill.paid_by is distinct from new.actor_id
      and coalesce(
        (select pp.payment_marked from notification_prefs pp
         where pp.user_id = v_bill.paid_by),
        true
      );

  -- ── the payer decided ────────────────────────────────────────────────────
  elsif new.type in ('payment_confirmed', 'payment_rejected') and v_debtor is not null then
    insert into notifications (user_id, type, title, body, data)
    select
      v_debtor,
      new.type,
      case new.type
        when 'payment_confirmed'
          then format('%s confirmed your %s payment', v_actor, public.peso(v_amount))
        else format('%s could not find your payment', v_actor)
      end,
      case new.type
        when 'payment_confirmed' then format('For %s.', v_bill.title)
        else coalesce(
          format('For %s: %s', v_bill.title, v_reason),
          format('For %s. Tap to try again.', v_bill.title)
        )
      end,
      v_route
    where coalesce(
      (select pp.payment_confirmed from notification_prefs pp
       where pp.user_id = v_debtor),
      true
    );

  -- ── someone commented ────────────────────────────────────────────────────
  elsif new.type = 'comment_added' then
    insert into notifications (user_id, type, title, body, data)
    select distinct
      recipient,
      new.type,
      format('%s commented on %s', v_actor, v_bill.title),
      coalesce(v_excerpt, 'Tap to read it.'),
      v_route
    from (
      select s.user_id as recipient from bill_shares s where s.bill_id = new.bill_id
      union
      select v_bill.paid_by
    ) as people
    left join notification_prefs p on p.user_id = people.recipient
    where recipient is not null
      and recipient is distinct from new.actor_id
      and coalesce(p.comments, true);

  -- ── someone joined ───────────────────────────────────────────────────────
  elsif new.type = 'member_joined' then
    insert into notifications (user_id, type, title, body, data)
    select
      m.user_id,
      new.type,
      format('%s joined %s',
             coalesce(new.payload ->> 'display_name', v_actor), v_group.name),
      'Say hi.',
      v_route
    from group_members m
    where m.group_id = new.group_id
      and m.left_at is null
      and m.user_id is distinct from new.actor_id;
  end if;

  return new;
end;
$$;

create trigger activity_events_fan_out
  after insert on public.activity_events
  for each row execute function public.fan_out_notifications();

-- ---------------------------------------------------------------------------
-- reminders and nudges
-- ---------------------------------------------------------------------------

-- One reminder at three days and one more at seven (spec §7.2).
--
-- last_reminded_at carries both: null means never reminded, and a value at or
-- past created_at + 7 days means both have gone out. The Nudge below writes to
-- the same column on purpose — a manual nudge counts as a reminder, so the
-- debtor does not get two messages in a day (DECISIONS D-45).
create or replace function public.send_reminders()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sent int := 0;
  v_share record;
begin
  for v_share in
    select
      s.id, s.user_id, s.amount, s.created_at,
      b.id as bill_id, b.title, b.group_id, b.paid_by,
      p.display_name as payer_name
    from bill_shares s
    join bills b on b.id = s.bill_id
    join profiles p on p.id = b.paid_by
    left join notification_prefs np on np.user_id = s.user_id
    where s.status = 'unpaid'
      and b.status <> 'void'
      and s.user_id <> b.paid_by
      and coalesce(np.reminders, true)
      and (
        (s.last_reminded_at is null
          and s.created_at <= now() - interval '3 days')
        or (s.last_reminded_at is not null
          and s.created_at <= now() - interval '7 days'
          and s.last_reminded_at < s.created_at + interval '7 days')
      )
  loop
    insert into notifications (user_id, type, title, body, data)
    values (
      v_share.user_id,
      'reminder',
      format('You still owe %s %s',
             v_share.payer_name, public.peso(v_share.amount)),
      format('For %s.', v_share.title),
      jsonb_build_object(
        'route', '/bills/' || v_share.bill_id,
        'group_id', v_share.group_id,
        'event_type', 'reminder'
      )
    );

    update bill_shares set last_reminded_at = now() where id = v_share.id;
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$$;

create or replace function public.nudge_share(p_bill_share_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_share bill_shares%rowtype;
  v_bill bills%rowtype;
  v_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_share from bill_shares where id = p_bill_share_id;
  if not found then
    raise exception 'That share no longer exists' using errcode = 'HT050';
  end if;

  select * into v_bill from bills where id = v_share.bill_id;
  if v_bill.paid_by <> v_uid then
    raise exception 'Only the person who paid the bill can nudge'
      using errcode = 'HT051';
  end if;
  if v_share.status = 'settled' or v_bill.status = 'void' then
    raise exception 'Nothing to nudge about' using errcode = 'HT052';
  end if;

  -- Once a day per share (spec §7.2).
  if v_share.last_reminded_at is not null
     and v_share.last_reminded_at > now() - interval '24 hours' then
    raise exception 'Already nudged in the last 24 hours'
      using errcode = 'HT053';
  end if;

  select display_name into v_name from profiles where id = v_uid;

  insert into notifications (user_id, type, title, body, data)
  select
    v_share.user_id,
    'nudge',
    format('%s is waiting on %s', v_name, public.peso(v_share.amount)),
    format('For %s.', v_bill.title),
    jsonb_build_object(
      'route', '/bills/' || v_bill.id,
      'group_id', v_bill.group_id,
      'event_type', 'nudge'
    )
  where coalesce(
    (select pp.reminders from notification_prefs pp
     where pp.user_id = v_share.user_id),
    true
  );

  update bill_shares set last_reminded_at = now() where id = p_bill_share_id;
end;
$$;

-- The daily job. M9 adds recurring-bill generation to it.
create or replace function public.run_daily_jobs()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reminders int;
begin
  v_reminders := public.send_reminders();
  return jsonb_build_object('reminders_sent', v_reminders, 'ran_at', now());
end;
$$;

-- ---------------------------------------------------------------------------
-- grants
-- ---------------------------------------------------------------------------

revoke all on function public.send_reminders() from public, anon, authenticated;
revoke all on function public.run_daily_jobs() from public, anon, authenticated;
revoke all on function public.fan_out_notifications() from public, anon, authenticated;

revoke all on function public.nudge_share(uuid) from public, anon;
grant execute on function public.nudge_share(uuid) to authenticated;

revoke all on function public.peso(bigint) from public, anon;
grant execute on function public.peso(bigint) to authenticated;
