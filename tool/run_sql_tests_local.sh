#!/usr/bin/env bash
# Applies every migration to a throwaway local Postgres, then runs the RLS
# suite against it. No Supabase project and no Docker needed.
#
# Verifies the SQL really parses and the policies really behave; it cannot
# verify anything Supabase-specific beyond the shim in
# supabase/tests/local_supabase_shim.sql.

set -euo pipefail
cd "$(dirname "$0")/.."

PGBIN="${PGBIN:-/Applications/Postgres.app/Contents/Versions/17/bin}"
WORKDIR="${TMPDIR:-/tmp}/hati-sqltest.$$"
PGDATA="$WORKDIR/data"
PGPORT="${PGPORT:-54329}"
export PGHOST="$WORKDIR"

cleanup() {
  "$PGBIN/pg_ctl" -D "$PGDATA" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$WORKDIR"
"$PGBIN/initdb" -D "$PGDATA" -U postgres --auth=trust >/dev/null
"$PGBIN/pg_ctl" -D "$PGDATA" -o "-p $PGPORT -k $WORKDIR -c listen_addresses=''" \
  -l "$WORKDIR/server.log" -w start >/dev/null

psql_run() {
  "$PGBIN/psql" -p "$PGPORT" -U postgres -d hati -v ON_ERROR_STOP=1 --no-psqlrc "$@"
}

"$PGBIN/createdb" -p "$PGPORT" -U postgres hati

echo "→ shim"
psql_run --quiet -f supabase/tests/local_supabase_shim.sql

for migration in supabase/migrations/*.sql; do
  echo "→ $(basename "$migration")"
  psql_run --quiet -f "$migration"
done

for suite in supabase/tests/*_test.sql; do
  echo "→ $(basename "$suite")"
  psql_run -f "$suite"
done
