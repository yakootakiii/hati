-- Hati — settlement (spec §7, §9, §12.9).
--
-- Money moves outside the app: the debtor pays by GCash, Maya or bank, marks
-- it here, and the payer confirms. These four functions are the only way a
-- payment row or a share status ever changes.
--
--   HT040  that share no longer exists
--   HT041  only the person who owes it can do that
--   HT042  only the payer of the bill can do that
--   HT043  that share is already settled
--   HT044  that payment no longer exists
--   HT045  that payment has already been decided
--   HT046  the bill was voided
--
-- Every function is idempotent (spec §12.9): a second tap re-reads the current
-- status and returns quietly rather than creating a second payment or a second
-- activity event.

-- Marks a share as paid, awaiting the payer's confirmation.
--
-- Returns the payment id. Tapping twice returns the same one.
create or replace function public.mark_share_paid(
  p_bill_share_id uuid,
  p_method text default null,
  p_reference_no text default null,
  p_proof_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_share bill_shares%rowtype;
  v_bill bills%rowtype;
  v_payment_id uuid;
  v_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_share from bill_shares where id = p_bill_share_id;
  if not found then
    raise exception 'That share no longer exists' using errcode = 'HT040';
  end if;
  if v_share.user_id <> v_uid then
    raise exception 'Only the person who owes this can mark it paid'
      using errcode = 'HT041';
  end if;

  select * into v_bill from bills where id = v_share.bill_id;
  if v_bill.status = 'void' then
    raise exception 'That bill was voided' using errcode = 'HT046';
  end if;

  -- Already awaiting confirmation: a duplicate tap, so hand back the payment
  -- that is already in flight (spec §12.9).
  if v_share.status = 'pending_confirmation' then
    select id into v_payment_id
    from payments
    where bill_share_id = p_bill_share_id and status = 'pending'
    limit 1;

    if v_payment_id is not null then
      return v_payment_id;
    end if;
  end if;

  if v_share.status = 'settled' then
    raise exception 'That share is already settled' using errcode = 'HT043';
  end if;

  -- v1 has no partial payments, so the amount is always the whole share
  -- (DECISIONS D-06).
  insert into payments (
    bill_share_id, from_user, to_user, amount, method, reference_no, proof_path
  )
  values (
    p_bill_share_id, v_uid, v_bill.paid_by, v_share.amount,
    nullif(btrim(coalesce(p_method, '')), ''),
    nullif(btrim(coalesce(p_reference_no, '')), ''),
    nullif(btrim(coalesce(p_proof_path, '')), '')
  )
  returning id into v_payment_id;

  update bill_shares
  set status = 'pending_confirmation'
  where id = p_bill_share_id;

  select display_name into v_name from profiles where id = v_uid;

  insert into activity_events (group_id, actor_id, type, bill_id, payment_id, payload)
  values (
    v_bill.group_id, v_uid, 'payment_marked', v_bill.id, v_payment_id,
    jsonb_build_object(
      'bill_title', v_bill.title,
      'amount', v_share.amount,
      'display_name', v_name,
      'method', p_method
    )
  );

  return v_payment_id;
end;
$$;

-- The payer confirms they received the money.
--
-- Only the bill's payer may call this: a debtor confirming their own payment
-- is exactly what spec §14 requires be impossible.
create or replace function public.confirm_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_payment payments%rowtype;
  v_share bill_shares%rowtype;
  v_bill bills%rowtype;
  v_name text;
  v_outstanding int;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_payment from payments where id = p_payment_id;
  if not found then
    raise exception 'That payment no longer exists' using errcode = 'HT044';
  end if;

  select * into v_share from bill_shares where id = v_payment.bill_share_id;
  select * into v_bill from bills where id = v_share.bill_id;

  if v_bill.paid_by <> v_uid then
    raise exception 'Only the person who paid the bill can confirm this'
      using errcode = 'HT042';
  end if;

  -- Confirming twice does nothing the second time (spec §12.9).
  if v_payment.status = 'confirmed' then
    return;
  end if;
  if v_payment.status = 'rejected' then
    raise exception 'That payment was already rejected' using errcode = 'HT045';
  end if;

  update payments
  set status = 'confirmed', confirmed_at = now(), rejected_reason = null
  where id = p_payment_id;

  update bill_shares
  set status = 'settled', settled_at = now(), last_reminded_at = null
  where id = v_share.id;

  select display_name into v_name from profiles where id = v_uid;

  insert into activity_events (group_id, actor_id, type, bill_id, payment_id, payload)
  values (
    v_bill.group_id, v_uid, 'payment_confirmed', v_bill.id, p_payment_id,
    jsonb_build_object(
      'bill_title', v_bill.title,
      'amount', v_payment.amount,
      'display_name', v_name,
      'debtor_id', v_payment.from_user
    )
  );

  -- Last one in settles the bill.
  select count(*) into v_outstanding
  from bill_shares
  where bill_id = v_bill.id and status <> 'settled';

  if v_outstanding = 0 then
    update bills set status = 'settled' where id = v_bill.id;

    insert into activity_events (group_id, actor_id, type, bill_id, payload)
    values (
      v_bill.group_id, v_uid, 'bill_settled', v_bill.id,
      jsonb_build_object('bill_title', v_bill.title)
    );
  end if;
end;
$$;

-- The payer says the money never arrived. The share goes back to unpaid so the
-- debtor can try again.
create or replace function public.reject_payment(
  p_payment_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_payment payments%rowtype;
  v_share bill_shares%rowtype;
  v_bill bills%rowtype;
  v_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_payment from payments where id = p_payment_id;
  if not found then
    raise exception 'That payment no longer exists' using errcode = 'HT044';
  end if;

  select * into v_share from bill_shares where id = v_payment.bill_share_id;
  select * into v_bill from bills where id = v_share.bill_id;

  if v_bill.paid_by <> v_uid then
    raise exception 'Only the person who paid the bill can reject this'
      using errcode = 'HT042';
  end if;

  if v_payment.status = 'rejected' then
    return;
  end if;
  if v_payment.status = 'confirmed' then
    raise exception 'That payment was already confirmed' using errcode = 'HT045';
  end if;

  update payments
  set status = 'rejected',
      rejected_reason = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_payment_id;

  update bill_shares
  set status = 'unpaid', settled_at = null
  where id = v_share.id;

  select display_name into v_name from profiles where id = v_uid;

  insert into activity_events (group_id, actor_id, type, bill_id, payment_id, payload)
  values (
    v_bill.group_id, v_uid, 'payment_rejected', v_bill.id, p_payment_id,
    jsonb_build_object(
      'bill_title', v_bill.title,
      'amount', v_payment.amount,
      'display_name', v_name,
      'debtor_id', v_payment.from_user,
      'reason', nullif(btrim(coalesce(p_reason, '')), '')
    )
  );
end;
$$;

-- The shortcut for cash handed over in person (spec §7): the payer records it
-- themselves and it is confirmed on the spot.
create or replace function public.record_payment_received(
  p_bill_share_id uuid,
  p_method text default 'cash'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_share bill_shares%rowtype;
  v_bill bills%rowtype;
  v_payment_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_share from bill_shares where id = p_bill_share_id;
  if not found then
    raise exception 'That share no longer exists' using errcode = 'HT040';
  end if;

  select * into v_bill from bills where id = v_share.bill_id;

  if v_bill.paid_by <> v_uid then
    raise exception 'Only the person who paid the bill can record this'
      using errcode = 'HT042';
  end if;
  if v_bill.status = 'void' then
    raise exception 'That bill was voided' using errcode = 'HT046';
  end if;
  if v_share.status = 'settled' then
    raise exception 'That share is already settled' using errcode = 'HT043';
  end if;

  -- A payment already awaiting confirmation is confirmed rather than
  -- duplicated — the payer is, after all, saying the money arrived.
  select id into v_payment_id
  from payments
  where bill_share_id = p_bill_share_id and status = 'pending'
  limit 1;

  if v_payment_id is not null then
    perform public.confirm_payment(v_payment_id);
    return v_payment_id;
  end if;

  insert into payments (
    bill_share_id, from_user, to_user, amount, method, status, confirmed_at
  )
  values (
    p_bill_share_id, v_share.user_id, v_uid, v_share.amount,
    coalesce(nullif(btrim(coalesce(p_method, '')), ''), 'cash'),
    'pending', null
  )
  returning id into v_payment_id;

  -- Routed through confirm_payment so the settle-the-bill check and the
  -- activity events live in exactly one place.
  perform public.confirm_payment(v_payment_id);

  return v_payment_id;
end;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.mark_share_paid(uuid, text, text, text)',
    'public.confirm_payment(uuid)',
    'public.reject_payment(uuid, text)',
    'public.record_payment_received(uuid, text)'
  ]
  loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;
