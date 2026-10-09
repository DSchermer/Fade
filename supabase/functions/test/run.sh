#!/usr/bin/env bash
# Tests the three Edge Functions against pretend servers (no Apple or Supabase account needed). Needs Node 22+.
# Usage: supabase/functions/test/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for f in send-push apple-link apple-delete-account; do cp "$here/../$f/index.ts" "$tmp/$f.mts"; done
cp "$here/harness.mjs" "$tmp/harness.mjs"
status=0
for f in send-push apple-link apple-delete-account; do
  echo "=== $f"
  FN_DIR="$tmp" node --experimental-strip-types "$tmp/harness.mjs" "$f" 2>&1 | grep -v -i "experimentalwarning\|trace-warnings" | tee "$tmp/out.txt"
  if grep -q "^FAIL" "$tmp/out.txt" || ! grep -q "^ok" "$tmp/out.txt"; then status=1; fi
done
[ "$status" = 0 ] && echo "All Edge Function tests passed." || { echo "Edge Function tests FAILED."; exit 1; }
