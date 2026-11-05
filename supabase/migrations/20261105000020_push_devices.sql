-- Hati — registering phones for push (DECISIONS D-65).
--
-- A phone has one push token. If someone else signed in on it before, the
-- token belongs to them; RLS rightly stops the new user from touching that
-- row, so a plain upsert would fail — and leaving it would send the previous
-- person's notifications to this phone. These move the token to whoever is
-- signed in now, and release it on sign-out.

create or replace function public.register_device_token(
  p_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'HT002';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'A device token is required' using errcode = '22023';
  end if;

  insert into device_tokens (user_id, token, platform)
  values (v_uid, p_token, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- On sign-out: this phone should stop receiving the caller's pushes.
create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.unregister_device_token(text) to authenticated;
