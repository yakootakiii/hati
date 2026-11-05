-- Hati — the activity feed and comments (spec §4.1, §4.3, §5.3).
--
-- Everywhere else, activity events are emitted by the RPC that made the
-- change: the client has no INSERT privilege on activity_events, and no state
-- change reaches the database except through one of those functions, so an
-- event cannot be skipped or forged (DECISIONS D-40).
--
-- Comments are the exception. They are one of the few tables a client writes
-- directly, so "emit it in the RPC" has no RPC to live in — the event has to
-- come from a trigger, or inserting a comment straight through PostgREST would
-- silently produce no activity.

create or replace function public.on_comment_added()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bill bills%rowtype;
  v_name text;
begin
  select * into v_bill from bills where id = new.bill_id;
  select display_name into v_name from profiles where id = new.author_id;

  insert into activity_events (
    group_id, actor_id, type, bill_id, comment_id, payload
  )
  values (
    v_bill.group_id, new.author_id, 'comment_added', new.bill_id, new.id,
    jsonb_build_object(
      'bill_title', v_bill.title,
      'display_name', v_name,
      -- Denormalised so the feed renders without reading the comment, which
      -- the author may since have deleted.
      'excerpt', left(new.body, 140)
    )
  );

  return new;
end;
$$;

create trigger comments_emit_activity
  after insert on public.comments
  for each row execute function public.on_comment_added();

-- Keeps edited_at honest without trusting the client to set it.
create or replace function public.on_comment_edited()
returns trigger
language plpgsql
as $$
begin
  if new.body <> old.body then
    new.edited_at = now();
  end if;
  return new;
end;
$$;

create trigger comments_mark_edited
  before update on public.comments
  for each row execute function public.on_comment_edited();

-- ---------------------------------------------------------------------------
-- ordering
--
-- now() is the transaction timestamp, so every event written by one request
-- shared a created_at — and two events from a single RPC, such as
-- payment_confirmed followed by bill_settled, could come back in either order.
-- clock_timestamp() advances within a transaction, so statements are
-- distinguishable. The id is kept as a final tiebreaker so the order is total
-- rather than merely usually-right (DECISIONS D-41).
-- ---------------------------------------------------------------------------

alter table public.activity_events
  alter column created_at set default clock_timestamp();

-- ---------------------------------------------------------------------------
-- the feed
-- ---------------------------------------------------------------------------

-- One function for both feeds (spec §10): pass a group for the group tab,
-- omit it for the merged feed across every group the caller is in.
--
-- `p_before` pages backwards through time, which is stable under inserts in a
-- way that OFFSET is not.
create or replace function public.get_activity_feed(
  p_group_id uuid default null,
  p_limit int default 30,
  p_before timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(entry order by sort_at desc, sort_id desc), '[]'::jsonb)
  from (
    select
      e.created_at as sort_at,
      e.id as sort_id,
      jsonb_build_object(
        'id', e.id,
        'group_id', e.group_id,
        'group_name', g.name,
        'actor_id', e.actor_id,
        'actor_name', coalesce(p.display_name, 'Someone'),
        'type', e.type,
        'bill_id', e.bill_id,
        'payment_id', e.payment_id,
        'comment_id', e.comment_id,
        'payload', e.payload,
        'created_at', e.created_at
      ) as entry
    from activity_events e
    join groups g on g.id = e.group_id
    left join profiles p on p.id = e.actor_id
    where e.group_id in (
      select group_id from group_members
      where user_id = auth.uid() and left_at is null
    )
      and (p_group_id is null or e.group_id = p_group_id)
      and (p_before is null or e.created_at < p_before)
    order by e.created_at desc, e.id desc
    limit least(coalesce(p_limit, 30), 100)
  ) rows;
$$;

revoke all on function public.get_activity_feed(uuid, int, timestamptz)
  from public, anon;
grant execute on function public.get_activity_feed(uuid, int, timestamptz)
  to authenticated;

-- ---------------------------------------------------------------------------
-- realtime
--
-- Postgres Changes only delivers rows for tables in Supabase's publication,
-- and it still applies RLS per subscriber — so adding a table here widens what
-- can be watched, never who may see it (spec §4.3).
--
-- Guarded because the publication is a Supabase fixture: the local test
-- harness has no such thing.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    raise notice 'no supabase_realtime publication; skipping (local harness)';
    return;
  end if;

  foreach t in array array[
    'bills', 'bill_shares', 'payments', 'comments', 'activity_events'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
