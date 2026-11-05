#!/usr/bin/env bash
# Runs every SQL test suite against a database.
#
#   DATABASE_URL=postgresql://postgres:...@db.<ref>.supabase.co:5432/postgres \
#     tool/run_rls_tests.sh
#
# Every suite runs inside a transaction that rolls back, so it is safe to point
# at a real project — though a dedicated dev project is still wiser.
#
# Use the SESSION pooler (port 5432), not the transaction pooler (6543): the
# suites rely on `set local role` holding across statements.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is not set." >&2
  echo "Find it in the Supabase dashboard under Project Settings → Database." >&2
  exit 2
fi

for suite in supabase/tests/*_test.sql; do
  echo "→ $(basename "$suite")"
  psql "$DATABASE_URL" \
    --quiet \
    --no-psqlrc \
    --set ON_ERROR_STOP=1 \
    -f "$suite"
done
