// API keys for Hati's edge functions (DECISIONS D-65).
//
// Projects on Supabase's newer API keys get them as JSON maps —
// SUPABASE_SECRET_KEYS / SUPABASE_PUBLISHABLE_KEYS, e.g. {"default":"sb_…"} —
// and may have the legacy JWT keys (SUPABASE_SERVICE_ROLE_KEY /
// SUPABASE_ANON_KEY) switched off. Prefer the new ones, fall back to legacy.

function fromMap(name: string): string | undefined {
  const raw = Deno.env.get(name);
  if (!raw) return undefined;
  try {
    const map = JSON.parse(raw) as Record<string, string>;
    return map['default'] ?? Object.values(map)[0];
  } catch {
    // Some setups pass a single key rather than a map.
    return raw;
  }
}

/** Full access, bypassing RLS. Server-side only. */
export function secretKey(): string {
  const key = fromMap('SUPABASE_SECRET_KEYS') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!key) throw new Error('No secret API key in the function environment');
  return key;
}

/** The public key, for acting as the signed-in user under RLS. */
export function publishableKey(): string {
  const key = fromMap('SUPABASE_PUBLISHABLE_KEYS') ?? Deno.env.get('SUPABASE_ANON_KEY');
  if (!key) throw new Error('No publishable API key in the function environment');
  return key;
}
