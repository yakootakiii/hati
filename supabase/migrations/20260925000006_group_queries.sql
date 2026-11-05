-- Hati — read helpers for the Groups list (spec §10).
--
-- One round trip for the whole screen: the groups the caller belongs to, their
-- role in each, the member count, and enough profiles to draw the avatar stack.
-- Balances join this in M4, once bills exist.

create or replace function public.get_my_groups()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(entry order by sort_name), '[]'::jsonb)
  from (
    select
      gr.name as sort_name,
      jsonb_build_object(
        'id', gr.id,
        'name', gr.name,
        'photo_path', gr.photo_path,
        'archived_at', gr.archived_at,
        'role', gm.role,
        'joined_at', gm.joined_at,
        'member_count', (
          select count(*) from group_members m
          where m.group_id = gr.id and m.left_at is null
        ),
        'members', (
          -- Just enough for the avatar stack; the Members screen reads the
          -- full list through RLS.
          select coalesce(
            jsonb_agg(
              jsonb_build_object(
                'id', p.id,
                'display_name', p.display_name,
                'avatar_path', p.avatar_path
              )
              order by top.joined_at
            ),
            '[]'::jsonb
          )
          from (
            select m.user_id, m.joined_at
            from group_members m
            where m.group_id = gr.id and m.left_at is null
            order by m.joined_at
            limit 5
          ) top
          join profiles p on p.id = top.user_id
        )
      ) as entry
    from group_members gm
    join groups gr on gr.id = gm.group_id
    where gm.user_id = auth.uid() and gm.left_at is null
  ) rows;
$$;

revoke all on function public.get_my_groups() from public, anon;
grant execute on function public.get_my_groups() to authenticated;
