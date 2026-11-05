-- Hati — paying in cash without a screenshot (DECISIONS D-70).
--
-- …0016 made a screenshot mandatory for "I've paid", which left no way to
-- say you paid in cash. Cash now needs no proof; the payer still has to
-- confirm, and every other method still needs its screenshot. mark_shares_paid
-- calls this function, so "Settle all" in cash works the same way.

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
  v_proof text := nullif(btrim(coalesce(p_proof_path, '')), '');
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

  -- The screenshot has to be in this bill's group folder of payment-proofs:
  -- that is where the storage policy lets the group's members read it, so a
  -- path anywhere else would be proof the payer cannot open.
  -- Cash is handed over in person: there is no receipt to show, and the
  -- payer confirms only once they have it (D-70). Every other method still
  -- needs its screenshot.
  if lower(coalesce(btrim(p_method), '')) = 'cash' then
    -- An optional photo must still sit where the group can read it.
    if v_proof is not null and v_proof not like v_bill.group_id::text || '/%' then
      raise exception 'Attach a screenshot of your payment'
        using errcode = 'HT047';
    end if;
  elsif v_proof is null or v_proof not like v_bill.group_id::text || '/%' then
    raise exception 'Attach a screenshot of your payment'
      using errcode = 'HT047';
  end if;

  insert into payments (
    bill_share_id, from_user, to_user, amount, method, reference_no, proof_path
  )
  values (
    p_bill_share_id, v_uid, v_bill.paid_by, v_share.amount,
    nullif(btrim(coalesce(p_method, '')), ''),
    nullif(btrim(coalesce(p_reference_no, '')), ''),
    v_proof
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
