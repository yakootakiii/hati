# DECISIONS

Per `bill-splitting-app-spec.md`: "where something is not specified, choose the simplest
option consistent with this spec and note the decision here."

Each entry records the decision, why, and — where it patches a gap in the spec — what
the spec actually says.

---

### D-01 — App / package identity
**Decision:** Dart package `hati`, application id `com.hati.app`, display name "Hati".
**Why:** Spec §1 names the app Hati; no domain is owned yet (D-07), so the id is a
placeholder that can be changed before any store submission. Revisit if the final
domain differs.

### D-02 — `bills.itemized_extras` is a real column
**Spec gap:** §5.1 mentions `bills.itemized_extras jsonb` only in a trailing SQL
comment, not in the `bills` DDL.
**Decision:** Add `itemized_extras jsonb not null default '{}'::jsonb` to `bills`,
with a check that its values are non-negative integers and its keys are a subset of
`service_charge`, `tax`, `discount`.
**Why:** §6.3 itemized validation cannot run without it.

### D-03 — `bill_shares.last_reminded_at`
**Spec gap:** §7.2 says reminders "track in `bill_shares.last_reminded_at`", but the
§5.1 DDL has no such column.
**Decision:** Add `last_reminded_at timestamptz` to `bill_shares`. The same column
backs both the 3/7-day cron reminders and the 24h Nudge rate limit.

### D-04 — Migration ordering for the recurring FK
**Spec gap:** `bills.recurring_template_id` references `recurring_bills`, which §5.1
defines after `bills`.
**Decision:** Create both tables first, then add the FK with
`alter table bills add constraint ... foreign key (recurring_template_id)`.
**Why:** Avoids a forward reference; keeps `0001_init.sql` runnable top to bottom.

### D-05 — Rounding order for itemized extras
**Spec gap:** §6.3 says extras are applied "proportionally to each person's item
subtotal (remainder rule)" but does not fix the order, which changes who gets the
leftover centavo.
**Decision:** Apply each extra as its own largest-remainder distribution over the
per-person item subtotals, in the fixed order `service_charge`, then `tax`, then
`discount`. Ties broken by participant order, as in §6.2.
**Why:** §14 requires Dart and SQL to match exactly; an unspecified order is the
likeliest place for them to drift. Pinned by `split_vectors.json`.

### D-06 — `payments.amount` always equals the share amount
**Spec note:** §5.1 comments "v1: always equals the share amount (no partials)" and
§15 defaults partial payments to "No in v1".
**Decision:** Enforce in `mark_share_paid` and `record_payment_received` rather than
as a table check, since the constraint is cross-table.

### D-07 — No custom domain yet → placeholder links — **BLOCKER for §14.1**
**Decision:** Use `https://hati.app/join/<token>` as the canonical link format from
§8 and additionally register a custom URL scheme `hati://join/<token>` for
development. App Links / Universal Links verification files are not deployed.
**Consequence:** "invite link opens the installed app" cannot be accepted until a
domain is owned and serving `assetlinks.json` and `apple-app-site-association`.
The in-app join flow is fully testable via the custom scheme.

### D-08 — No Firebase project yet → push stubbed — **BLOCKER for §14.6**
**Decision:** Build `notifications` fan-out triggers, preferences and the
`send-push` edge function in full, but behind a sender interface whose FCM
implementation is unconfigured. Tests use a fake sender.
**Consequence:** Notification *rows* are verifiable; *delivery* is not.

### D-09 — No Apple Developer account yet — **BLOCKER for §14.1 (iOS half)**
**Decision:** iOS work targets the Simulator. Universal Links and physical-device
testing are deferred.
**Note:** Xcode 26.0.1 currently reports no installed Simulator runtimes — install
one before M1 iOS testing.

### D-10 — Hosted Supabase, no local Docker stack
**Decision:** Develop against a hosted Supabase project; apply schema with
`supabase db push` from versioned files in `supabase/migrations/`.
**Why:** Docker is not installed on this machine and the hosted path matches
production. Trade-off: no instant `db reset`, so migrations must be forward-only
and each one independently reversible by a follow-up migration.

### D-11 — JDK for Android
**Decision:** The machine's default JDK is 25. Flutter 3.35 warned about this;
after the upgrade to 3.47.5 (D-12) `flutter doctor` no longer does. Left as-is.
**Re-check at the first Android build** — if Gradle objects, point Flutter at a
17 or 21 JDK with `flutter config --jdk-dir` rather than downgrading the system
default, so the user's other toolchains are undisturbed.

### D-12 — Upgraded Flutter 3.35.4 → 3.47.5
**Decision:** Upgraded the machine's Flutter stable SDK, with the user's approval.
**Why:** 3.35.4 (Dart 3.9.2) could not resolve the dependency set spec §3 requires
— the current `riverpod_annotation`/`riverpod_generator`, `freezed` 3 and
`json_serializable` all need Dart ≥3.12 and analyzer ≥12. Pub's own resolver
recommended 3.47.5. The alternatives were pinning a year-old dependency set or
dropping Riverpod codegen, both of which diverge from the spec.
**Note:** this is a machine-wide SDK change; other Flutter projects on this
machine now build against 3.47.5.

### D-13 — No `riverpod_lint` / `custom_lint`
**Decision:** Omitted from dev dependencies.
**Why:** `custom_lint` pins `analyzer` to a range that cannot coexist with
`json_serializable` ^6.8.0 and `freezed_annotation` ^3.1.0 in this resolution.
Riverpod's runtime and codegen are unaffected — only the extra lint rules are
missing.
**Revisit** when `custom_lint` catches up to analyzer 13+.

### D-14 — Minimum password length is 8
**Spec gap:** §2 requires email + password auth but never states a password rule.
**Decision:** 8 characters, validated client-side in `AuthValidators.password`.
Supabase's own default minimum is 6.
**Why:** The shortest length still worth calling a password. The log-in form
deliberately uses a laxer rule (non-empty only) so an account created before any
rule change can still sign in.

### D-15 — `publishableKey`, not `anonKey`
**Decision:** `Supabase.initialize` is called with `publishableKey`. The build
reads `SUPABASE_PUBLISHABLE_KEY`, falling back to `SUPABASE_ANON_KEY`.
**Why:** `anonKey` is deprecated in supabase_flutter 2.17 and slated for removal.
The fallback keeps older projects, which only issue an anon key, working.

### D-16 — Keys come from `--dart-define-from-file`, not a bundled .env
**Decision:** `SupabaseConfig` reads compile-time `String.fromEnvironment`
values; the app is run with `flutter run --dart-define-from-file=.env`.
**Why:** No secrets file ships inside the bundle and no runtime file read is
needed. A build with neither value set still boots, onto `ConfigMissingScreen`,
so the app is runnable before a project exists.

### D-17 — Constraints added beyond the spec's DDL
The spec's §5.1 listing leaves these implicit; each one is enforced in the
schema so no RPC can forget it:
- `payment_methods_one_default` — at most one default payment method per user.
- `group_members_single_owner` — at most one active owner per group, which is
  what makes "owner must transfer ownership first" (§7 `leave_group`) meaningful.
- `payments_one_pending_per_share` — at most one pending payment per share, so a
  double tap on "I've paid" is a no-op at the database level (§12.9).
- `bills_recurring_once_per_date` — the §7.1 idempotency index, added now rather
  than in M9 because it is schema.
- `groups.name` and `bills.title` length bounds, mirroring the display_name rule.

### D-18 — RLS uses ENABLE, never FORCE
**Decision:** Tables get `enable row level security` only.
**Why:** `force` subjects the table owner to policies too — and the owner is
exactly who the `security definer` helpers run as. `is_group_member` would then
trigger `group_members`' own policy, which calls `is_group_member`, recursing
until the stack gives out. Verified: the suite passes with ENABLE.

### D-19 — SQL is tested against a local throwaway Postgres
**Decision:** `tool/run_sql_tests_local.sh` spins up a temporary Postgres 17
cluster, applies `supabase/tests/local_supabase_shim.sql` (minimal stand-ins for
`auth.users`, `auth.uid()`, `storage.objects` and `storage.foldername`), runs
every migration, then runs the RLS suite — no project and no Docker.
**Why:** D-10 rules out a local Supabase stack, but shipping unrun SQL is worse.
**Limit:** the shim is a model, not the real thing.
**Resolved 2026-09-25:** all migrations applied to the live project
(`nwxcwolgxikzevmisukp`, ap-southeast-1, Postgres 17.6) and the full suite —
109 assertions — passes there. `storage.objects` does expose `owner`.
**Two real differences surfaced that the shim had masked: D-26 and D-27.**
Both were fixed by changing the shim to mirror production, then fixing the
schema. The rule this establishes: when the shim and a real project disagree,
the shim is the thing that is wrong.

### D-20 — RPC failures use custom SQLSTATEs, not message matching
**Decision:** The group RPCs raise `HT001`–`HT010` (listed at the top of
`20260925000005_groups_rpc.sql`). PostgREST passes the code through as
`PostgrestException.code`, and `GroupFailure.fromCode` maps it.
**Why:** Copy on either side can then change freely. Matching on message text
would make every wording tweak a potential client break.

### D-21 — An unusable invite reveals nothing about the group
**Decision:** `get_invite_preview` returns only `{valid: false, reason}` for a
revoked, expired, exhausted or unknown token — no group name, photo or member
count.
**Why:** `get_invite_preview` is callable by any signed-in user, member or not.
Showing the group behind a revoked link would make revoking it pointless.
Asserted in both the SQL and widget suites.

### D-22 — `set_member_role` added
**Spec gap:** §7's function table has no role-changing RPC, but §10's Members
screen requires promote / demote, and §7's `leave_group` says "Owner must
transfer ownership first" — which needs a way to transfer.
**Decision:** `set_member_role(group_id, user_id, role)`. Promoting to owner
demotes the outgoing owner in the same call, since the schema permits one
active owner per group (D-17).
**Note:** emits no activity event — §5.3 has no type for a role change.

### D-23 — Who may remove and promote whom
**Spec gap:** §7 says `remove_member` is "owner/admin" without saying what an
admin may do to another admin.
**Decision:** An admin may remove or demote members; only the owner may touch
an admin or the owner, and only the owner may hand ownership over. The owner is
never removable — they leave by transferring first.
**Why:** Stops an admin from removing their peers or the owner, which would
turn the admin role into an ownership takeover.

### D-24 — `get_my_groups` read RPC
**Decision:** The Groups list reads one RPC returning each group with the
caller's role, the member count and up to five profiles for the avatar stack.
**Why:** One round trip instead of a groups query plus a members query plus a
profiles query. M4 extends the same function with balances.

### D-25 — The money check strips strings and comments before matching
**Decision:** `tool/check_no_float_money.sh` delegates to
`tool/check_no_float_money.py`, which blanks string literals and comments,
skips generated files, and allows the `(json[...] as num).toInt()` idiom.
**Why:** The original grep flagged the `/` in `'https://hati.app/join/...'` and
`double` inside comments. A check that cries wolf gets switched off. Verified
in both directions: it still catches `double`, `num`, `.toDouble()` and
non-truncating division.

### D-26 — Invite tokens come from `gen_random_uuid()`, not pgcrypto
**Found by:** `supabase db push` failing on the live project with
`function gen_random_bytes(integer) does not exist`.
**Cause:** Supabase installs pgcrypto into the `extensions` schema, not
`public`, so an unqualified `gen_random_bytes` does not resolve — and Postgres
validates SQL-language function bodies at creation time, so this failed at
`CREATE FUNCTION`, not at first call. The local shim installs pgcrypto into
`public`, which is why the suite passed locally.
**Decision:** `generate_invite_token()` concatenates two `gen_random_uuid()`
values with the hyphens stripped: 64 URL-safe characters, ~244 bits of
randomness, against the 22 characters the spec asks for.
**Why not schema-qualify:** `gen_random_uuid()` is core Postgres 13+, so
dropping the extension dependency removes the whole class of problem rather
than papering over one instance of it.
**Note:** `…0001_init.sql` still carries a `create extension if not exists
pgcrypto`, left alone because that migration has already applied. It is a
no-op on Supabase and nothing depends on it any more.

### D-27 — Table privileges must be granted explicitly
**Found by:** the first run of the SQL suite against the live project, which
failed immediately with `permission denied for table groups`.
**Cause:** current Supabase projects do not auto-grant DML on `public` to the
API roles. `pg_default_acl` shows `anon=Dxtm` / `authenticated=Dxtm` for
`public` — TRUNCATE, REFERENCES, TRIGGER, MAINTAIN — with no
SELECT/INSERT/UPDATE/DELETE, while the `storage` schema still carries the full
`arwdDxtm`. The local shim reproduced the *older* behaviour of granting ALL,
so 71 local assertions passed while **every client query against the real
project would have failed**, whatever the policies said. The targeted `REVOKE`s
in `…0002_rls.sql` were silent no-ops — nothing can be revoked that was never
granted.
**Decision:** `…0007_grants.sql` grants privileges explicitly, mirroring the
policy set: SELECT to `authenticated` on every table, targeted write grants
where a policy allows a direct write, a column grant for `notifications.read_at`,
and nothing beyond SELECT on the seven RPC-only tables.
**Guard:** `supabase/tests/grants_test.sql` pins the matrix — every table's
privileges, that no public table is missing from the matrix, that RLS is on
everywhere, that `anon` reaches nothing, and that the RPCs are executable by
`authenticated` but not `anon`. Verified to fail (`activity_events: -none-`)
when the grants migration is removed, so it cannot pass vacuously.
**Why two gates:** privileges and RLS are independent. Granting only SELECT on
the RPC-only tables means even a mistaken policy cannot become a client write.

### D-28 — Extras on an all-free itemized bill are shared equally
**Spec gap:** §6.3 spreads service charge, tax and discount "proportionally to
each person's item subtotal". When every item is ₱0 there are no proportions
to spread by, and the spec does not say what happens.
**Decision:** fall back to an equal split of the extra. The alternative —
refusing the bill — would reject a real case (a free meal with a service
charge) for no good reason.
**Where:** `_spreadOverSubtotals` in Dart, `split_spread` in SQL, identically.

### D-29 — A generated differential corpus, with Dart as the reference
**Decision:** `tool/gen_fuzz_vectors.dart` generates 240 random cases across
all five modes from a fixed seed, computes each with the Dart engine, and
writes `supabase/tests/split_vectors_fuzz.json`. Both suites read it: SQL must
reproduce every answer, and Dart must still produce the committed answers.
**Why:** §14 requires Dart and SQL to "match exactly". The 26 hand-written
vectors cover the cases the spec names; they cannot cover the remainder rule's
edges across hundreds of weight combinations. 254 vectors now pass in both
engines.
**Why committed rather than generated at test time:** the corpus is reviewable
in a diff, and pinning it means changing either engine without regenerating
turns a suite red instead of silently moving the goalposts.
**Regenerate** with `dart run tool/gen_fuzz_vectors.dart` — and only alongside
a deliberate engine change.

### D-30 — Split failures use their own SQLSTATE range
**Decision:** `HT020`–`HT029`, with the failure's slug as the exception
message. The slug is the wire name shared by `SplitFailure` in Dart, the SQL
engine, and the `error` field in the vectors — so one name identifies a failure
in all three places.
**Why a separate range from HT001–HT010 (D-20):** split failures are input
validation the client can prevent, and M4's Add-bill screen maps them to inline
field errors rather than to the generic failure copy the group RPCs use.

### D-31 — Participant order is the server's to decide
**Why it matters:** the order participants are listed in decides who receives a
leftover centavo (spec §6.2). If the client sent them in tap order and the
server used join order, the preview and the stored shares would disagree by a
centavo — rarely, unreproducibly, and only for some bills.
**Decision:** `canonical_participants` re-sorts by `group_members.joined_at`,
then `user_id`, inside every bill RPC; `canonicalMemberOrder` does the same in
Dart before the preview runs. The server's order wins either way.
**Tested:** a bill whose participants are sent in reverse still gives the
leftover centavo to the earliest joiner.

### D-32 — In itemized mode the total is derived, not typed
**Spec:** §6.3 requires `subtotal + service_charge + tax − discount` to equal
`bills.total_amount`, and rejects the bill otherwise.
**Decision:** the Add-bill screen computes the total from the items and extras
and shows the amount field as read-only, rather than asking for it and then
refusing the bill.
**Why:** it removes a whole failure class from the UI — `items_total_mismatch`
becomes unreachable through the form. The engine still enforces it, because
the RPC is reachable without the form.

### D-33 — `initializeDateFormatting('en_PH')` before `runApp`
**Found by:** a widget test that rendered the Bills tab and got
`LocaleDataException` from `DateFormat.yMMMd('en_PH')`.
**Cause:** intl compiles in only `en_US` date symbols; any other locale must be
loaded at startup. Number formatting is unaffected, which is why `Money.format`
had worked all along and hid the gap.
**Decision:** `main()` awaits `initializeDateFormatting('en_PH')`, and the test
harness does the same so the two boot the same way.
**Note:** this was a real crash on the Bills tab and Bill detail, not a test
artifact.

### D-34 — Wallet deep links are best-effort, with a store fallback
**Spec:** §9 asks for an "Open GCash / Open Maya" button, says to verify the
schemes at build time, and requires a store fallback when launching fails. It
also rules out prefilling the amount — there is no supported public API.
**Decision:** `WalletLauncher` tries `gcash://` and `mayaph://`, and falls back
to the Play Store or App Store listing when the scheme does not resolve.
**Caveat:** these schemes are published by the wallets and do change. Treat
them as best known rather than guaranteed, and re-check before release.

### D-35 — Action notifiers are keepAlive, and inline errors are local
**Found by:** a widget test tapping "Record cash" threw
`UnmountedRefException` — and `ref.keepAlive()` inside the action threw too,
because the provider was *already* disposed before the action began.
**Cause:** the action notifiers were `autoDispose`, and nothing watches them
between taps. A confirmation dialog's await is far longer than the autoDispose
window, so the notifier captured before the dialog was dead by the time the
user confirmed.
**Decision:** the four action notifiers (`BillActions`, `GroupActions`,
`SettlementActions`, `PaymentMethodActions`) are `keepAlive: true` — they are
app-level handlers, not per-screen state.
**And:** because keepAlive means an error would otherwise linger and surface on
an unrelated screen, each notifier exposes `lastError`, and screens that show
an inline banner keep that message in their own local state. Nothing reads a
shared error after the fact.
**Note:** this was latent in M2's Members screen and M4's void flow as well —
`ref` used after an await in a stateless `ConsumerWidget` that the action's own
invalidation unmounts. All call sites now capture the notifier and the
`ScaffoldMessengerState` before awaiting.

### D-36 — Receipts upload after the bill exists, not before
**Constraint:** a receipt lives at `bill-receipts/{group_id}/{bill_id}/…`
(spec §5.2), and the bill id is the server's to mint — `create_bill` returns
it. So the path cannot be known before the bill exists.
**Decision:** save creates the bill, then uploads, then records the
attachments. Spec §12.11 says "bill save waits for uploads", and it does: the
button stays busy and shows "Uploading receipt 2 of 3" throughout.
**Trade-off:** a failed upload leaves the bill in place with fewer receipts,
and the error says so. The alternative — rolling the bill back — would throw
away the split the user just built over a transient network error.
**Note:** `create_bill` still accepts `attachment_paths` for callers that do
know their paths up front, such as the recurring generator in M9.

### D-37 — Compression computes its own target dimensions
**Spec §3:** max 1600px on the long edge, JPEG q80.
**Decision:** `PlatformImageService.compress` decodes the image, works out the
scaled width and height itself, and passes both to the compressor.
**Why:** flutter_image_compress thinks in `minWidth`/`minHeight` — a *lower*
bound — while the spec constrains the *long edge*. Passing exact values makes
the result the same whatever the library's own scaling rule does, instead of
depending on a behaviour that could change under us.
**Fallback:** a format the compressor cannot read is uploaded as-is rather
than dropped; the bucket's size limit still applies.

### D-38 — Upload progress is counted in files, not bytes
**Spec §12.11** asks to "show upload progress".
**Decision:** the save button reports "Uploading receipt 2 of 3".
**Why:** supabase_flutter's `uploadBinary` does not expose byte-level
progress. Per-file progress is honest about what is known; a fake percentage
bar would not be.

### D-39 — An attachment is labelled in every state
**Found by:** a widget test looking for the semantics label on a receipt found
nothing, because `Image.network` only carries `semanticLabel` once the image
has loaded — and in a test it never does.
**Decision:** `AttachmentImage` wraps all three states (loading, error,
loaded) in one `Semantics` node.
**Why it matters beyond the test:** a receipt that fails to load, on a bad
connection, would otherwise be an unlabelled blank to a screen reader. Spec
§11 asks for semantics labels on image-only content, and "only when it loads"
is not that.

### D-40 — Events come from the RPCs, except for comments
**Spec §4.1** says the activity feed is "generated by database triggers, not by
the client, so they can't be skipped or spoofed."
**Decision:** every event except `comment_added` is emitted by the RPC that
made the change; `comment_added` comes from a trigger on `comments`.
**Why the split:** the property that matters is that an event cannot be skipped
or forged. For bills, shares, payments and membership, the client has no write
privilege at all — the only way to change them is through an RPC, and every RPC
emits. Comments are different: they are one of the few tables a client writes
directly, so "emit it in the RPC" has no RPC to live in. Inserting a comment
through PostgREST would produce no activity at all, which is exactly the
skippable case. Hence the trigger, and a test that inserts a comment directly
and asserts the event appears.
**Also from the RPC side:** the payload is denormalised with titles, amounts
and names, which the RPC has to hand and a trigger would have to re-read.

### D-41 — Event ordering uses `clock_timestamp()`, not `now()`
**Found by:** a feed test asserting "newest first" failed, because every event
written in one transaction shared a `created_at`.
**Cause:** `now()` is the *transaction* timestamp. Two events from a single RPC
— `payment_confirmed` followed by `bill_settled`, say — were indistinguishable,
so the feed could show the bill settling before the payment that settled it.
**Decision:** `activity_events.created_at` defaults to `clock_timestamp()`,
which advances within a transaction, and the feed orders by
`(created_at desc, id desc)` so the order is total rather than merely
usually-right.
**Note:** this was a real ordering bug, not a test artifact. The test only
surfaced it because a test transaction makes every timestamp collide.

### D-42 — Realtime lives exactly as long as the screen
**Spec §4.3** asks for subscriptions only while the relevant screen is open.
**Decision:** `groupRealtime` and `billRealtime` are autoDispose providers that
open a channel in `build` and close it in `onDispose`. A screen `watch`es one;
leaving the screen disposes the provider, which closes the channel. There is no
lifecycle code in the widgets to get wrong.
**Tested** through a `RealtimeService` interface: the fake records what was
watched, what was closed, and can fire a change by hand — so the subscribe,
unsubscribe and refetch paths are all covered without a socket.

### D-43 — RLS narrows; it does not refuse
**Learned while writing the comment permission tests.** An `UPDATE` or `DELETE`
that a policy disallows does not raise — the rows simply fall outside what the
statement can see, and it succeeds having changed nothing. Only a missing
*privilege* (or a failed `WITH CHECK` on an insert) produces 42501.
**Consequence for tests:** where `authenticated` holds the privilege and RLS
does the work, assert the *effect* — the row is unchanged, the row still
exists. Where the privilege is withheld entirely, assert the SQLSTATE. Both
shapes appear in the suites, and the difference is deliberate.

### D-44 — Five preference switches over fourteen event types
**Spec gap:** `notification_prefs` has five booleans (§5.1) and §5.3 lists
fourteen event types, so the mapping cannot be one-to-one and the spec does not
give it.
**Decision, as implemented in the fan-out trigger:**
- `new_bill` — bill_created, recurring_generated, bill_edited, bill_voided
- `payment_marked` — payment_marked
- `payment_confirmed` — payment_confirmed **and** payment_rejected
- `comments` — comment_added
- `reminders` — the daily reminder and the payer's Nudge

`member_joined` has no switch and always sends. The remaining types —
group_created, member_left, member_removed, bill_settled, recurring_created —
notify nobody, because §7.2's table does not list them; they still appear in
the activity feed.
**Why preferences are applied in the trigger:** an unwanted notification is
never written, rather than written and then filtered on the way out. Nothing
downstream has to remember to check.

### D-45 — Reminders and Nudge share `last_reminded_at`
**Spec §7.2** tracks the automatic reminders in `bill_shares.last_reminded_at`
and separately rate-limits Nudge to once per 24h per share.
**Decision:** both write that one column.
**Consequence, accepted deliberately:** a manual nudge counts as a reminder, so
a nudge on day one suppresses the automatic day-three reminder. The debtor gets
one message instead of two, which is the better outcome — and the alternative,
a second timestamp column, would let both fire on the same day.
**How exactly-two-reminders works:** null means never reminded; a value at or
past `created_at + 7 days` means both have gone out. The seven-day condition
requires `last_reminded_at < created_at + 7 days`, which can only be true once.

### D-46 — `send-push` is kept thin because it cannot be tested here
**Constraint:** no Firebase project (D-08), and `brew install deno` failed on
this machine, so the edge function cannot be run or even type-checked.
**Decision:** push every decision out of it and into SQL. Who gets notified,
what it says, and whether preferences allow it are all settled by the fan-out
trigger, which has 42 assertions on it. The function only delivers a row that
already exists: read the devices, send, record `pushed_at`, drop dead tokens.
**Why this matters:** the unverified surface is now a handful of straight-line
calls with no branching logic worth getting wrong, rather than the notification
rules themselves.
**Marked as such** at the top of `index.ts` and in its README, including the
note that `FCM_ACCESS_TOKEN` is short-lived and a real deployment needs to mint
one per request from the service account key — which is not implemented.

### D-47 — pg_cron was enabled on the live project
**What changed outside the repo:** `create extension pg_cron` was run against
`nwxcwolgxikzevmisukp`. It is required by §7.1 and was available but not
enabled.
**Reproducible:** `…0013_schedule.sql` enables it and schedules `hati-daily`,
both guarded so the local harness — which has no pg_cron — skips them with a
notice rather than failing.

### D-48 — Two test-harness facts worth not rediscovering
**`go_router`'s `currentConfiguration.uri` does not follow a `push`.** It keeps
reporting the base location, so a test that pushes should assert on what is on
screen rather than on the router's reported location. Tests that use `go` are
unaffected.
**`ListTile` merges its descendants' semantics into one node.** A `Semantics`
label inside a tile is announced as part of the tile, so
`find.bySemanticsLabel('Unread')` finds nothing while
`find.bySemanticsLabel(RegExp('Unread'))` finds it. The behaviour is correct;
only the finder needed to be less strict.

### D-49 — The recurring generator is SQL, not an Edge Function
**Spec §7.1** names `generate-recurring-bills` as an Edge Function invoked by
pg_cron.
**Decision:** implemented as `public.generate_recurring_bills()` in PL/pgSQL,
called from `run_daily_jobs()` by the same cron entry.
**Why:** pg_cron already calls SQL directly, so the Edge Function would add a
network hop and a second failure mode for no benefit. The whole run is one
transaction, so a mid-run failure cannot leave a template advanced but its bill
unwritten. And decisively — a SQL function can be tested on this machine, while
an Edge Function cannot (the same constraint that left `send-push` unverified,
D-46). §14 asks for proof that running twice makes one bill; this way there is
proof rather than a promise.
**Reused rather than reimplemented:** generation calls `apply_bill_split`, the
same function `create_bill` uses, so a recurring bill splits exactly like a
manual one.

### D-50 — Catch-up is bounded at twelve runs
**Spec gap:** §7.1 says to generate for templates whose `next_run_on` has
passed, but not what to do when several runs were missed — after an outage, or
a project paused for a month.
**Decision:** the generator loops until `next_run_on` is in the future, capped
at twelve iterations per template per run.
**Why a loop at all:** skipping missed runs silently loses money someone owes.
A monthly template that missed three months should produce three bills, each
dated correctly.
**Why a cap:** a template with a corrupted `next_run_on` far in the past would
otherwise generate thousands of bills in one night. Twelve covers a year of
monthly runs, and anything beyond that is a data problem worth noticing rather
than papering over.

### D-51 — A form reachable by deep link must not rely on `pop`
**Found by:** a widget test navigating straight to the recurring form and
saving, which threw `GoError: There is nothing to pop`.
**Decision:** the form pops when it can and otherwise `go`es to the list it
belongs to.
**Why it is not just a test artifact:** notifications deep-link into the app,
and D-47's `recurring_paused` notification routes at the recurring list. Any
screen reachable without a stack behind it needs somewhere to go on save.

### D-52 — Fade-through where the spec asks for a container transform
**Spec §11** asks for "container transform from bill card → bill detail".
**Decision:** a fade-through transition on the Bill detail route, using M3's
emphasized easing.
**Why not the real thing:** a container transform needs the `animations`
package's `OpenContainer`, which owns its own navigation — it pushes a route
itself. That does not compose with go_router's declarative routing, where the
route is chosen by the URL rather than by a widget. Fade-through is M3's own
answer for moving between screens that are not in a parent-child relationship,
so it reads as the same family of motion rather than as a fallback.
**Revisit** if the app ever moves to imperative navigation for this one screen,
which would not be worth it on its own.

### D-53 — The test surface is phone-shaped, and overflow is a failure
**Found by:** changing the harness's surface from Flutter's 800x600 default to
400x900 immediately failed four tests that had been passing.
**Cause:** 800x600 is neither a phone nor a tablet. Rows that fit at 800px
overflowed at phone width, and nothing was checking — Flutter reports an
overflow as a `FlutterError`, not an exception, so a test that only watches for
thrown exceptions passes over a visibly broken screen.
**Decision:** the harness pumps at 400x900, and `collectOverflows` turns
overflow into a test failure. `test/polish/accessibility_test.dart` runs 15
routes through it at 200% text and in dark mode.
**What it caught, all real:** the Notifications app bar could not fit a text
button beside an icon button; the Add bill and recurring forms each put two
form fields in a Row that overflowed at phone width; and two Rows put an
unbounded `Text` beside an icon with nowhere to wrap.

### D-54 — The app icon was redesigned after looking at it
**First attempt:** a white disc with a diagonal slash through it, meant to read
as "split". Rendered, it read as a prohibition sign — a red-circle-slash
without the red.
**Decision:** two halves of a disc, drawn apart and slid past each other along
the cut. The offset is what stops it reading as a slash.
**Worth recording** because the first version looked fine as a description and
wrong as an image. Generated assets deserve the same look-at-the-output check
as any other output.

### D-55 — The Android toolchain had drifted behind the Flutter upgrade
**Found by:** the first native build ever attempted on this project, at M10.
**Cause:** the project was scaffolded under Flutter 3.35.4 and then the SDK was
upgraded to 3.47.5 (D-12). `flutter upgrade` does not touch an existing
project's Android files, so the Gradle wrapper, AGP and Kotlin versions stayed
at the 3.35 template's and were all below what 3.47 requires. Each one only
surfaced after the previous was fixed:

| | was | now | Flutter 3.47 minimum |
|---|---|---|---|
| JDK | 25.0.2 (system) | 17.0.18, via `flutter config --jdk-dir` | ≤ 21 for Gradle 8.x |
| Gradle | 8.12 | 8.14.3 | 8.14.0 |
| AGP | 8.9.1 | 8.11.1 | 8.11.1 |
| Kotlin | 2.1.0 | 2.2.20 | 2.2.20 |

**On the JDK:** openjdk@17 was already installed via Homebrew, so this is a
Flutter setting pointing at an existing JDK — the system default is untouched,
which is what D-11 said to do.
**Not bumped to Flutter's template default** of Gradle 9.3.1: AGP 8.x does not
support Gradle 9, and moving to AGP 9 is a larger migration than this milestone
warrants. The versions above are the stated minimums and are mutually
compatible.

### D-56 — Neither platform build completes on this machine
**Android:** blocked on **disk space**. The volume is 100% full with 1.3 GB
free; an Android build needs several GB for the NDK, CMake and Gradle caches,
and fails with `No space left on device` partway through native compilation.
The toolchain itself is now correct — the build gets as far as CMake before
running out of room.
**iOS:** blocked on **simulator runtimes**. `xcrun simctl list runtimes` is
empty; Xcode 26 ships without them and they are a separate download. This is
the same gap `flutter doctor` reported at M0.
**Consequence:** the app has never been compiled or run on a device or
simulator. Everything verified so far is `flutter test`, `flutter analyze`, and
SQL against the live project. Spec §14's first acceptance criterion — the
reference scenario working end to end on a physical Android and iOS device —
remains unmet for this reason, on top of D-07 and D-09.

### D-57 — Invite people by name, because links have nowhere to land
**Context:** invite links point at `hati.app`, which Hati does not own (D-07);
in practice it is someone else's parked domain, so a shared link opens a
GoDaddy page. The app also registers no link handler on either platform.
**Decision:** an owner or admin can search for someone already on Hati and
invite them directly (`…0015_direct_invites.sql`). The invite arrives as a
notification with Join / Decline, and as a card on the Groups tab so it is
not lost. Nothing about the group is readable until they accept. The link
flow stays in place for when a domain exists. A friends list was considered
and dropped: it adds a second request-and-accept step to reach the same place.
**Search:** display names by substring, or an email by exact match — the way
to pick the right one of several people with the same name. Results carry the
id and display name only; emails are never returned, and a partial email
matches nothing, so the search cannot be used to collect addresses.
**Privacy cost, accepted:** profiles were visible only to groupmates (…0002).
Any owner or admin — which is anyone, since anyone can create a group — can now
look up any user's display name, and can confirm whether a known email has a
Hati account. Avatars stay groupmate-only, so results show initials.
**Abuse limits:** one row per person per group, so re-sending a pending invite
is a no-op and never notifies twice; a decline blocks re-inviting for 24 hours.
**No push:** FCM is still stubbed (D-08), so the invite appears when the
invitee next opens the app, not as a phone notification.

### D-58 — Wallet QRs per e-wallet, the payer picks where to be paid, proof is required

**Context:** people keep several PH e-wallets and want their barkada to scan a
QR rather than type a number. The payer also wants to steer payments to one
wallet on some bills, and wants a receipt before they confirm.
**Decision** (`…0016_wallet_qr_and_proof.sql`):
- Payment methods gain GoTyme, ShopeePay, GrabPay, Coins.ph and PalawanPay
  alongside GCash, Maya and bank. Each method keeps its own QR, as before.
- `bills.receive_method_id` is where the payer wants this bill's money: one of
  their methods, or null for "any of my wallets". Only the payer sets it, via
  `set_bill_receive_method` (HT042 / HT046, HT048 for someone else's method).
  It clears itself when the method is deleted or the bill's payer changes.
- Settle up is now a full page, not a sheet, so a QR is big enough to scan.
  It shows only the pinned wallet, or chips to switch between all of them.
  The method recorded on the payment is the wallet on show.
- "I've paid" is disabled until a receipt screenshot is attached, and
  `mark_share_paid` raises HT047 without one (or with a path outside the
  bill's group folder). A duplicate tap still returns the claim in flight.
**Cost, accepted:** a debtor who paid in cash cannot mark it paid without a
picture; the payer records cash instead (Record cash), which needs no proof.
The "Open wallet" button still covers only GCash and Maya — the other apps'
URL schemes are unverified (D-34).

### D-59 — A deliberate design system instead of Material defaults

**Context:** the app looked like stock Material 3 — tinted surfaces, pill
buttons, a filled card for every row — and on Android 12+ dynamic colour
replaced the teal brand with the wallpaper's palette (the emulator showed navy).
**Decision:**
- **Fixed palette** (`app_theme.dart`): warm neutrals, one teal accent matching
  the icon, and hand-tuned owe/owed/pending colours that pass 4.5:1 in both
  modes. Dynamic colour is dropped (and the `dynamic_color` package removed);
  this overrides the spec §11 line asking for it, because the brand should look
  the same on every phone.
- **Inter** bundled (`assets/fonts`, SIL OFL) with a compact type scale and
  tabular figures on every amount style.
- **Tokens:** 8dp spacing, radii 6/10/14/20 (no pills), hairline borders,
  short motion that switches off under the system's reduce-motion setting.
- **Grouped lists** (`core/widgets/surfaces.dart` — `ListGroup`,
  `SectionHeader`, `StatusLabel`, `Tag`, `InfoNote`, `ContentWidth`,
  `BrandMark`): related rows share one surface instead of a card each.
- **Home** leads with what you owe and are owed side by side. A single net
  figure was tried and dropped: Hati never offsets debts (spec §2), so a net
  number invites paying the wrong amount.
- **Navigation:** bottom bar on phones, side rail at ≥ 840dp, content capped at
  720dp so tablet rows don't stretch edge to edge.
**Checked by** rendering the real screens through the widget-test harness with
the real fonts, light and dark, phone and tablet.

### D-60 — Google sign-in, and reset links that open the app

**Problem:** the password-reset email linked to `localhost:3000`. The app sent
no `redirectTo`, so Supabase used the project's Site URL, and the app had no
deep link to receive the link anyway (see D-57).
**Decision:**
- One deep link, `com.hati.hati://auth-callback` (`SupabaseConfig.authRedirect`),
  registered in AndroidManifest.xml and Info.plist. Flutter's own deep-link
  routing is turned off so go_router does not also try to open it as a page;
  supabase_flutter reads it and exchanges the code for a session.
- **Reset:** `resetPasswordForEmail(redirectTo: …)`. The passwordRecovery event
  sets `AuthSnapshot.recoveringPassword`, and the router holds the user on
  Set a new password until `updateUser(password)` succeeds.
- **Google:** Supabase's browser OAuth (`signInWithOAuth`) returning through the
  same deep link, rather than the native `google_sign_in` picker. It needs one
  Web OAuth client instead of an Android client per signing key, and no new
  package. Cost: a browser hop instead of an in-app account sheet.
- **Same email, same account:** Supabase links a Google identity to an existing
  user with the same verified email. Hati requires verification before
  sign-in, so an email/password account and Google with that address are one
  account, with one profile.
- Google sends `full_name`, not `display_name`, so `handle_new_user` now falls
  back through `full_name` and `name` before the email's local part
  (`…0017_oauth_profile_names.sql`).
**Scope:** spec §1 listed social login as out of scope for v1; Google is now in.
**Requires dashboard setup** (not in code): the redirect URL in the allow list,
and the Google provider enabled with the Web client ID and secret.

### D-61 — Terms and Conditions, written for Philippine law

**Decision:** an in-app Terms page (`lib/features/legal/`), readable signed in
or out at `/terms` and from Profile → Legal.
- **Core clause (§5):** Hati is a tracking tool only. It is not liable for
  failed, reversed or mistaken transfers, wrong QR or account details,
  e-wallet outages, unpaid or disputed shares, or fake payment proof. Debts
  exist only between users; Hati does not collect, guarantee or enforce them.
- **Why the clause is narrow, not blanket:** under the Civil Code a waiver of
  liability for future fraud is void (Art. 1171), and negligence liability
  stays with the courts (Art. 1172). A clause claiming no liability for
  anything risks being struck down whole. So the exclusions name what is
  genuinely outside Hati's control, and §9 keeps liability the law will not
  let anyone waive: fraud, bad faith, gross negligence, Consumer Act and Data
  Privacy Act rights. Ambiguity is read in the user's favour (Art. 1377),
  which suits a contract of adhesion.
- **Also covers:** acceptance by electronic means (RA 8792); not a payment
  system operator (RA 11127); age 18+ or guardian consent; AMLA (RA 9160);
  Data Privacy Act rights and the National Privacy Commission (RA 10173);
  Philippine governing law, amicable settlement first, then courts, without
  losing DTI/NPC complaints or small claims.
- **Agreement:** email sign-up needs an unticked-by-default checkbox, and the
  Terms version (`kTermsVersion`) is stored in the account's metadata. Google
  sign-in skips the form, so a notice sits under the Google button instead.
**Open:** the operator's legal name, address, contact email and court venue are
placeholders (`TermsParty`). A Privacy Notice, which the Data Privacy Act
expects as its own document, does not exist yet. Have Philippine counsel
review before public release.

### D-62 — Open wallets by package name; MariBank added

**Problem:** "Open GCash" went to the Play Store even with GCash installed.
Android 11+ hides other apps unless the manifest declares them, so
`canLaunchUrl('gcash://')` always answered no. Maya's scheme was also wrong
(`mayaph://`; the app registers `paymaya://`).
**Decision:** on Android, launch the wallet by package name through a small
`hati/wallets` channel in MainActivity.kt (`getLaunchIntentForPackage`), with
`<queries>` entries for each package. That is what tapping the app icon does,
and it does not depend on undocumented URL schemes. The Play Store is the
fallback only when the app is not installed. Package names were read from the
apps installed on a real phone and confirmed on the Play Store: GCash
`com.globe.gcash.android`, Maya `com.paymaya`, GoTyme `ph.com.gotyme`,
ShopeePay via Shopee `com.shopee.ph`, GrabPay via Grab
`com.grabtaxi.passenger`, Coins.ph `asia.coins.mobile`, PalawanPay
`com.palawanpay.ewallet`, MariBank `ph.seabank.seabank` (its old SeaBank
package). iOS can only use schemes, which are unverified there, so it keeps
scheme-then-App-Store.
**MariBank** joins the payment types (`…0018_maribank.sql`). It is a bank, so
the form asks for an account number. No wallet allows prefilling an amount.

### D-63 — A Privacy Notice, and the Terms filled in

**Decision:** an in-app Privacy Notice at `/privacy`, from Profile → Legal and
from the small print on Welcome, Log in and Sign up ("…and acknowledge the
Privacy Notice"). Written from what the tables actually hold: account, profile,
payment methods and QR codes, bills, receipts and proofs, comments, activity,
notifications and device tokens. It names the controller (Nex,
yakokakiiiii@gmail.com), the processors (Supabase; Google for sign-in and
FCM), possible storage outside the Philippines, what deletion erases and what
it keeps, the Section 16 rights and the NPC. The Terms placeholders are
filled; with no venue chosen, disputes go to "the proper courts of the
Philippines". The Terms and the Notice now share one renderer
(`LegalDocument`, `LegalScreen`).
**Still advised:** review by Philippine counsel before public release.

### D-64 — Deleting your own account

**Why:** Google Play requires in-app deletion; the Data Privacy Act gives a
right to erasure.
**Decision:** Profile → Delete account. Refused while any bill is open in
either direction (`account_deletion_blockers`, HT009), and the screen lists
which bills — otherwise a debtor loses the QR they were to pay, or a debt
disappears with its debtor. Confirmed by typing DELETE.
`prepare_account_deletion` (as the user) leaves every group, handing
ownership to an admin or the longest-standing member, pauses repeating bills
that involve them, deletes payment methods, device tokens, notifications,
settings and pending invites, scrubs their name from past activity, and
renames the profile "Deleted user". The `delete-account` edge function then
removes their photo and QR files, frees the email, clears Google's metadata
and soft-deletes the sign-in. Soft, because bills others keep reference the
profile row.
**Known limit:** notification text already delivered to *other* people
("Bea added Airbnb") keeps the name it was written with.

### D-65 — Push notifications

**Decision:** Firebase Cloud Messaging. On sign-in the app asks for permission
and registers its token through `register_device_token`, which moves a token
to whoever is signed in now — a plain upsert would fail under RLS and leave a
shared phone receiving the previous person's pushes. Sign-out releases it
first. Tapping a notification opens its `data.route`; a push that arrives
with the app open refreshes the bell. `send-push` now mints Google OAuth
tokens from the service account, accepts calls only with the
`x-hati-webhook-secret` header, and re-reads the row by id instead of trusting
the request body. Everything push does is best effort; nothing waits on it.
Without `google-services.json` the app builds and runs with push off.
**Token choice:** the classic FCM registration token (`getToken`, deprecated
in firebase_messaging 17) because HTTP v1 `message.token` sends to exactly
that; the new installation-ID flow is a different send path.
**Status:** verified end to end on 5 November 2026 — a bill added on one
phone notified another (Firebase project `hati-a1a23`). D-08 is resolved.
**Found on the way:** send-push's first reads failed with "permission denied
for table notifications". Current Supabase projects grant the API roles no
DML by default, and …0007 granted the client roles only. `…0021` grants
service_role exactly what delivery needs (read notifications, stamp
`pushed_at`, read and prune device tokens). The functions also resolve the
new-style API keys first (`_shared/keys.ts`), and a failed read is now
reported as such rather than as "no such notification".

### D-66 — A default wallet to be paid on

**Decision:** `profiles.receive_method_id` — set under Payment methods → "Ask
people to pay you via". Settle up uses, in order: the wallet chosen on the bill
(D-58), else this default, else any of the payer's wallets. A trigger refuses a
method that is not the profile's own (HT048), because profiles are written
directly by their owner. The bill card's "no choice" option now reads "My
default (GCash)" when one is set.
**Not supported:** "any wallet" on one bill while a default is set — the bill
can only pick a specific wallet or fall back to the default.

### D-67 — Settle all with one person

**Decision:** in a group's Balances tab, "Settle all with Bea · ₱X" appears when
the viewer owes one person on two or more unpaid bills. One page, one total,
one screenshot, one "I've paid". `mark_shares_paid` checks every share up front
— the caller's, one group, one payer, all unpaid (HT054–HT056) — then calls
`mark_share_paid` for each, so each bill keeps its own payment row, history and
notification; `payments.batch_id` ties them. The payer's review sheet shows
"One payment for N bills" and confirms or rejects the whole batch
(`confirm_payment_batch`, `reject_payment_batch`).
**Within one group only,** because payment proofs live in that group's storage
folder, readable by its members.
**Cost:** the payer gets one notification per bill in the batch.
**Also:** error codes HT050–HT053 were already the nudge's, so the batch uses
HT054–HT056; and account deletion moved from HT009 (already "the owner cannot
be removed") to HT057 in `…0024`.

### D-68 — Save QR

**Decision:** a "Save QR" button under the payer's QR on the settle-up page
downloads it from storage and saves it to the gallery (`gal`), so it can be
opened from inside GCash or Maya — how most people pay a QR on the same phone.
Permission: `WRITE_EXTERNAL_STORAGE` only up to Android 10; iOS asks with
`NSPhotoLibraryAddUsageDescription`.

### D-69 — Invite links on Firebase Hosting

**Problem:** links pointed at `hati.app`, a domain Hati does not own (D-07, D-57).
**Decision:** Firebase Hosting on the project already used for push:
`https://hati-a1a23.web.app/join/TOKEN`. Android App Links (`autoVerify`,
`/.well-known/assetlinks.json`) open Hati directly; otherwise the invite page
offers "Open in Hati" (an intent link with a browser fallback) and explains
there is no store listing yet. `InviteLinkRouter` sends both link forms to the
join screen, and signed-out users resume the invite after signing in.
The site also serves `/terms` and `/privacy`, generated from the app's own text
by `tool/gen_legal_html.dart` — the public privacy-policy URL the Play Store
asks for.
**When the signing key changes,** add its SHA-256 to `assetlinks.json` and
redeploy, or links stop opening the app. iOS universal links need an Apple
Developer account (D-09); iPhones get the web page.

### D-70 — Paying in cash needs no screenshot

**Problem:** D-58 made a screenshot mandatory for "I've paid", so someone who
paid in cash had no way to say so — only the payer could record it (Record
cash). D-58 accepted that cost; in use it was a dead end.
**Decision:** the settle-up page asks "Wallet or bank" or "Cash". Cash hides
the QR codes and the screenshot step, and the button reads "I paid in cash".
`mark_share_paid` (`…0025`) accepts method `cash` without proof — every other
method still needs its screenshot (HT047) — and the payer still confirms, so a
false cash claim is as visible as any other. "Settle all" works in cash too.
The "How did you pay?" chips (shown when the payer has no wallets) lose their
"Cash / other" label; cash has its own option now.

### D-71 — A web app, for iPhones

**Why:** iPhones cannot install the APK, and every native route to them goes
through a paid Apple Developer account. The web app is the free way in.
**Decision:** the same Flutter code built for the web, served from Firebase
Hosting at `https://hati-a1a23.web.app/app/` with hash routes (`/app/#/…`),
so no server rewrites are needed for deep pages. A manifest and Apple meta
tags make "Add to Home Screen" open it full-screen with Hati's icon.
`tool/build_web.sh` builds it into `hosting/public/app`, which is not
committed.
- `AppPlatform` replaces `dart:io`'s `Platform`, which throws in a browser.
- Photos are resized by the browser's picker; the native compressor is skipped.
- Save QR downloads the image (`browser_download_web.dart`, conditionally
  imported so Android never compiles it).
- Sign-in, reset and verification links return to the web app when started
  there (`SupabaseConfig.authRedirect`); its URL must be in Supabase's
  redirect allow list.
- `delete-account` answers CORS preflights from Hati's own site.
- The invite page offers "Open Hati on the web" to iPhones and computers.
**Not yet (Stage 2):** web push notifications; on iPhone they also need "Add to
Home Screen" and iOS 16.4+. Opening wallet apps from Safari is best effort and
untested on a real iPhone. This goes beyond spec §1, which left a web client
out of v1.

### D-72 — Push notifications in the web app

**Decision:** the web app uses the same FCM pipeline as Android. A "Hati Web"
app in the Firebase project, a background script (`web/firebase-messaging-sw.js`,
Firebase JS 13.1.0 to match firebase_core_web), and the VAPID key from `.env`.
Browsers register as platform `web` (`…0026`); send-push gives web
notifications a link into the web app (`/app/#/route`) and Hati's icon.
**Asking:** browsers, and iPhones in particular, allow the permission prompt
only from a tap, so the web app never asks on its own. Home shows a "Get
notified" card with "Turn on"; Safari on an iPhone that is not running Hati
from the Home Screen gets the "Add to Home Screen" instructions instead, since
iOS (16.4+) offers push only there. A browser that already allowed it
registers quietly. `PushRegistration` now reports a `PushStatus`.
**Untested on a real iPhone** until the VAPID key is set and the site redeployed.
