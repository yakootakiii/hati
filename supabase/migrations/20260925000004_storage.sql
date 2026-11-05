-- Hati — private storage buckets and their policies (spec §5.2).
--
-- Every bucket is private; the app reads through signed URLs. Each object's
-- path starts with the id that scopes it, so a policy can authorise by parsing
-- the first path segment:
--
--   avatars          {user_id}/...
--   payment-qr       {user_id}/...
--   group-photos     {group_id}/...
--   bill-receipts    {group_id}/{bill_id}/...
--   payment-proofs   {group_id}/...
--
-- Paths are user-supplied, so every cast goes through try_uuid, which returns
-- null rather than raising on a malformed segment.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',        'avatars',        false, 5242880,  array['image/jpeg', 'image/png', 'image/webp']),
  ('group-photos',   'group-photos',   false, 5242880,  array['image/jpeg', 'image/png', 'image/webp']),
  ('payment-qr',     'payment-qr',     false, 5242880,  array['image/jpeg', 'image/png', 'image/webp']),
  ('bill-receipts',  'bill-receipts',  false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('payment-proofs', 'payment-proofs', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- avatars and payment QR codes — owned by one user, visible to their groupmates
-- ---------------------------------------------------------------------------

create policy "own-user-scoped objects are readable by groupmates"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('avatars', 'payment-qr')
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.shares_group_with(public.try_uuid((storage.foldername(name))[1]))
    )
  );

create policy "users write only their own avatar and QR"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'payment-qr')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users update only their own avatar and QR"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'payment-qr')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users delete only their own avatar and QR"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'payment-qr')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- group photos — any member reads, owners and admins write
-- ---------------------------------------------------------------------------

create policy "group photos are readable by members"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'group-photos'
    and public.is_group_member(public.try_uuid((storage.foldername(name))[1]))
  );

create policy "group photos are written by owners and admins"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'group-photos'
    and public.has_group_role(
      public.try_uuid((storage.foldername(name))[1]),
      array['owner', 'admin']
    )
  );

create policy "group photos are replaced by owners and admins"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'group-photos'
    and public.has_group_role(
      public.try_uuid((storage.foldername(name))[1]),
      array['owner', 'admin']
    )
  );

create policy "group photos are removed by owners and admins"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'group-photos'
    and public.has_group_role(
      public.try_uuid((storage.foldername(name))[1]),
      array['owner', 'admin']
    )
  );

-- ---------------------------------------------------------------------------
-- receipts and payment proofs — active members of the owning group
--
-- Note this is stricter than table-level access: a former member keeps reading
-- the bill rows they took part in, but loses the images. That is what §5.2
-- asks for ("are an active member of the object's group").
-- ---------------------------------------------------------------------------

create policy "receipts and proofs are readable by group members"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('bill-receipts', 'payment-proofs')
    and public.is_group_member(public.try_uuid((storage.foldername(name))[1]))
  );

create policy "receipts and proofs are uploaded by group members"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('bill-receipts', 'payment-proofs')
    and public.is_group_member(public.try_uuid((storage.foldername(name))[1]))
  );

create policy "receipts and proofs are removed by their uploader"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('bill-receipts', 'payment-proofs')
    and owner = auth.uid()
  );
