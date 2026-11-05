-- Hati — group, invite and membership RPCs (spec §7).
--
-- Membership tables are not client-writable (see the RLS migration), so every
-- change goes through one of these. They run as the definer, which is how they
-- can write group_members and activity_events at all.
--
-- Failures raise custom SQLSTATEs. PostgREST passes the code through to the
-- client as PostgrestException.code, so the app maps a code to copy rather
-- than matching on message text:
--
--   HT001  not a member of the group
--   HT002  not signed in, or lacking the required role
--   HT003  invite token does not exist
--   HT004  invite has expired
--   HT005  invite was revoked
--   HT006  invite has hit its use limit
--   HT007  blocked by an outstanding balance
--   HT008  the owner must hand ownership over first
--   HT009  the owner cannot be removed
--   HT010  invalid argument

create or replace function public.generate_invite_token()
returns text
language sql
volatile
set search_path = public, pg_temp
as $$
  -- Two random uuids, hyphens stripped: 64 URL-safe characters carrying ~244
  -- bits of randomness, well past the 22 the spec asks for.
  --
  -- gen_random_uuid() is core Postgres, deliberately in preference to
  -- pgcrypto's gen_random_bytes: on Supabase pgcrypto is installed into the
  -- `extensions` schema, so an unqualified call does not resolve.
  select replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');
$$;

-- ---------------------------------------------------------------------------
-- create_group
-- ---------------------------------------------------------------------------

create or replace function public.create_group(
  p_name text,
  p_photo_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_group_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if v_name = '' then
    raise exception 'Give the group a name' using errcode = 'HT010';
  end if;

  insert into groups (name, photo_path, created_by)
  values (v_name, p_photo_path, v_uid)
  returning id into v_group_id;

  insert into group_members (group_id, user_id, role)
  values (v_group_id, v_uid, 'owner');

  insert into activity_events (group_id, actor_id, type, payload)
  values (
    v_group_id, v_uid, 'group_created',
    jsonb_build_object('group_name', v_name)
  );

  return v_group_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- invites
-- ---------------------------------------------------------------------------

create or replace function public.create_invite(
  p_group_id uuid,
  p_expires_in_hours int default null,
  p_max_uses int default null,
  p_revoke_existing boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_token text := public.generate_invite_token();
  v_expires_at timestamptz;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if not public.has_group_role(p_group_id, array['owner', 'admin']) then
    raise exception 'Only an owner or admin can invite people'
      using errcode = 'HT002';
  end if;
  if p_expires_in_hours is not null and p_expires_in_hours <= 0 then
    raise exception 'Expiry must be in the future' using errcode = 'HT010';
  end if;
  if p_max_uses is not null and p_max_uses <= 0 then
    raise exception 'A link needs at least one use' using errcode = 'HT010';
  end if;

  -- "Reset link" (spec §8): the old token stops working the moment a new one
  -- is handed out.
  if p_revoke_existing then
    update group_invites
    set revoked_at = now()
    where group_id = p_group_id and revoked_at is null;
  end if;

  if p_expires_in_hours is not null then
    v_expires_at := now() + make_interval(hours => p_expires_in_hours);
  end if;

  insert into group_invites (group_id, token, created_by, expires_at, max_uses)
  values (p_group_id, v_token, v_uid, v_expires_at, p_max_uses)
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'token', v_token,
    'expires_at', v_expires_at,
    'max_uses', p_max_uses
  );
end;
$$;

create or replace function public.revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_group_id uuid;
begin
  select group_id into v_group_id from group_invites where id = p_invite_id;
  if v_group_id is null then
    raise exception 'That link no longer exists' using errcode = 'HT003';
  end if;
  if not public.has_group_role(v_group_id, array['owner', 'admin']) then
    raise exception 'Only an owner or admin can revoke a link'
      using errcode = 'HT002';
  end if;

  update group_invites set revoked_at = now()
  where id = p_invite_id and revoked_at is null;
end;
$$;

-- What the join screen shows before the user commits (spec §8.2).
--
-- Callable by any signed-in user, member or not — which is exactly why an
-- unusable token returns only the reason. Revealing the group behind a revoked
-- link would make revocation pointless.
create or replace function public.get_invite_preview(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_invite group_invites%rowtype;
  v_group groups%rowtype;
  v_reason text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_invite from group_invites where token = p_token;

  if not found then
    v_reason := 'not_found';
  elsif v_invite.revoked_at is not null then
    v_reason := 'revoked';
  elsif v_invite.expires_at is not null and v_invite.expires_at <= now() then
    v_reason := 'expired';
  elsif v_invite.max_uses is not null and v_invite.use_count >= v_invite.max_uses then
    v_reason := 'exhausted';
  end if;

  if v_reason is not null then
    return jsonb_build_object('valid', false, 'reason', v_reason);
  end if;

  select * into v_group from groups where id = v_invite.group_id;

  return jsonb_build_object(
    'valid', true,
    'group_id', v_group.id,
    'group_name', v_group.name,
    'group_photo_path', v_group.photo_path,
    'member_count', (
      select count(*) from group_members
      where group_id = v_group.id and left_at is null
    ),
    'inviter_name', (
      select display_name from profiles where id = v_invite.created_by
    ),
    'already_member', public.is_group_member(v_group.id)
  );
end;
$$;

-- Joining is idempotent: tapping a link twice, or re-opening it after joining,
-- returns the same group without consuming another use (spec §7).
create or replace function public.join_group(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_invite group_invites%rowtype;
  v_existing group_members%rowtype;
  v_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  -- Locked so two taps racing each other cannot both slip past max_uses.
  select * into v_invite from group_invites where token = p_token for update;

  if not found then
    raise exception 'That invite link is not valid' using errcode = 'HT003';
  end if;
  if v_invite.revoked_at is not null then
    raise exception 'That invite link was reset' using errcode = 'HT005';
  end if;
  if v_invite.expires_at is not null and v_invite.expires_at <= now() then
    raise exception 'That invite link has expired' using errcode = 'HT004';
  end if;

  select * into v_existing
  from group_members
  where group_id = v_invite.group_id and user_id = v_uid;

  if found and v_existing.left_at is null then
    return v_invite.group_id;
  end if;

  update group_invites
  set use_count = use_count + 1
  where id = v_invite.id
    and (max_uses is null or use_count < max_uses);

  if not found then
    raise exception 'That invite link has been used up' using errcode = 'HT006';
  end if;

  if v_existing.user_id is not null then
    -- Rejoining: the old membership row comes back, history intact.
    update group_members
    set left_at = null, joined_at = now()
    where group_id = v_invite.group_id and user_id = v_uid;
  else
    insert into group_members (group_id, user_id, role)
    values (v_invite.group_id, v_uid, 'member');
  end if;

  select display_name into v_name from profiles where id = v_uid;

  insert into activity_events (group_id, actor_id, type, payload)
  values (
    v_invite.group_id, v_uid, 'member_joined',
    jsonb_build_object('display_name', v_name)
  );

  return v_invite.group_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- leaving and removing
-- ---------------------------------------------------------------------------

-- The bills that stand in the way of someone leaving (spec §12.3: "show
-- exactly which bills block it"). Read by the UI to list them, and by
-- leave_group/remove_member to enforce the rule — one definition, so the
-- message and the check can never disagree.
create or replace function public.group_leave_blockers(
  p_group_id uuid,
  p_user_id uuid default auth.uid()
)
returns table (bill_id uuid, title text, reason text, amount bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'Not a member of that group' using errcode = 'HT001';
  end if;

  return query
    -- Shares they still owe.
    select b.id, b.title, 'you_owe'::text, s.amount
    from bill_shares s
    join bills b on b.id = s.bill_id
    where b.group_id = p_group_id
      and b.status <> 'void'
      and s.user_id = p_user_id
      and s.status in ('unpaid', 'pending_confirmation')
    union all
    -- Bills they fronted that others have not settled.
    select b.id, b.title, 'owed_to_you'::text, sum(s.amount)::bigint
    from bills b
    join bill_shares s on s.bill_id = b.id
    where b.group_id = p_group_id
      and b.status <> 'void'
      and b.paid_by = p_user_id
      and s.user_id <> p_user_id
      and s.status in ('unpaid', 'pending_confirmation')
    group by b.id, b.title;
end;
$$;

create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_blockers text;
  v_others int;
  v_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select role into v_role
  from group_members
  where group_id = p_group_id and user_id = v_uid and left_at is null;

  if v_role is null then
    raise exception 'Not a member of that group' using errcode = 'HT001';
  end if;

  select string_agg(distinct title, ', ')
  into v_blockers
  from public.group_leave_blockers(p_group_id, v_uid);

  if v_blockers is not null then
    raise exception 'Settle up first: %', v_blockers using errcode = 'HT007';
  end if;

  select count(*) into v_others
  from group_members
  where group_id = p_group_id and user_id <> v_uid and left_at is null;

  -- The last person out may be the owner; anyone else must hand it over first.
  if v_role = 'owner' and v_others > 0 then
    raise exception 'Make someone else the owner before you leave'
      using errcode = 'HT008';
  end if;

  update group_members
  set left_at = now()
  where group_id = p_group_id and user_id = v_uid;

  select display_name into v_name from profiles where id = v_uid;

  insert into activity_events (group_id, actor_id, type, payload)
  values (
    p_group_id, v_uid, 'member_left',
    jsonb_build_object('display_name', v_name)
  );
end;
$$;

create or replace function public.remove_member(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
  v_target_role text;
  v_blockers text;
  v_actor_name text;
  v_target_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if p_user_id = v_uid then
    raise exception 'Use Leave group to remove yourself' using errcode = 'HT010';
  end if;

  select role into v_actor_role
  from group_members
  where group_id = p_group_id and user_id = v_uid and left_at is null;

  if v_actor_role not in ('owner', 'admin') then
    raise exception 'Only an owner or admin can remove someone'
      using errcode = 'HT002';
  end if;

  select role into v_target_role
  from group_members
  where group_id = p_group_id and user_id = p_user_id and left_at is null;

  if v_target_role is null then
    raise exception 'They are not in this group' using errcode = 'HT001';
  end if;
  if v_target_role = 'owner' then
    raise exception 'The owner cannot be removed' using errcode = 'HT009';
  end if;
  -- An admin may remove members; only the owner may remove another admin.
  if v_target_role = 'admin' and v_actor_role <> 'owner' then
    raise exception 'Only the owner can remove an admin' using errcode = 'HT002';
  end if;

  select string_agg(distinct title, ', ')
  into v_blockers
  from public.group_leave_blockers(p_group_id, p_user_id);

  if v_blockers is not null then
    raise exception 'They still have unsettled bills: %', v_blockers
      using errcode = 'HT007';
  end if;

  update group_members
  set left_at = now()
  where group_id = p_group_id and user_id = p_user_id;

  select display_name into v_actor_name from profiles where id = v_uid;
  select display_name into v_target_name from profiles where id = p_user_id;

  insert into activity_events (group_id, actor_id, type, payload)
  values (
    p_group_id, v_uid, 'member_removed',
    jsonb_build_object(
      'display_name', v_target_name,
      'removed_by', v_actor_name,
      'user_id', p_user_id
    )
  );
end;
$$;

-- Promote, demote, and hand over ownership (spec §10, Members screen).
--
-- Ownership transfer demotes the outgoing owner in the same call, because the
-- schema allows only one active owner per group.
create or replace function public.set_member_role(
  p_group_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
  v_target_role text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if p_role not in ('owner', 'admin', 'member') then
    raise exception 'Unknown role' using errcode = 'HT010';
  end if;

  select role into v_actor_role
  from group_members
  where group_id = p_group_id and user_id = v_uid and left_at is null;

  select role into v_target_role
  from group_members
  where group_id = p_group_id and user_id = p_user_id and left_at is null;

  if v_actor_role is null then
    raise exception 'Not a member of that group' using errcode = 'HT001';
  end if;
  if v_target_role is null then
    raise exception 'They are not in this group' using errcode = 'HT001';
  end if;
  if v_actor_role not in ('owner', 'admin') then
    raise exception 'Only an owner or admin can change roles'
      using errcode = 'HT002';
  end if;
  -- Handing over ownership, and touching the owner at all, is the owner's call.
  if (p_role = 'owner' or v_target_role = 'owner') and v_actor_role <> 'owner' then
    raise exception 'Only the owner can do that' using errcode = 'HT002';
  end if;

  if v_target_role = p_role then
    return;
  end if;

  if p_role = 'owner' then
    update group_members set role = 'admin'
    where group_id = p_group_id and user_id = v_uid;
  end if;

  update group_members set role = p_role
  where group_id = p_group_id and user_id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- execution grants
-- ---------------------------------------------------------------------------

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.create_group(text, text)',
    'public.create_invite(uuid, int, int, boolean)',
    'public.revoke_invite(uuid)',
    'public.get_invite_preview(text)',
    'public.join_group(text)',
    'public.group_leave_blockers(uuid, uuid)',
    'public.leave_group(uuid)',
    'public.remove_member(uuid, uuid)',
    'public.set_member_role(uuid, uuid, text)',
    'public.generate_invite_token()'
  ]
  loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;
