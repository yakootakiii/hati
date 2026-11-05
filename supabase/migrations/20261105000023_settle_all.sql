-- Hati — settle several bills with one payment (DECISIONS D-67).
--
-- People pay once for everything they owe someone, not bill by bill. One
-- transfer, one screenshot, one confirmation — while each share still gets
-- its own payment row, so per-bill history, balances and D-06 (a payment is
-- always the whole share) are untouched. payments.batch_id ties them.
--
-- A batch stays within one group: payment proofs live in that group's storage
-- folder, readable by its members only.
--
--   HT054  pick at least one share
--   HT055  every share must be yours, in one group, owed to one person
--   HT056  a share in the batch is already settled or awaiting confirmation

alter table public.payments add column batch_id uuid;
create index payments_batch_id_idx on public.payments (batch_id)
  where batch_id is not null;

create or replace function public.mark_shares_paid(
  p_share_ids uuid[],
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
  v_batch uuid := gen_random_uuid();
  v_count int;
  v_groups int;
  v_payers int;
  v_share uuid;
  v_payment uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if coalesce(array_length(p_share_ids, 1), 0) = 0 then
    raise exception 'Pick at least one bill to settle' using errcode = 'HT054';
  end if;

  select count(*), count(distinct b.group_id), count(distinct b.paid_by)
  into v_count, v_groups, v_payers
  from bill_shares s
  join bills b on b.id = s.bill_id
  where s.id = any (p_share_ids)
    and s.user_id = v_uid
    and b.paid_by <> v_uid
    and b.status <> 'void';

  -- Every id must be one of the caller's live shares, and together they must
  -- be owed to one person in one group.
  if v_count <> cardinality(array(select distinct unnest(p_share_ids)))
     or v_groups <> 1 or v_payers <> 1
  then
    raise exception 'Those bills are not all yours, owed to one person in one group'
      using errcode = 'HT055';
  end if;

  if exists (
    select 1 from bill_shares
    where id = any (p_share_ids) and status <> 'unpaid'
  ) then
    raise exception 'One of those bills is already paid or awaiting confirmation'
      using errcode = 'HT056';
  end if;

  -- The same rules, history and notifications as paying one bill at a time.
  -- mark_share_paid also enforces the proof (HT047).
  foreach v_share in array (select array(select distinct unnest(p_share_ids)))
  loop
    v_payment := public.mark_share_paid(
      v_share, p_method, p_reference_no, p_proof_path
    );
    update payments set batch_id = v_batch where id = v_payment;
  end loop;

  return v_batch;
end;
$$;

-- The payer confirms the whole payment at once.
create or replace function public.confirm_payment_batch(p_batch_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment uuid;
  v_found boolean := false;
begin
  for v_payment in
    select id from payments
    where batch_id = p_batch_id and status = 'pending'
    order by created_at
  loop
    v_found := true;
    -- Checks that the caller is the payer, payment by payment.
    perform public.confirm_payment(v_payment);
  end loop;

  if not v_found and not exists (select 1 from payments where batch_id = p_batch_id) then
    raise exception 'That payment no longer exists' using errcode = 'HT044';
  end if;
end;
$$;

-- …or says it never arrived.
create or replace function public.reject_payment_batch(
  p_batch_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment uuid;
  v_found boolean := false;
begin
  for v_payment in
    select id from payments
    where batch_id = p_batch_id and status = 'pending'
    order by created_at
  loop
    v_found := true;
    perform public.reject_payment(v_payment, p_reason);
  end loop;

  if not v_found and not exists (select 1 from payments where batch_id = p_batch_id) then
    raise exception 'That payment no longer exists' using errcode = 'HT044';
  end if;
end;
$$;

revoke all on function public.mark_shares_paid(uuid[], text, text, text) from public, anon;
grant execute on function public.mark_shares_paid(uuid[], text, text, text) to authenticated;
revoke all on function public.confirm_payment_batch(uuid) from public, anon;
grant execute on function public.confirm_payment_batch(uuid) to authenticated;
revoke all on function public.reject_payment_batch(uuid, text) from public, anon;
grant execute on function public.reject_payment_batch(uuid, text) to authenticated;
