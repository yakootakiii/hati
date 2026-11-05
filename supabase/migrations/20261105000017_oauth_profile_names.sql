-- Hati — profile names for Google sign-ins (DECISIONS D-60).
--
-- The email sign-up form sends display_name in the user metadata. Google
-- sends full_name and name instead, so without this a Google user would be
-- named after their email's local part ("bea.reyes1990").
--
-- Same function as 20260925000003, with two more fallbacks before the email.
-- An existing user who later signs in with Google keeps their profile: the
-- Google identity is linked to the same auth.users row, so this trigger does
-- not fire again.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  chosen_name text;
begin
  chosen_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');
  chosen_name := coalesce(chosen_name, nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''));
  chosen_name := coalesce(chosen_name, nullif(btrim(coalesce(new.raw_user_meta_data ->> 'name', '')), ''));
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
