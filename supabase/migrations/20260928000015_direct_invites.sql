-- Hati — invite someone by name instead of by link (DECISIONS D-57).
--
-- Invite links need a domain that opens the app (D-07), and there is none. So
-- an owner or admin can search for a person already on Hati and send them an
-- invite directly. It lands in their notifications with Join / Decline, and
-- nothing about the group is visible to them until they accept.
--
--   HT070  that invite does not exist, or is not yours to answer
--   HT071  they are already in the group
--   HT072  that invite was already answered or cancelled
--   HT073  they declined in the last 24 hours
--   HT074  search needs at least two characters

create table public.group_direct_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  invitee_id uuid not null references public.profiles on delete cascade,
  invited_by uuid references public.profiles on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  -- One row per person per group. Re-inviting reuses it, so the history of a
  -- pair is always a single row and "is there a pending invite" is a lookup.
  unique (group_id, invitee_id)
);

create index group_direct_invites_invitee_pending
  on public.group_direct_invites (invitee_id)
  where status = 'pending';

alter table public.group_direct_invites enable row level security;

-- The invitee sees their own; the group's owners and admins see the group's.
-- Plain members do not: who was invited is the inviters' business.
create policy group_direct_invites_select on public.group_direct_invites
  for select to authenticated
  using (
    invitee_id = auth.uid()
    or public.has_group_role(group_id, array['owner', 'admin'])
  );

-- Written only through the RPCs below.
revoke all on public.group_direct_invites from anon;
revoke insert, update, delete on public.group_direct_invites from authenticated;
grant select on public.group_direct_invites to authenticated;

-- ---------------------------------------------------------------------------
-- search
-- ---------------------------------------------------------------------------

-- People an owner or admin might invite to p_group_id.
--
-- Matches display names by substring, or an email exactly. The email is never
-- returned: typing someone's full address is how you pick the right one of
-- three "Juan"s, but the search must not become a way to harvest addresses.
--
-- Profiles are otherwise visible only to groupmates (…0002_rls.sql), so this
-- is a deliberate, narrow hole: name and id, nothing else, twenty at a time,
-- and only to someone who could invite the result anyway.
create or replace function public.search_people(
  p_group_id uuid,
  p_query text
)
returns table (
  id uuid,
  display_name text,
  status text,
  invite_id uuid
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_query text := btrim(coalesce(p_query, ''));
  v_pattern text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if not public.has_group_role(p_group_id, array['owner', 'admin']) then
    raise exception 'Only an owner or admin can invite people'
      using errcode = 'HT002';
  end if;
  if char_length(v_query) < 2 then
    raise exception 'Type at least two characters' using errcode = 'HT074';
  end if;

  -- The query is data, not a pattern: a typed % or _ matches itself.
  v_pattern := '%' || replace(replace(replace(v_query,
    '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
    select
      p.id,
      p.display_name,
      case
        when m.user_id is not null then 'member'
        when i.status = 'pending' then 'pending'
      end,
      case when i.status = 'pending' then i.id end
    from profiles p
    left join auth.users u on u.id = p.id
    left join group_members m
      on m.group_id = p_group_id and m.user_id = p.id and m.left_at is null
    left join group_direct_invites i
      on i.group_id = p_group_id and i.invitee_id = p.id
    where p.id <> v_uid
      and (
        p.display_name ilike v_pattern
        or lower(u.email) = lower(v_query)
      )
    order by
      (lower(u.email) = lower(v_query)) desc nulls last,
      -- Names that start with the query before names that merely contain it.
      (p.display_name ilike substr(v_pattern, 2)) desc,
      p.display_name
    limit 20;
end;
$$;

-- ---------------------------------------------------------------------------
-- invite, answer, cancel
-- ---------------------------------------------------------------------------

-- Sends the invite and its notification. Inviting someone who already has a
-- pending invite is a no-op that returns the same id — a double tap must not
-- notify twice.
create or replace function public.invite_person(
  p_group_id uuid,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_existing group_direct_invites%rowtype;
  v_id uuid;
  v_inviter text;
  v_group_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if not public.has_group_role(p_group_id, array['owner', 'admin']) then
    raise exception 'Only an owner or admin can invite people'
      using errcode = 'HT002';
  end if;
  if p_user_id = v_uid or not exists (select 1 from profiles where id = p_user_id) then
    raise exception 'That person is not on Hati' using errcode = 'HT010';
  end if;
  if exists (
    select 1 from group_members
    where group_id = p_group_id and user_id = p_user_id and left_at is null
  ) then
    raise exception 'They are already in this group' using errcode = 'HT071';
  end if;

  select * into v_existing
  from group_direct_invites
  where group_id = p_group_id and invitee_id = p_user_id
  for update;

  if found then
    if v_existing.status = 'pending' then
      return v_existing.id;
    end if;
    -- A decline is respected for a day, so an invite cannot be used to badger.
    if v_existing.status = 'declined'
       and v_existing.responded_at > now() - interval '24 hours' then
      raise exception 'They declined recently. Try again tomorrow.'
        using errcode = 'HT073';
    end if;

    update group_direct_invites
    set status = 'pending',
        invited_by = v_uid,
        created_at = now(),
        responded_at = null
    where id = v_existing.id;
    v_id := v_existing.id;
  else
    insert into group_direct_invites (group_id, invitee_id, invited_by)
    values (p_group_id, p_user_id, v_uid)
    returning id into v_id;
  end if;

  select display_name into v_inviter from profiles where id = v_uid;
  select name into v_group_name from groups where id = p_group_id;

  -- No route: the invitee cannot open the group until they join. The app
  -- renders Join / Decline from invite_id and status instead, and the answer
  -- rewrites status here so a stale notification stops offering the buttons.
  -- Like member_joined, there is no preference switch for this (D-44).
  insert into notifications (user_id, type, title, body, data)
  values (
    p_user_id,
    'group_invite',
    format('%s invited you to %s', v_inviter, v_group_name),
    'Join to see and split the group''s bills.',
    jsonb_build_object(
      'invite_id', v_id,
      'group_id', p_group_id,
      'group_name', v_group_name,
      'event_type', 'group_invite',
      'status', 'pending'
    )
  );

  return v_id;
end;
$$;

-- Keeps every notification for an invite in step with its answer.
create or replace function public.sync_invite_notifications(
  p_invite_id uuid,
  p_status text
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update notifications
  set data = data || jsonb_build_object('status', p_status),
      read_at = coalesce(read_at, now())
  where type = 'group_invite'
    and data ->> 'invite_id' = p_invite_id::text;
$$;

-- Accepting joins the group the way a link does — rejoining restores the old
-- membership row — and returns the group id so the app can open it.
create or replace function public.respond_to_invite(
  p_invite_id uuid,
  p_accept boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_invite group_direct_invites%rowtype;
  v_status text := case when p_accept then 'accepted' else 'declined' end;
  v_member group_members%rowtype;
  v_name text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;

  select * into v_invite
  from group_direct_invites
  where id = p_invite_id and invitee_id = v_uid
  for update;

  if not found then
    raise exception 'That invite no longer exists' using errcode = 'HT070';
  end if;
  if v_invite.status <> 'pending' then
    raise exception 'That invite was already %', v_invite.status
      using errcode = 'HT072';
  end if;

  update group_direct_invites
  set status = v_status, responded_at = now()
  where id = p_invite_id;

  perform public.sync_invite_notifications(p_invite_id, v_status);

  if not p_accept then
    return v_invite.group_id;
  end if;

  select * into v_member
  from group_members
  where group_id = v_invite.group_id and user_id = v_uid;

  -- Already back in, through a link since the invite went out: nothing to do.
  if found and v_member.left_at is null then
    return v_invite.group_id;
  end if;

  if found then
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

create or replace function public.cancel_direct_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invite group_direct_invites%rowtype;
begin
  select * into v_invite from group_direct_invites where id = p_invite_id for update;

  if not found then
    raise exception 'That invite no longer exists' using errcode = 'HT070';
  end if;
  if not public.has_group_role(v_invite.group_id, array['owner', 'admin']) then
    raise exception 'Only an owner or admin can cancel an invite'
      using errcode = 'HT002';
  end if;
  if v_invite.status <> 'pending' then
    raise exception 'That invite was already %', v_invite.status
      using errcode = 'HT072';
  end if;

  update group_direct_invites
  set status = 'cancelled', responded_at = now()
  where id = p_invite_id;

  perform public.sync_invite_notifications(p_invite_id, 'cancelled');
end;
$$;

-- The caller's open invites, for the Groups tab. An RPC rather than a select
-- because the invitee cannot read the group or the inviter's profile yet.
create or replace function public.get_my_direct_invites()
returns table (
  id uuid,
  group_id uuid,
  group_name text,
  inviter_name text,
  member_count bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    i.id,
    g.id,
    g.name,
    coalesce(p.display_name, 'Someone'),
    (select count(*) from group_members m
     where m.group_id = g.id and m.left_at is null),
    i.created_at
  from group_direct_invites i
  join groups g on g.id = i.group_id
  left join profiles p on p.id = i.invited_by
  where i.invitee_id = auth.uid()
    and i.status = 'pending'
    and g.archived_at is null
  order by i.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- execution grants
-- ---------------------------------------------------------------------------

revoke all on function public.sync_invite_notifications(uuid, text)
  from public, anon, authenticated;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.search_people(uuid, text)',
    'public.invite_person(uuid, uuid)',
    'public.respond_to_invite(uuid, boolean)',
    'public.cancel_direct_invite(uuid)',
    'public.get_my_direct_invites()'
  ]
  loop
    execute format('revoke all on function %s from public, anon', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;
