-- Hati — a default wallet to be paid on (DECISIONS D-66).
--
-- profiles.receive_method_id: where this person wants to be paid unless a
-- bill says otherwise (bills.receive_method_id, D-58). Null means any of
-- their wallets. Deleting the method falls back to any.
--
-- Profiles are updated directly by their owner (…0007 grants UPDATE), so the
-- one rule that matters — it must be your own method — is a trigger, which
-- holds however the row is written.
--
--   HT048  that payment method is not yours  (shared with …0016)

alter table public.profiles
  add column receive_method_id uuid
    references public.payment_methods on delete set null;

create or replace function public.check_profile_receive_method()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.receive_method_id is not null
     and new.receive_method_id is distinct from old.receive_method_id
     and not exists (
       select 1 from payment_methods
       where id = new.receive_method_id and user_id = new.id
     )
  then
    raise exception 'That payment method is not yours' using errcode = 'HT048';
  end if;
  return new;
end;
$$;

create trigger profiles_check_receive_method
  before update of receive_method_id on public.profiles
  for each row
  execute function public.check_profile_receive_method();

revoke all on function public.check_profile_receive_method()
  from public, anon, authenticated;
