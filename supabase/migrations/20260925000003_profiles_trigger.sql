-- Hati — profile bootstrap (spec §5.1: "created by trigger on signup").
--
-- The client never inserts into profiles; it has no privilege to (see the RLS
-- migration). Signing up is the only way a profile comes into existence, which
-- keeps auth.users and public.profiles exactly 1:1.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  chosen_name text;
begin
  -- The sign-up form sends display_name in the user metadata. Fall back to the
  -- email's local part so a profile always satisfies the 1–50 char constraint,
  -- even for users created from the dashboard or a seed script.
  chosen_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');
  chosen_name := coalesce(chosen_name, nullif(split_part(coalesce(new.email, ''), '@', 1), ''));
  chosen_name := coalesce(chosen_name, 'Hati user');
  chosen_name := left(chosen_name, 50);

  insert into public.profiles (id, display_name)
  values (new.id, chosen_name)
  on conflict (id) do nothing;

  insert into public.notification_prefs (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
