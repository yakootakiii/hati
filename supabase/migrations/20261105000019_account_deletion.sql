-- Hati — deleting your own account (DECISIONS D-64).
--
-- Google Play requires in-app account deletion, and the Data Privacy Act
-- gives a right to erasure. Two halves:
--
--   account_deletion_blockers()  what stops it — open money, as for leaving
--   prepare_account_deletion()   erases what is personal, anonymises the rest
--
-- The sign-in itself is removed by the delete-account edge function, which
-- calls prepare_account_deletion() as the user and then soft-deletes the auth
-- user with the service role. Soft, because bills, shares, payments and
-- comments other people depend on reference the profile; those records stay,
-- under "Deleted user", as the Terms (§11) and Privacy Notice (§6) say.
--
--   HT009  settle up first — the caller still owes or is owed money

-- Every open debt in either direction, across all of the caller's groups.
create or replace function public.account_deletion_blockers()
returns table (
  group_id uuid,
  group_name text,
  bill_id uuid,
  title text,
  reason text,
  amount bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  return query
    -- Shares they still owe.
    select g.id, g.name, b.id, b.title, 'you_owe'::text, s.amount
    from bill_shares s
    join bills b on b.id = s.bill_id
    join groups g on g.id = b.group_id
    where b.status <> 'void'
      and s.user_id = v_uid
      and b.paid_by <> v_uid
      and s.status in ('unpaid', 'pending_confirmation')
    union all
    -- Bills they paid for that others have not settled.
    select g.id, g.name, b.id, b.title, 'owed_to_you'::text,
           sum(s.amount)::bigint
    from bills b
    join groups g on g.id = b.group_id
    join bill_shares s on s.bill_id = b.id
    where b.status <> 'void'
      and b.paid_by = v_uid
      and s.user_id <> v_uid
      and s.status in ('unpaid', 'pending_confirmation')
    group by g.id, g.name, b.id, b.title;
end;
$$;

create or replace function public.prepare_account_deletion()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_blockers text;
  v_membership record;
  v_successor uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select string_agg(distinct title, ', ')
  into v_blockers
  from public.account_deletion_blockers();

  if v_blockers is not null then
    raise exception 'Settle up first: %', v_blockers using errcode = 'HT009';
  end if;

  -- ── leave every group, handing ownership on ──────────────────────────────
  for v_membership in
    select gm.group_id, gm.role
    from group_members gm
    where gm.user_id = v_uid and gm.left_at is null
  loop
    if v_membership.role = 'owner' then
      -- An admin first, then whoever has been there longest.
      select gm.user_id into v_successor
      from group_members gm
      where gm.group_id = v_membership.group_id
        and gm.user_id <> v_uid
        and gm.left_at is null
      order by (gm.role = 'admin') desc, gm.joined_at, gm.user_id
      limit 1;

      if v_successor is not null then
        -- One owner per group (group_members_single_owner), so step down
        -- before the successor steps up.
        update group_members
        set role = 'member'
        where group_id = v_membership.group_id and user_id = v_uid;

        update group_members
        set role = 'owner'
        where group_id = v_membership.group_id and user_id = v_successor;
      end if;
    end if;

    update group_members
    set left_at = now()
    where group_id = v_membership.group_id and user_id = v_uid;

    insert into activity_events (group_id, actor_id, type, payload)
    values (
      v_membership.group_id, v_uid, 'member_left',
      jsonb_build_object('display_name', 'Deleted user')
    );
  end loop;

  -- Repeating bills that would keep generating debts for someone who is gone.
  update recurring_bills
  set paused = true
  where not paused
    and (
      paid_by = v_uid
      or split_config -> 'participants'
           @> jsonb_build_array(jsonb_build_object('user_id', v_uid))
    );

  -- ── erase what is only theirs ────────────────────────────────────────────
  delete from payment_methods where user_id = v_uid;
  delete from device_tokens where user_id = v_uid;
  delete from notifications where user_id = v_uid;
  delete from notification_prefs where user_id = v_uid;
  delete from group_direct_invites
  where status = 'pending' and (invitee_id = v_uid or invited_by = v_uid);

  -- ── anonymise what others still need ─────────────────────────────────────
  -- Names stored inside past activity, where they were copied at the time.
  update activity_events
  set payload = payload || jsonb_build_object('display_name', 'Deleted user')
  where actor_id = v_uid and payload ? 'display_name';

  update profiles
  set display_name = 'Deleted user',
      avatar_path = null
  where id = v_uid;
end;
$$;

revoke all on function public.account_deletion_blockers() from public, anon;
grant execute on function public.account_deletion_blockers() to authenticated;
revoke all on function public.prepare_account_deletion() from public, anon;
grant execute on function public.prepare_account_deletion() to authenticated;
