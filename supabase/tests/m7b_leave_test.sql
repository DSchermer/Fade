-- Leaving a group and handing over ownership.
\set ON_ERROR_STOP on
\set open_nba_game `cat fixtures/open_nba_game.json`
begin;

create procedure pg_temp.expect_error(p_sql text, p_like text) language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like p_like then return; end if;
    raise exception 'wrong error for [%]: got "%", wanted like "%"', p_sql, sqlerrm, p_like;
  end;
  raise exception 'expected an error but none was raised for [%]', p_sql;
end $$;
create procedure pg_temp.as_user(p_user text) language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', ('00000000-0000-0000-0000-0000000000' || p_user || '1'), true); end $$;

insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c','d']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave')) v(u, n);
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb);
create temp table ids (name text primary key, id uuid, code text);
grant all on ids to public;
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

create function pg_temp.gid(p text) returns uuid language sql as $$ select id from ids where name = p $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.row(p_group text, p_user text) returns group_members language sql as $$
  select * from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_user) $$;
create function pg_temp.healthy() returns boolean language sql as $$
  select not exists (select 1 from check_ledger_integrity()) and not exists (select 1 from check_betting_integrity()) $$;
create function pg_temp.mkt(p text) returns text language sql as $$
  select id from markets where case p when 'ml' then market_type = 'moneyline' when 'sp' then market_type = 'spreads' else market_type = 'totals' end order by id limit 1 $$;
-- Make a market final through the real finality rule, then settle.
create function pg_temp.finish(p_market text, p_prices text) returns void language plpgsql as $$
declare e jsonb;
begin
  select x into e from fx, jsonb_array_elements(fx.payload) x where x ->> 'id' = p_market;
  perform ingest_markets('nba', jsonb_build_array(e || jsonb_build_object('closed', true, 'umaResolutionStatus', 'resolved', 'outcomePrices', p_prices)), '2026-10-08 12:00+00');
  perform settle_resolved_markets();
end $$;

-- Group G: alice (owner), bobby, carol, dave. Everyone has 100 coins.
call pg_temp.as_user('a');
insert into ids (name, id) values ('g', create_group('Leave Crew'));
update ids set code = (select invite_code from groups where id = pg_temp.gid('g')) where name = 'g';
do $$ declare code text := (select code from ids where name = 'g'); u text; begin
  foreach u in array array['b', 'c', 'd'] loop
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || u || '1', true);
    perform join_group(code);
  end loop;
end $$;

-- Bobby wins 40 coins from carol (settled); dave sits out.
call pg_temp.as_user('b');
select post_offer(pg_temp.gid('g'), pg_temp.mkt('ml'), 0, 60, 100);
call pg_temp.as_user('c');
select take_offer((select id from offers where maker_id = pg_temp.u('b')), 100);
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');
do $$ begin
  assert (pg_temp.row('g', 'b')).available = 14000 and (pg_temp.row('g', 'c')).available = 6000, 'bobby +40, carol −40';
  assert pg_temp.healthy(), 'healthy before anyone leaves';
end $$;

-- ───────── Rules that stop you leaving ─────────
call pg_temp.as_user('a');
call pg_temp.expect_error($q$ select leave_group(pg_temp.gid('g')) $q$, '%owner_must_transfer%');
call pg_temp.as_user('d');
call pg_temp.expect_error($q$ select leave_group(gen_random_uuid()) $q$, '%not_a_member%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select leave_group(pg_temp.gid('g')) $q$, '%not_signed_in%');

-- an unsettled bet blocks leaving — as maker or as taker — and the block changes nothing (offers stay open)
call pg_temp.as_user('c');
select post_offer(pg_temp.gid('g'), pg_temp.mkt('sp'), 0, 50, 10);                                -- carol's open offer
select post_offer(pg_temp.gid('g'), pg_temp.mkt('tot'), 1, 50, 4);                                 -- another, will be partly taken
call pg_temp.as_user('d');
select take_offer((select id from offers where maker_id = pg_temp.u('c') and market_id = pg_temp.mkt('tot')), 2);   -- dave takes 2 shares: pending bet
do $$ declare before_c group_members; begin
  before_c := pg_temp.row('g', 'c');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
  begin perform leave_group(pg_temp.gid('g')); assert false, 'maker with a pending bet must not leave'; exception when others then assert sqlerrm = 'has_unsettled_bets', sqlerrm; end;
  assert pg_temp.row('g', 'c') = before_c, 'a refused leave changes nothing';
  assert (select count(*) from offers where maker_id = pg_temp.u('c') and status = 'open') = 2, 'her offers are still open after the refused leave';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);
  begin perform leave_group(pg_temp.gid('g')); assert false, 'taker with a pending bet must not leave'; exception when others then assert sqlerrm = 'has_unsettled_bets', sqlerrm; end;
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ───────── Leaving with a profit: offers refunded, profit kept in the lifetime score, coins burned ─────────
call pg_temp.as_user('b');
select post_offer(pg_temp.gid('g'), pg_temp.mkt('sp'), 1, 20, 50);                                 -- bobby has an open offer (10 coins escrowed)
do $$ declare r bigint; begin
  assert (pg_temp.row('g', 'b')).escrow = 1000, 'offer escrow';
  r := leave_group(pg_temp.gid('g'));
  assert r = 4000, 'realised profit is +40 coins, got ' || r;
  assert (pg_temp.row('g', 'b')).status = 'left' and (pg_temp.row('g', 'b')).available = 0 and (pg_temp.row('g', 'b')).escrow = 0, 'nothing left in the group';
  assert (pg_temp.row('g', 'b')).granted = 0 and (pg_temp.row('g', 'b')).buyback_coins = 0 and (pg_temp.row('g', 'b')).realized_profit = 4000, 'baseline cleared, profit recorded';
  assert (select status from offers where maker_id = pg_temp.u('b') and market_id = pg_temp.mkt('sp')) = 'cancelled', 'his offer was cancelled';
  assert (select cancel_reason from offers where maker_id = pg_temp.u('b') and market_id = pg_temp.mkt('sp')) = 'left', 'with the reason "left"';
  assert (select lifetime_closed_profit from profiles where id = pg_temp.u('b')) = 4000, 'profit kept in the lifetime score';
  assert (select count(*) from ledger where kind = 'leave_burn' and user_id = pg_temp.u('b')) = 1, 'one burn in the ledger';
  assert pg_temp.healthy(), 'every group still sums to zero after a winner leaves';
end $$;
call pg_temp.expect_error($q$ select leave_group(pg_temp.gid('g')) $q$, '%not_a_member%');                          -- already gone
set local role authenticated;
call pg_temp.as_user('a');
do $$ begin
  assert (select count(*) from group_leaderboard where group_id = pg_temp.gid('g')) = 3, 'three members remain on the leaderboard';
  assert not exists (select 1 from group_leaderboard where group_id = pg_temp.gid('g') and username = 'bobby'), 'bobby is gone from it';
end $$;
call pg_temp.as_user('b');
do $$ declare s record; begin
  assert (select count(*) from groups where id = pg_temp.gid('g')) = 0 and (select count(*) from group_leaderboard) = 0, 'a leaver can no longer see the group';
  select * into s from my_score;
  assert s.closed_profit = 4000 and s.live_profit = 0 and s.score = 4000, 'score keeps the +40 coins after leaving';
end $$;
reset role;

-- ───────── Coming back: 0 coins, busted, buyback per policy ─────────
call pg_temp.as_user('b');
select join_group((select code from ids where name = 'g'));
do $$ declare s record; begin
  assert (pg_temp.row('g', 'b')).status = 'active' and (pg_temp.row('g', 'b')).available = 0 and (pg_temp.row('g', 'b')).granted = 0, 'back with nothing and no new grant';
  select * into s from buyback_status(pg_temp.gid('g'));
  assert s.busted and s.can_claim, 'a returning member with 0 coins is busted and may buy back';
  assert (select net_profit from group_leaderboard where group_id = pg_temp.gid('g') and user_id = pg_temp.u('b')) = 0, 'net profit restarts at 0';
  assert pg_temp.healthy(), 'healthy after rejoin';
end $$;
select claim_buyback(pg_temp.gid('g'));
do $$ declare s record; begin
  assert (pg_temp.row('g', 'b')).available = 10000 and (pg_temp.row('g', 'b')).buyback_count = 1, 'bought back in';
  assert (select net_profit from group_leaderboard where group_id = pg_temp.gid('g') and user_id = pg_temp.u('b')) = 0, 'he holds exactly what he received (no starting grant this time), so net profit from the rejoin is 0';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ───────── Ownership ─────────
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select transfer_ownership(pg_temp.gid('g'), pg_temp.u('c')) $q$, '%not_group_owner%');
call pg_temp.as_user('a');
call pg_temp.expect_error($q$ select transfer_ownership(pg_temp.gid('g'), pg_temp.u('a')) $q$, '%invalid_transfer%');
call pg_temp.expect_error($q$ select transfer_ownership(pg_temp.gid('g'), null) $q$, '%invalid_transfer%');
update group_members set status = 'left', granted = 0 where group_id = pg_temp.gid('g') and user_id = pg_temp.u('d') and false;   -- (no-op: dave stays)
call pg_temp.expect_error($q$ select transfer_ownership(pg_temp.gid('g'), gen_random_uuid()) $q$, '%target_not_member%');
select transfer_ownership(pg_temp.gid('g'), pg_temp.u('c'));
do $$ begin
  assert (pg_temp.row('g', 'c')).role = 'owner' and (pg_temp.row('g', 'a')).role = 'member', 'ownership handed to carol';
  assert (select count(*) from group_members where group_id = pg_temp.gid('g') and role = 'owner' and status = 'active') = 1, 'exactly one owner';
end $$;
call pg_temp.expect_error($q$ select transfer_ownership(pg_temp.gid('g'), pg_temp.u('b')) $q$, '%not_group_owner%');     -- alice is no longer the owner
do $$ begin
  begin  -- the database refuses a second owner even if some bug tried
    update group_members set role = 'owner' where group_id = pg_temp.gid('g') and user_id = pg_temp.u('a');
    assert false, 'two owners accepted';
  exception when unique_violation then null; end;
end $$;
-- the old owner is now an ordinary member and may leave (no bets of hers)
call pg_temp.as_user('a');
select leave_group(pg_temp.gid('g'));
do $$ begin assert (pg_temp.row('g', 'a')).status = 'left', 'alice left after handing over'; end $$;
-- the new owner cannot leave while others remain
call pg_temp.as_user('c');
call pg_temp.expect_error($q$ select leave_group(pg_temp.gid('g')) $q$, '%owner_must_transfer%');

-- ───────── A sole owner may leave; the empty group's code stops working ─────────
call pg_temp.as_user('d');
insert into ids (name, id) values ('solo', create_group('Solo'));
update ids set code = (select invite_code from groups where id = pg_temp.gid('solo')) where name = 'solo';
select leave_group(pg_temp.gid('solo'));
call pg_temp.expect_error($q$ select join_group((select code from ids where name = 'solo')) $q$, '%group_not_found%');
do $$ begin assert pg_temp.healthy(), 'healthy'; end $$;

-- ───────── Permissions ─────────
set local role anon;
call pg_temp.expect_error($q$ select leave_group(gen_random_uuid()) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select transfer_ownership(gen_random_uuid(), gen_random_uuid()) $q$, '%permission denied%');
reset role;

-- ───────── The books catch tampering ─────────
do $$ begin
  assert pg_temp.healthy(), 'healthy before tampering';
  update profiles set lifetime_closed_profit = lifetime_closed_profit + 1 where id = pg_temp.u('b');
  assert exists (select 1 from check_ledger_integrity() where check_name = 'closed_profit_mismatch'), 'a score that does not match what was realised is detected';
  update profiles set lifetime_closed_profit = lifetime_closed_profit - 1 where id = pg_temp.u('b');
  update group_members set realized_profit = realized_profit + 1 where group_id = pg_temp.gid('g') and user_id = pg_temp.u('a');
  assert exists (select 1 from check_ledger_integrity() where check_name = 'group_profit_not_zero_sum'), 'profit that appears from nowhere is detected';
  update group_members set realized_profit = realized_profit - 1 where group_id = pg_temp.gid('g') and user_id = pg_temp.u('a');
  update group_members set granted = 5 where group_id = pg_temp.gid('g') and user_id = pg_temp.u('a');
  assert exists (select 1 from check_ledger_integrity() where check_name = 'left_member_not_clean'), 'a leaver with leftovers is detected';
end $$;
rollback;
