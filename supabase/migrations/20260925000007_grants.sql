-- Hati — explicit table privileges for the API roles.
--
-- RLS decides which ROWS a caller sees. Table privileges decide whether they
-- may touch the table at all, and the two are separate gates: a policy that
-- allows everything is still refused if the privilege was never granted.
--
-- Current Supabase projects grant the API roles only TRUNCATE, REFERENCES,
-- TRIGGER and MAINTAIN on `public` by default — no SELECT, INSERT, UPDATE or
-- DELETE. Without this migration every client query fails with
-- "permission denied for table ...", whatever the policies say.
--
-- The grants below mirror the policy set in `…0002_rls.sql` exactly. Where a
-- table is written only through an RPC, the client gets SELECT and nothing
-- more, so even a mistaken policy cannot turn into a write.
-- `supabase/tests/grants_test.sql` asserts the two stay in step.

grant usage on schema public to anon, authenticated;

-- Reading is universal; RLS filters the rows.
grant select on all tables in schema public to authenticated;

-- Writes, table by table.
grant update on public.profiles to authenticated;
grant insert, update, delete on public.payment_methods to authenticated;
grant update on public.groups to authenticated;
grant insert, update, delete on public.group_invites to authenticated;
grant insert, delete on public.bill_attachments to authenticated;
grant insert, update, delete on public.comments to authenticated;
grant insert, update, delete on public.recurring_bills to authenticated;
grant insert, update, delete on public.device_tokens to authenticated;
grant insert, update, delete on public.notification_prefs to authenticated;

-- Marking a notification read is the only edit a client may make to it. A
-- column grant is the only way to say that — RLS cannot express "this column
-- only".
grant update (read_at) on public.notifications to authenticated;

-- Deliberately granted nothing beyond SELECT: group_members, bills,
-- bill_shares, bill_items, bill_item_assignees, payments and activity_events
-- change only through security-definer RPCs and triggers (spec §4.1, §5.4).

-- Nothing in Hati is reachable without a session.
revoke all on all tables in schema public from anon;
