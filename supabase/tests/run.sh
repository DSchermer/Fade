#!/usr/bin/env bash
# Runs the SQL tests against a throwaway local Postgres database.
# Usage: supabase/tests/run.sh      (needs a local Postgres server; uses the 'postgres' superuser)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="fade_test_$$"
if [ "$(id -u)" = 0 ] && id postgres >/dev/null 2>&1; then pg=(runuser -u postgres -- psql); else pg=(psql); fi
run() { "${pg[@]}" -v ON_ERROR_STOP=1 -q "$@"; }
trap 'run -d postgres -c "drop database if exists $db" >/dev/null 2>&1 || true' EXIT
run -d postgres -c "create database $db" >/dev/null
run -d "$db" < "$here/00_local_auth_stub.sql" >/dev/null
for f in "$here"/../migrations/*.sql; do run -d "$db" < "$f" >/dev/null; done
cd "$here"   # tests load fixtures by relative path
for t in "$here"/*_test.sql; do run -o /dev/null -d "$db" < "$t"; done
echo "All SQL tests passed."
if [ "${SKIP_CONCURRENCY:-0}" != 1 ]; then echo; "$here/concurrency_test.sh"; fi
