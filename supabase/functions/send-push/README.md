# send-push

Delivers each new `notifications` row to the recipient's phones through
Firebase Cloud Messaging (spec §7.1, DECISIONS D-08, D-65).

Who gets a notification, and whether their settings allow it, is decided by
the `fan_out_notifications` trigger and tested in
`supabase/tests/notifications_test.sql`. This function only delivers.

## Status

Working: verified end to end on 5 November 2026. The phone side (token
registration, taps opening the right screen) is covered by
`test/core/push/`; the service role's table access by
`supabase/tests/grants_test.sql`.

## Setting it up

1. **Firebase project** — console.firebase.google.com → Add project → add an
   Android app with package name `com.hati.hati`. Download
   `google-services.json` into `android/app/`.
2. **Service account key** — Project settings → Service accounts →
   Generate new private key.
3. **Secrets** (keep the key file out of git):
   ```
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat path/to/key.json)"
   supabase secrets set PUSH_WEBHOOK_SECRET="$(openssl rand -hex 32)"
   ```
   Note the webhook secret — step 5 needs it.
4. **Deploy:** `supabase functions deploy send-push`
5. **Webhook** — Supabase dashboard → Database → Webhooks → Create:
   table `notifications`, event `Insert`, type *Supabase Edge Functions*,
   function `send-push`, and an HTTP header
   `x-hati-webhook-secret: <the secret from step 3>`.

Without `FCM_SERVICE_ACCOUNT` the function logs instead of sending, and
without the right header it answers 403.
