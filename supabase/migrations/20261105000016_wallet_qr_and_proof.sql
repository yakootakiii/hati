-- Hati — e-wallet QR codes, choosing where to be paid, and required proof.
--
-- Three changes, all on the settle-up path:
--
--   1. More Philippine e-wallets. A payment method can now be GoTyme,
--      ShopeePay, GrabPay, Coins.ph or PalawanPay as well as GCash, Maya and
--      bank, so people can keep one QR per wallet on their profile.
--
--   2. The payer of a bill can say where they want to receive the money:
--      bills.receive_method_id points at one of their own payment methods, or
--      is null for "any of my wallets". Only the payer can set it, through
--      set_bill_receive_method, because bills stay RPC-only (spec §5.4).
--
--   3. "I've paid" now needs a screenshot. mark_share_paid refuses a claim
--      with no proof, so the requirement holds even for a client that skips
--      the UI check.
--
--   HT047  a screenshot of the payment is required
--   HT048  that payment method is not the payer's

-- ---------------------------------------------------------------------------
-- 1. wallets
-- ---------------------------------------------------------------------------

alter table public.payment_methods
  drop constraint payment_methods_type_check,
  add constraint payment_methods_type_check check (type in (
    'gcash', 'maya', 'gotyme', 'shopeepay', 'grabpay', 'coinsph',
    'palawanpay', 'bank', 'other'
  ));

alter table public.payments
  drop constraint payments_method_check,
  add constraint payments_method_check check (method in (
    'gcash', 'maya', 'gotyme', 'shopeepay', 'grabpay', 'coinsph',
    'palawanpay', 'bank', 'cash', 'other'
  ));

-- ---------------------------------------------------------------------------
-- 2. where the payer wants to be paid
-- ---------------------------------------------------------------------------

-- Deleting the method falls back to "any wallet" rather than blocking the
-- delete or leaving a dangling id.
alter table public.bills
  add column receive_method_id uuid
    references public.payment_methods on delete set null;

-- A choice belongs to whoever paid. If an edit changes the payer, the old
-- payer's wallet no longer makes sense, so the choice is cleared.
create or replace function public.clear_receive_method_on_payer_change()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.paid_by is distinct from old.paid_by then
    new.receive_method_id := null;
  end if;
  return new;
end;
$$;

create trigger bills_clear_receive_method
  before update of paid_by on public.bills
  for each row
  execute function public.clear_receive_method_on_payer_change();

-- Sets (or, with null, clears) where the payer of a bill wants to be paid.
create or replace function public.set_bill_receive_method(
  p_bill_id uuid,
  p_method_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_bill bills%rowtype;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_bill from bills where id = p_bill_id;
  if not found then
    raise exception 'That bill no longer exists' using errcode = 'HT030';
  end if;
  if v_bill.paid_by <> v_uid then
    raise exception 'Only the payer of the bill can choose where to be paid'
      using errcode = 'HT042';
  end if;
  if v_bill.status = 'void' then
    raise exception 'That bill was voided' using errcode = 'HT046';
  end if;

  if p_method_id is not null and not exists (
    select 1 from payment_methods where id = p_method_id and user_id = v_uid
  ) then
    raise exception 'That payment method is not yours' using errcode = 'HT048';
  end if;

  update bills set receive_method_id = p_method_id where id = p_bill_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. proof is required to mark a share paid
-- ---------------------------------------------------------------------------

-- Same as 20260925000010, plus the HT047 check just before the insert. It sits
-- after the duplicate-tap return so a retry of a claim already in flight still
-- answers quietly (spec §12.9).
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
  if v_proof is null or v_proof not like v_bill.group_id::text || '/%' then
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

-- ---------------------------------------------------------------------------
-- execution grants
-- ---------------------------------------------------------------------------

revoke all on function public.clear_receive_method_on_payer_change()
  from public, anon, authenticated;

revoke all on function public.set_bill_receive_method(uuid, uuid)
  from public, anon;
grant execute on function public.set_bill_receive_method(uuid, uuid)
  to authenticated;
