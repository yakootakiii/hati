// Hati — delete-account (DECISIONS D-64).
//
// Called by the app, as the signed-in user, from Profile → Delete account.
//
//   1. prepare_account_deletion(), run *as the user* so its HT057 check —
//      no open money — is enforced by the database, not by this function.
//   2. Their files: profile photos and payment QR codes ({user_id}/… in the
//      avatars and payment-qr buckets).
//   3. The sign-in: email replaced so it can be used again, metadata (the
//      name and photo Google sent) cleared, then a soft delete. Soft, because
//      the profile row is referenced by bills other people keep.
//
// Never trusts a user id from the request body: the id comes from the
// caller's own access token.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { publishableKey, secretKey } from '../_shared/keys.ts';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') return json(405, { error: 'POST only' });

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json(401, { error: 'Not signed in' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = publishableKey();
  const serviceKey = secretKey();

  // As the user: RLS and auth.uid() apply.
  const asUser = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userError } = await asUser.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return json(401, { error: 'Not signed in' });

  // 1. App data. Refuses with HT057 while money is still open.
  const { error: prepareError } = await asUser.rpc('prepare_account_deletion');
  if (prepareError) {
    const status = prepareError.code === 'HT057' ? 409 : 500;
    return json(status, { code: prepareError.code, error: prepareError.message });
  }

  // As the system, for what the user's own key cannot do.
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  // 2. Files that are only theirs.
  for (const bucket of ['avatars', 'payment-qr']) {
    const { data: files } = await admin.storage
      .from(bucket)
      .list(user.id, { limit: 1000 });
    const paths = (files ?? []).map((f) => `${user.id}/${f.name}`);
    if (paths.length > 0) {
      const { error } = await admin.storage.from(bucket).remove(paths);
      if (error) console.error(`[delete-account] ${bucket}:`, error.message);
    }
  }

  // 3. The sign-in. Free the email first, so the person can sign up again
  //    later, and drop what Google sent about them.
  const { error: scrubError } = await admin.auth.admin.updateUserById(user.id, {
    email: `deleted-${user.id}@deleted.invalid`,
    email_confirm: true,
    user_metadata: {},
  });
  if (scrubError) {
    console.error('[delete-account] scrub:', scrubError.message);
    return json(500, { error: 'Could not remove your sign-in details' });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(
    user.id,
    true, // soft delete: keeps the row bills point at, blocks sign-in
  );
  if (deleteError) {
    console.error('[delete-account] delete:', deleteError.message);
    return json(500, { error: 'Could not remove your sign-in' });
  }

  return json(200, { deleted: true });
});
