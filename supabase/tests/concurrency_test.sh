#!/usr/bin/env bash
# Many people acting AT THE SAME MOMENT. Uses real parallel database connections and committed data.
#   1. 60 people race to take the last 50 shares of one offer      → exactly 50 succeed
#   2. one person fires 10 simultaneous takes with money for only 3 → exactly 3 succeed, balance never negative
#   3. a taker and the maker's cancel race over the same offer     → exactly one wins, every round
# Afterwards every integrity check must pass.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="fade_conc_$$"
if [ "$(id -u)" = 0 ] && id postgres >/dev/null 2>&1; then pg=(runuser -u postgres -- psql); else pg=(psql); fi
q()  { "${pg[@]}" -X -q -At -v ON_ERROR_STOP=1 -d "$db" "$@"; }
trap '"${pg[@]}" -X -q -d postgres -c "drop database if exists $db" >/dev/null 2>&1 || true; rm -rf "$out"' EXIT
out="$(mktemp -d)"; chmod 777 "$out"

"${pg[@]}" -X -q -d postgres -c "create database $db" >/dev/null
q < "$here/00_local_auth_stub.sql" >/dev/null
for f in "$here"/../migrations/*.sql; do q < "$f" >/dev/null; done

uid() { printf '00000000-0000-0000-0000-%012x' "$1"; }
MAKER=$(uid 1); TAKER=$(uid 2)

# ── setup (committed): 1 maker, 1 special taker, 60 racers; one real NBA game; clock fixed before the game
q <<SQL >/dev/null
insert into auth.users (id) select ('00000000-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid from generate_series(1, 62) i;
insert into profiles (id, username) select ('00000000-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid, 'user' || i from generate_series(1, 62) i;
SQL
# group + members + market (done as separate committed steps so ids can be reused)
GROUP=$(q -c "select set_config('request.jwt.claim.sub', '$MAKER', false); select create_group('Race');" | tail -1)
CODE=$(q -c "select invite_code from groups where id = '$GROUP'")
for i in $(seq 2 62); do q -c "select set_config('request.jwt.claim.sub', '$(uid $i)', false); select join_group('$CODE');" >/dev/null; done
# the maker gets a large bankroll so offers are affordable
q -c "select ledger_post(gen_random_uuid(), '$GROUP', '$MAKER', 'available', 100000000, 'buyback');" >/dev/null
fixture="$here/fixtures/open_nba_game.json"
q -c "select ingest_markets('nba', \$j\$$(cat "$fixture")\$j\$::jsonb, '2026-10-08 12:00+00');" >/dev/null
MARKET=$(q -c "select id from markets where market_type = 'moneyline'")
q -c "insert into clock_override (at) values ('2026-10-08 12:00+00');" >/dev/null

take() { # take <user#> <offer> <shares> <label>
  local o m; o=$(q -c "select set_config('request.jwt.claim.sub', '$(uid "$1")', false); select take_offer('$2', $3);" 2>&1) || true
  m=$(printf '%s\n' "$o" | grep -m1 '^ERROR' || true)
  if [ -n "$m" ]; then echo "${m#*ERROR:  }" >> "$out/$4"; else echo ok >> "$out/$4"; fi
}
export -f take q uid; export db out pg_str="" 
count() { grep -c "^$2\$" "$out/$1" 2>/dev/null || true; }
healthy() { [ -z "$(q -c "select 1 from check_ledger_integrity() union all select 1 from check_betting_integrity()")" ]; }

echo "1) 60 people race for 50 shares…"
OFFER1=$(q -c "select set_config('request.jwt.claim.sub', '$MAKER', false); select post_offer('$GROUP', '$MARKET', 0, 50, 50);" | tail -1)
for i in $(seq 3 62); do ( take "$i" "$OFFER1" 1 race1 ) & done; wait
ok=$(count race1 ok); full=$(count race1 offer_not_open)
[ "$ok" = 50 ] && [ "$full" = 10 ] || { echo "FAIL: expected 50 ok + 10 offer_not_open, got $ok ok / $full offer_not_open"; cat "$out/race1" | sort | uniq -c; exit 1; }
[ "$(q -c "select shares_open || '/' || status from offers where id = '$OFFER1'")" = "0/filled" ] || { echo "FAIL: offer should be filled"; exit 1; }
[ "$(q -c "select count(*) from bets where offer_id = '$OFFER1'")" = 50 ] || { echo "FAIL: expected 50 bets"; exit 1; }
healthy || { echo "FAIL: integrity broken after race 1"; q -c "select * from check_ledger_integrity() union all select * from check_betting_integrity()"; exit 1; }
echo "   ok: exactly 50 filled, 10 turned away"

echo "2) one person, 10 simultaneous takes, money for 3…"
OFFER2=$(q -c "select set_config('request.jwt.claim.sub', '$MAKER', false); select post_offer('$GROUP', '$MARKET', 0, 70, 1000);" | tail -1)
q -c "select available from group_members where group_id = '$GROUP' and user_id = '$TAKER'" > "$out/taker_before"
BEFORE=$(cat "$out/taker_before")
per=$(( 100 * 30 ))           # each take of 100 shares @ 30¢ costs 3000
affordable=$(( BEFORE / per ))
for k in $(seq 1 10); do ( take 2 "$OFFER2" 100 race2 ) & done; wait
ok=$(count race2 ok); poor=$(count race2 insufficient_balance)
[ "$ok" = "$affordable" ] && [ $((ok + poor)) = 10 ] || { echo "FAIL: expected $affordable ok + rest insufficient_balance, got $ok ok / $poor poor"; sort "$out/race2" | uniq -c; exit 1; }
AFTER=$(q -c "select available from group_members where group_id = '$GROUP' and user_id = '$TAKER'")
[ "$AFTER" -ge 0 ] && [ "$AFTER" = "$((BEFORE - ok * per))" ] || { echo "FAIL: taker balance wrong ($BEFORE → $AFTER, $ok takes)"; exit 1; }
healthy || { echo "FAIL: integrity broken after race 2"; exit 1; }
echo "   ok: $ok succeeded of 10 (balance $BEFORE → $AFTER, never negative)"

echo "2b) one person takes from 10 DIFFERENT offers at once, money for 3…"
for k in $(seq 1 10); do
  q -c "select set_config('request.jwt.claim.sub', '$MAKER', false); select post_offer('$GROUP', '$MARKET', 0, 70, 100);" | tail -1 >> "$out/offers2b"
done
RICH=$(uid 3)
BEFORE=$(q -c "select available from group_members where group_id = '$GROUP' and user_id = '$RICH'")
affordable=$(( BEFORE / 3000 ))
while read -r o; do ( take 3 "$o" 100 race2b ) & done < "$out/offers2b"; wait
ok=$(count race2b ok); poor=$(count race2b insufficient_balance)
[ "$ok" = "$affordable" ] && [ $((ok + poor)) = 10 ] || { echo "FAIL: expected $affordable ok + rest insufficient_balance, got $ok ok / $poor poor"; sort "$out/race2b" | uniq -c; exit 1; }
AFTER=$(q -c "select available from group_members where group_id = '$GROUP' and user_id = '$RICH'")
[ "$AFTER" -ge 0 ] && [ "$AFTER" = "$((BEFORE - ok * 3000))" ] || { echo "FAIL: balance wrong ($BEFORE → $AFTER)"; exit 1; }
healthy || { echo "FAIL: integrity broken after race 2b"; exit 1; }
echo "   ok: $ok succeeded of 10 across different offers (balance $BEFORE → $AFTER)"

echo "3) take vs cancel, 25 rounds…"
for r in $(seq 1 25); do
  O=$(q -c "select set_config('request.jwt.claim.sub', '$MAKER', false); select post_offer('$GROUP', '$MARKET', 1, 20, 10);" | tail -1)
  ( take $((3 + r % 50)) "$O" 10 race3 ) &
  ( c=$(q -c "select set_config('request.jwt.claim.sub', '$MAKER', false); select cancel_offer('$O');" 2>&1) || true
    if printf '%s\n' "$c" | grep -q '^ERROR'; then echo cancel_lost >> "$out/race3"; else echo cancel_won >> "$out/race3"; fi ) &
  wait
done
tk=$(count race3 ok); cw=$(count race3 cancel_won)
[ "$((tk + cw))" = 25 ] || { echo "FAIL: each round must have exactly one winner (take won $tk, cancel won $cw)"; sort "$out/race3" | uniq -c; exit 1; }
healthy || { echo "FAIL: integrity broken after race 3"; q -c "select * from check_ledger_integrity() union all select * from check_betting_integrity()"; exit 1; }
echo "   ok: take won $tk rounds, cancel won $cw, never both"

total=$(q -c "select sum(available + escrow) from group_members where group_id = '$GROUP'")
expected=$(q -c "select sum(delta) from ledger where group_id = '$GROUP' and kind in ('grant', 'buyback')")
[ "$total" = "$expected" ] || { echo "FAIL: coins created or destroyed ($total vs $expected)"; exit 1; }
echo "All concurrency tests passed. (group holds exactly the $expected hundredths it was given)"
