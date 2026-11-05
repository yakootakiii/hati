-- Hati — what the send-push edge function may touch (DECISIONS D-65).
--
-- Current Supabase projects grant the API roles no SELECT/INSERT/UPDATE/DELETE
-- on `public` by default (see …0007_grants.sql), and that migration granted
-- the client roles only. send-push runs as service_role, so its first read
-- failed with "permission denied for table notifications".
--
-- Least privilege: exactly what delivery needs, nothing more.
--   notifications  read the row to send; stamp pushed_at
--   device_tokens  read where to send; drop tokens FCM reports dead

grant usage on schema public to service_role;

grant select on public.notifications to service_role;
grant update (pushed_at) on public.notifications to service_role;

grant select, delete on public.device_tokens to service_role;
