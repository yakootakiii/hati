// Hati — send-push (spec §7.1, DECISIONS D-08, D-65).
//
// Invoked by a Database Webhook on `notifications` INSERT. Delivers the row
// to the recipient's phones through Firebase Cloud Messaging (HTTP v1),
// records `pushed_at`, and drops tokens FCM says are dead.
//
// Who is notified, and whether their settings allow it, is decided in SQL
// by the fan-out trigger (covered by supabase/tests/notifications_test.sql).
// This function only delivers what that trigger already wrote.
//
// Secrets (supabase secrets set …):
//   FCM_SERVICE_ACCOUNT   the Firebase service-account key, the whole JSON
//   PUSH_WEBHOOK_SECRET   any long random string, also set as the webhook's
//                         x-hati-webhook-secret header
//
// Without FCM_SERVICE_ACCOUNT it logs instead of sending, so the pipeline can
// still be watched end to end.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';

interface NotificationRow {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown> | null;
}

interface DeviceToken {
  token: string;
  platform: 'ios' | 'android' | 'web';
}

/// Where web notifications open (D-72): the web app, with a hash route.
const WEB_APP = 'https://hati-a1a23.web.app/app/';

interface SendOutcome {
  token: string;
  ok: boolean;
  /** FCM said this token no longer exists and should be deleted. */
  unregistered: boolean;
}

interface PushSender {
  send(token: DeviceToken, notification: NotificationRow): Promise<SendOutcome>;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

class LoggingSender implements PushSender {
  send(token: DeviceToken, n: NotificationRow): Promise<SendOutcome> {
    console.log(
      `[send-push] would send to ${token.platform} ${token.token.slice(0, 12)}…: ` +
        `${n.title} — ${n.body}`,
    );
    return Promise.resolve({ token: token.token, ok: true, unregistered: false });
  }
}

// ── Google OAuth from the service account ─────────────────────────────────
//
// FCM HTTP v1 takes a short-lived OAuth token. It is minted here from the
// service account's private key (a signed JWT exchanged at Google's token
// endpoint) and cached until shortly before it expires.

let cachedToken: { value: string; expiresAt: number } | null = null;

const base64url = (bytes: Uint8Array | string): string => {
  const raw = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes;
  let binary = '';
  for (const b of raw) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(
    JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claims}`;
  const key = await importPrivateKey(account.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );
  const assertion = `${unsigned}.${base64url(signature)}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google token exchange failed: ${response.status} ${await response.text()}`);
  }
  const { access_token, expires_in } = await response.json();
  cachedToken = { value: access_token, expiresAt: now + Number(expires_in ?? 3600) };
  return access_token;
}

class FcmSender implements PushSender {
  constructor(private readonly account: ServiceAccount) {}

  async send(token: DeviceToken, n: NotificationRow): Promise<SendOutcome> {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${await accessToken(this.account)}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: token.token,
            notification: { title: n.title, body: n.body },
            // Strings only: FCM rejects other types. `route` is what the app
            // opens when the notification is tapped.
            data: Object.fromEntries(
              Object.entries(n.data ?? {}).map(([k, v]) => [k, String(v)]),
            ),
            android: {
              priority: 'high',
              // One notification per bill: a newer one replaces the older.
              notification: { tag: String(n.data?.route ?? n.id) },
            },
            // The web app (D-72): the browser shows it, and a tap opens the
            // page it is about in Hati's web app.
            ...(token.platform === 'web'
              ? {
                webpush: {
                  fcm_options: {
                    link: `${WEB_APP}#${String(n.data?.route ?? '/')}`,
                  },
                  notification: {
                    icon: `${WEB_APP}icons/Icon-192.png`,
                    tag: String(n.data?.route ?? n.id),
                  },
                },
              }
              : {}),
          },
        }),
      },
    );

    if (response.ok) return { token: token.token, ok: true, unregistered: false };

    // 404 UNREGISTERED and 400 INVALID_ARGUMENT both mean the token is dead.
    const unregistered = response.status === 404 || response.status === 400;
    console.error(`[send-push] ${response.status} for ${token.token.slice(0, 12)}…`);
    return { token: token.token, ok: false, unregistered };
  }
}

function buildSender(): PushSender {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) {
    console.warn('[send-push] FCM_SERVICE_ACCOUNT is not set; logging instead');
    return new LoggingSender();
  }
  return new FcmSender(JSON.parse(raw) as ServiceAccount);
}

Deno.serve(async (request: Request) => {
  // Only our own webhook may trigger a push. The function is deployed with
  // JWT verification off, so this shared secret is the gate.
  const secret = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (!secret || request.headers.get('x-hati-webhook-secret') !== secret) {
    return new Response('forbidden', { status: 403 });
  }

  const payload = await request.json();
  if (payload?.table !== 'notifications' || payload?.type !== 'INSERT') {
    return new Response('ignored', { status: 200 });
  }

  // service_role: this runs as the system, not as the recipient.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    secretKey(),
    { auth: { persistSession: false } },
  );

  // Re-read the row rather than trusting the request body: a push can only
  // ever say what the database actually holds.
  const { data: notification, error: readError } = await supabase
    .from('notifications')
    .select('id, user_id, type, title, body, data, pushed_at')
    .eq('id', payload?.record?.id)
    .maybeSingle();

  if (readError) {
    // A failed read is not a missing row: say which, so the webhook log in
    // net._http_response shows the real cause.
    console.error('[send-push] could not read the notification', readError);
    return new Response(`read failed: ${readError.message}`, { status: 500 });
  }
  if (!notification) {
    return new Response('no such notification', { status: 200 });
  }
  if (notification.pushed_at) {
    return new Response('already pushed', { status: 200 });
  }

  const { data: tokens, error } = await supabase
    .from('device_tokens')
    .select('token, platform')
    .eq('user_id', notification.user_id);

  if (error) {
    console.error('[send-push] could not read device tokens', error);
    return new Response('error', { status: 500 });
  }
  if (!tokens || tokens.length === 0) {
    // Nothing to push to is not a failure: the row still shows in the app.
    return new Response('no devices', { status: 200 });
  }

  const sender = buildSender();
  const outcomes = await Promise.all(
    (tokens as DeviceToken[]).map((t) => sender.send(t, notification as NotificationRow)),
  );

  const dead = outcomes.filter((o) => o.unregistered).map((o) => o.token);
  if (dead.length > 0) {
    await supabase.from('device_tokens').delete().in('token', dead);
  }

  if (outcomes.some((o) => o.ok)) {
    await supabase
      .from('notifications')
      .update({ pushed_at: new Date().toISOString() })
      .eq('id', notification.id);
  }

  return new Response(
    JSON.stringify({ sent: outcomes.filter((o) => o.ok).length, pruned: dead.length }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
