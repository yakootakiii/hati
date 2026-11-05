# Hati — Implementation Plan

Derived from `bill-splitting-app-spec.md`. The spec is the contract; this file is the
execution order, the exit criteria per milestone, and the running status.

**Status legend:** `todo` · `wip` · `done`

---

## Environment baseline (verified 2026-09-25)

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.47.5 stable | Upgraded from 3.35.4 — see D-12 |
| Android toolchain | JDK 17, Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20 | All bumped at M10; they had drifted behind the SDK upgrade (D-55) |
| Disk | **1.3 GB free, 100% full** | Blocks the Android build (D-56) |
| iOS simulator runtimes | none installed | Blocks the iOS build (D-56) |
| Xcode | 26.0.1 | Simulator runtimes not installed yet |
| Android SDK | 36.0.0 | `flutter doctor --android-licenses` not accepted yet |
| JDK | 25 | Flutter 3.47.5 no longer warns; re-check at the first Android build |
| Supabase CLI | installed via Homebrew | Hosted project, `supabase db push` |
| Docker | not installed | Not required — we develop against a hosted project |

**Backend mode:** hosted Supabase project, migrations applied with
`supabase db push`. No local Docker stack.

**Live project (linked 2026-09-25):** `nwxcwolgxikzevmisukp`, ap-southeast-1
(Singapore), Postgres 17.6 — the same major version the local harness tests
against. All fourteen migrations applied; 17 tables live; the full SQL suite —
339 assertions, covering 254 split vectors — passes against it. `pg_cron` is
enabled and the `hati-daily` job is scheduled.

Run the suite remotely with the **session pooler** (port 5432 —
the transaction pooler on 6543 cannot hold `set local role`):
`DATABASE_URL=... tool/run_rls_tests.sh`

**Deferred externals** (no accounts yet — see `DECISIONS.md` D-07..D-09):
custom domain for App Links / Universal Links, Firebase project for FCM,
Apple Developer account.

---

## Milestones

### M0 — Scaffold & decisions — `done`
Deliverables
- `flutter create` with the feature-first tree from spec §4.2.
- Dependencies: `flutter_riverpod`, `riverpod_annotation`, `go_router`, `freezed`,
  `json_serializable`, `supabase_flutter`, `intl`, `image_picker`,
  `flutter_image_compress`, `url_launcher`, `dynamic_color`; dev: `build_runner`,
  `riverpod_generator`, `mocktail`. (`riverpod_lint`/`custom_lint` omitted — D-13.)
- M3 theme: `ColorScheme.fromSeed(#00897B)`, light + dark, `dynamic_color` fallback,
  `ThemeExtension` carrying `owe` / `owed` / `pending`.
- `core/money/`: `Money` value type over `int` centavos — parse, format
  (`NumberFormat.currency(locale: 'en_PH', symbol: '₱')`), arithmetic. No `double`.
- `core/split/`: package skeleton + the `SplitResult` contract only (engine lands in M3).
- `app/router.dart`: go_router with auth redirect stub and the shell route for the
  3-destination `NavigationBar`.
- `analysis_options.yaml` with the money lint (see Exit criteria).
- `PLAN.md`, `DECISIONS.md`.

Exit criteria
- `flutter analyze` clean, `flutter test` green, app boots to a placeholder Home.
- CI-style money check passes: `tool/check_no_float_money.sh` scans
  `lib/core/money/`, `lib/core/split/` and every `features/**/{domain,data}/`
  for `double`, `num`, `toDouble` and non-truncating division (spec §14).

Result: `flutter analyze` clean, 16 tests green, app boots to the placeholder
shell, money check passes.

### M1 — Foundation (auth + schema) — `done` apart from email delivery
Deliverables — all written:
- `20260925000001_init.sql` — every table in §5.1, the §5.1 indexes, the extra
  constraints in D-17, and the money/extras helpers.
- `20260925000002_rls.sql` — `is_group_member`, `has_group_role`,
  `shares_group_with`, `can_read_bill`, the §5.4 policy set, and table- and
  column-level grants as defence behind the policies.
- `20260925000003_profiles_trigger.sql` — profile + notification prefs on signup.
- `20260925000004_storage.sql` — the five private buckets and their policies.
- Auth feature: sign up, log in, forgot password, verify-email notice, welcome;
  `AuthRepository` behind an interface, `AuthController`, validators, and a
  session-aware router redirect that stashes an invite token through auth.
- `ConfigMissingScreen`, so a build with no project boots and explains itself.

Exit criteria
- ✅ A non-member cannot read any row of another group. 30 assertions in
  `supabase/tests/rls_test.sql`, run via `tool/run_sql_tests_local.sh`; the four
  write refusals assert SQLSTATE 42501 specifically, so an unrelated error
  cannot read as a pass.
- ✅ Signing up creates exactly one `profiles` row with the submitted display
  name (asserted in the same suite).
- ✅ 30 Dart tests green, `flutter analyze` clean, money check passes.
- ⬜ **Not yet done:** migrations have never run against a real Supabase project.
  Needs a project ref + publishable key. Email delivery (verification link,
  password reset) and the real `storage.objects` column names are unverified
  until then — see D-19.

### M2 — Groups & invites — `done`, verified against the live project
Deliverables — all written:
- `20260925000005_groups_rpc.sql` — `create_group`, `create_invite`,
  `revoke_invite`, `get_invite_preview`, `join_group`, `group_leave_blockers`,
  `leave_group`, `remove_member`, `set_member_role`, with the HT001–HT010
  error protocol (D-20).
- `20260925000006_group_queries.sql` — `get_my_groups`, one round trip for the
  Groups list.
- Screens: Groups list (with archived section), Create group, Group detail
  (tabbed shell; Bills/Balances fill at M4, Activity at M7), Members with
  promote / demote / remove, Invite sheet with Copy / Share / Reset.
- `/join/:token` with the full §8 flow, including the stash-through-auth resume.

Exit criteria
- ✅ Joining is idempotent: a second tap returns the same group, consumes no
  extra use and emits no second event.
- ✅ Revoked, expired, exhausted and unknown tokens each raise their own code
  and get their own copy — verified in SQL and in widget tests.
- ✅ `leave_group` is refused with the blocking bills named, from either side
  of the debt; `group_leave_blockers` is the single definition both the check
  and the UI read, so the message and the rule cannot disagree.
- ✅ 41 new SQL assertions (71 total) and 65 Dart tests green.

### M3 — Split engine — `done`, verified against the live project
Deliverables — all written:
- `lib/core/split/` — `split_models.dart` and `split_engine.dart`, pure Dart,
  integer centavos throughout, all five modes with the largest-remainder rule.
- `…0008_split_engine.sql` — the PL/pgSQL twin: `split_distribute`,
  `split_spread`, `split_itemized`, `compute_split`, with failures in the
  HT020–HT029 range (D-30). M4's `create_bill` calls `compute_split`.
- `supabase/tests/split_vectors.json` — 26 hand-written vectors, every §6.4
  case named explicitly.
- `supabase/tests/split_vectors_fuzz.json` — 240 generated vectors with Dart as
  the reference (D-29).

Exit criteria
- ✅ Every §6.4 vector passes in both engines with identical output.
- ✅ `sum(shares) == total` asserted on all 254 computing vectors in both
  engines, independently of the expected map.
- ✅ All 12 rejection vectors raise the right failure, in both engines.
- ✅ **254 vectors match between Dart and SQL to the centavo**, on the live
  project as well as locally.
- ✅ Verified non-vacuous: injecting a wrong expectation into a vector turns
  the SQL suite red.

### M4 — Bills — `done`, verified against the live project
Deliverables — all written:
- `…0009_bills_rpc.sql` — `create_bill`, `update_bill`, `void_bill`,
  `get_my_balances`, `get_my_open_shares`, plus `canonical_participants`
  (D-31) and the shared `apply_bill_split`. Failures in HT030–HT036.
- Add/Edit bill with the `SegmentedButton` mode switch, participant checklist,
  per-mode inputs, the live "₱X left to assign" hint and a preview that runs
  the same engine the server runs.
- Itemized editor with assignee chips, the three extras and a per-person
  breakdown; the total is derived, not typed (D-32).
- Bill detail, group Bills and Balances tabs, Home summary cards.

Exit criteria
- ✅ The §1 reference scenario: ₱12,500 four ways is ₱3,125 each, the payer's
  own share settled on the spot — asserted in SQL and in widget tests.
- ✅ Editing is refused once a payment is `pending` or `confirmed` (HT033),
  and the UI hides Edit under the same rule.
- ✅ 172 SQL assertions and 134 Dart tests, locally and against the live
  project.

### M5 — Settlement — `todo`
Deliverables
- Payment methods CRUD in Profile (incl. QR upload).
- Settle up bottom sheet (§9) with wallet-launch best effort and store fallback.
- RPCs: `mark_share_paid`, `confirm_payment`, `reject_payment`,
  `record_payment_received`.

Exit criteria
- A debtor cannot confirm their own payment; only the bill payer can (§14).
- Double-tapping mark-paid or confirm is a no-op the second time (§12.9).

### M6 — Attachments — `done`, verified against the live project
Deliverables — all written:
- `lib/core/images/` — the pick-and-compress service (1600px long edge, JPEG
  q80, spec §3), the bucket and path definitions, and the storage client with
  signed-URL reads.
- Bill receipts: up to five per bill, pick from camera or gallery, thumbnails
  on the form, progress while saving, carousel on Bill detail with tap to
  enlarge.
- Payment proofs: one per payment, attached in the Settle up sheet and shown
  to the payer in Payment review.
- Payment-method QR codes: uploaded on the method form, shown to whoever is
  settling up.
- No migration needed — the buckets and policies landed in
  `…0004_storage.sql`; M6 is what finally exercises them.

Exit criteria
- ✅ A non-member cannot read a group's storage objects, in any of the five
  buckets. 18 assertions in `supabase/tests/storage_test.sql`; reads stand in
  for signed-URL requests, since Supabase checks SELECT on `storage.objects`
  before it will sign one.
- ✅ Malformed path prefixes grant nothing, even to a member — an object at
  `bill-receipts/not-a-uuid/…` is readable by nobody.
- ✅ Writes are scoped too: nobody can write into another user's avatar or QR
  folder, a plain member cannot change the group photo, and an outsider cannot
  upload into a group at all.
- ✅ A former member loses the images, though they keep their bill rows (§5.2).
- ✅ 225 SQL assertions and 162 Dart tests, locally and against the live
  project.

**Not wired yet:** the `avatars` and `group-photos` buckets. Both have policies
and test coverage, and the pipeline is the same three calls — they just have no
UI on them until the profile and group-settings screens land in M10.

### M7 — Activity & comments — `done`, verified against the live project
Deliverables — all written:
- `…0011_activity.sql` — the comments trigger (D-40), `edited_at` maintained by
  the database rather than the client, `get_activity_feed` for both feeds with
  cursor paging, and the five tables added to the realtime publication.
- All fourteen §5.3 event types render, each with its own copy and icon; an
  unrecognised type degrades instead of crashing.
- Group Activity tab and the global merged feed, both with infinite scroll.
- Comment thread on Bill detail: post, edit, soft delete, with a tombstone so
  the thread keeps its shape.
- Realtime subscriptions that live exactly as long as the screen (§4.3).

Exit criteria
- ✅ No client can insert an `activity_events` row directly — not even a member
  of the group (42501, no privilege).
- ✅ A comment written straight through PostgREST still emits its event,
  because the event comes from a trigger rather than an RPC the client could
  bypass.
- ✅ Feeds are scoped: an outsider's merged feed is empty, and a member of one
  group cannot read another group's feed.
- ✅ 250 SQL assertions and 184 Dart tests, locally and against the live
  project; all five tables confirmed in the live realtime publication.

### M8 — Notifications — `done` except delivery, verified against the live project
Deliverables — all written:
- `…0012_notifications.sql` — the fan-out trigger on `activity_events`,
  covering every event §7.2 lists, with preferences applied before a row is
  written; `send_reminders()` for the 3- and 7-day reminders; `nudge_share`
  rate-limited to once a day (HT050–HT053); `run_daily_jobs()`.
- `…0013_schedule.sql` — `hati-daily` on pg_cron at 22:00 UTC, which is 06:00
  Asia/Manila as §7.1 specifies. Confirmed active on the live project.
- Notifications list with deep links through `data.route`, the app-bar bell
  with an unread badge, and the five preference switches.
- Nudge on Bill detail, for the payer, on an unpaid share.
- `supabase/functions/send-push/` — the edge function and its README.

Exit criteria
- ✅ Fan-out is correct per event type: the right people, the right copy, and
  each recipient's own share amount in the body.
- ✅ Preferences are honoured *before* the row is written — an unwanted
  notification is never created, not created and filtered.
- ✅ Reminders go out at three days and again at seven, and then stop.
- ✅ Nudge is payer-only and refuses a second attempt within 24 hours.
- ✅ 292 SQL assertions and 202 Dart tests, locally and against the live
  project.
- ⬜ **Delivery is not verified.** `send-push` has never been executed: there
  is no Firebase project (D-08) and no Deno toolchain on this machine. See
  D-46 for how the risk was contained.

### M9 — Recurring bills — `done`, verified against the live project
Deliverables — all written:
- `…0014_recurring.sql` — `advance_run_date` with month-end clamping,
  `create_recurring_bill`, `update_recurring_bill`, `set_recurring_paused`,
  `delete_recurring_bill`, and `generate_recurring_bills`, in SQL rather than
  an Edge Function (D-49). `run_daily_jobs` now does both jobs.
- Repeating bills screen: schedule, next run, pause/resume, edit, delete.
- A form with no Items mode, since a template cannot be itemized (§5.1).

Exit criteria
- ✅ **Running the generator twice for one date produces exactly one bill**,
  and so does rewinding `next_run_on` and running it again — the partial
  unique index refuses the second insert.
- ✅ The anchor day clamps to the end of a short month *and climbs back*: the
  31st becomes 28 February, then 31 March, then 30 April. It does not stick at
  28.
- ✅ Participants who left are skipped; if the payer has left, the template
  pauses itself and tells the creator and the group's admins why.
- ✅ Deleting a template leaves the bills it already made untouched.
- ✅ 339 SQL assertions and 219 Dart tests, locally and against the live
  project; `hati-daily` confirmed scheduled.


### M10 — Polish — `done`
Deliverables — all written:
- **Appearance setting** — light, dark or match the phone, stored on the
  device so it applies before the first frame (spec §11).
- **Avatars and group photos** — the two buckets M6 left unwired. Profile
  editing with an avatar, group settings with a photo, and `UserAvatar` used
  everywhere an initial used to be hand-rolled.
- **Group settings** — rename, photo and archive, replacing the archive toggle
  that was buried in the group's overflow menu.
- **Motion** — a fade-through transition into Bill detail (D-52).
- **App icon and splash** — generated from the brand seed, wired into both
  platforms.
- **Accessibility sweep** — 15 routes checked at 200% text and in dark mode.

Exit criteria
- ✅ Every list has an illustrated empty state and every load has an inline
  retry — 11 and 16 files respectively.
- ✅ 15 routes render at **200% text scale with no clipping**, and again in
  dark mode. Four real overflows were found and fixed.
- ✅ Avatar-only content carries semantics: "Bea, Owner", "Carlo, ₱3,125.00,
  Unpaid", "1 unread notification".
- ✅ The theme follows the platform and can be overridden.
- ✅ 339 SQL assertions and 255 Dart tests, locally and against the live
  project.


## Known blockers to spec §14 acceptance

1. **Invite link opening the installed app** cannot be verified without a domain
   serving `assetlinks.json` / `apple-app-site-association` (D-07).
2. **Push notification delivery** cannot be verified without a Firebase project (D-08).
3. **Physical iOS device testing** needs an Apple Developer account (D-09).
4. **Email delivery** — the verification link and password reset — needs
   Confirm email switched on and the SMTP rate limit accepted or replaced.
5. **The app has never been compiled.** Android needs disk space; iOS needs
   simulator runtimes (D-56). Everything to date is verified by `flutter test`,
   `flutter analyze` and SQL against the live project.

Everything else in §14 is reachable with the current setup.
