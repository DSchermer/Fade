#!/usr/bin/env bash
# "Contract" test: does what the database returns still match what the iPhone app's Swift models expect?
# Builds a scratch database, fills it through the real server functions, saves the JSON each app screen would receive,
# then decodes it with the app's model types (needs a local Postgres AND a Swift toolchain: https://www.swift.org/install/).
# Usage: supabase/tests/contract/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="fade_contract_$$"
out="$(mktemp -d)"; chmod 777 "$out"
if [ "$(id -u)" = 0 ] && id postgres >/dev/null 2>&1; then pg=(runuser -u postgres -- psql); else pg=(psql); fi
run() { "${pg[@]}" -v ON_ERROR_STOP=1 -q "$@"; }
trap 'run -d postgres -c "drop database if exists $db" >/dev/null 2>&1 || true; rm -rf "$out"' EXIT
run -d postgres -c "create database $db" >/dev/null
run -d "$db" < "$here/../00_local_auth_stub.sql" >/dev/null
for f in "$here"/../../migrations/*.sql; do run -d "$db" < "$f" >/dev/null; done
( cd "$here" && run -d "$db" < seed.sql >/dev/null )
( cd "$out" && run -d "$db" -v "nhl_fixture=$(cat "$here/../fixtures/open_nhl_moneyline.json")" < "$here/dump.sql" >/dev/null )
cd "$here" && FADE_CONTRACT_DIR="$out" swift test 2>&1 | grep -E "error|failed|Executed" | tail -25
