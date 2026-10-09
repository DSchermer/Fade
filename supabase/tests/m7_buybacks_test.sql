-- Milestone 7 tests: buybacks (unlimited / weekly / vote), the leaderboard maths, the global score.
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
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n
    from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave')) v(u, n);
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb);
create temp table ids (name text primary key, id uuid);
grant all on ids to public;
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

-- Three groups, all created by alice: unlimited buybacks, 2-per-week buybacks, buybacks by vote.
call pg_temp.as_user('a');
insert into ids values ('gu', create_group('Unlimited', 10000, 'unlimited', null, 10000));
insert into ids values ('gw', create_group('Weekly', 10000, 'weekly', 2, 5000));
insert into ids values ('gv', create_group('Vote', 10000, 'vote'));
do $$ declare code text; begin
  select invite_code into code from groups where id = (select id from ids where name = 'gu');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true); perform join_group(code);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true); perform join_group(code);
  select invite_code into code from groups where id = (select id from ids where name = 'gw');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true); perform join_group(code);
  select invite_code into code from groups where id = (select id from ids where name = 'gv');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true); perform join_group(code);
end $$;

create function pg_temp.gid(p text) returns uuid language sql as $$ select id from ids where name = p $$;
create function pg_temp.healthy() returns boolean language sql as $$
  select not exists (select 1 from check_ledger_integrity()) and not exists (select 1 from check_betting_integrity()) $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.row(p_group text, p_user text) returns group_members language sql as $$
  select * from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_user) $$;
create function pg_temp.net(p_group text, p_user text) returns bigint language sql as $$
  select net_profit from group_leaderboard where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_user) $$;
-- Simulate losing: move all of someone's available coins to someone else (a zero-sum transfer, as a lost bet would be).
create procedure pg_temp.lose_everything(p_group text, p_loser text, p_winner text) language plpgsql as $$
declare v_amt bigint; v_tx uuid := gen_random_uuid();
begin
  select available into v_amt from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_loser);
  if v_amt > 0 then
    perform ledger_post(v_tx, pg_temp.gid(p_group), pg_temp.u(p_loser),  'available', -v_amt, 'escrow_release');
    perform ledger_post(v_tx, pg_temp.gid(p_group), pg_temp.u(p_winner), 'available',  v_amt, 'escrow_release');
  end if;
end $$;
do $$ begin assert pg_temp.healthy(), 'healthy at start'; end $$;

-- ───────── Leaderboard: net profit, raw balance, buyback counts ─────────
-- A real bet: alice backs outcome 0 at 60¢ for 100 shares, bobby takes it all, alice's side wins (via the real settle path).
create function pg_temp.settle_moneyline_for_maker() returns void language plpgsql as $$
declare mk text := (select id from markets where market_type = 'moneyline'); e jsonb;
begin
  select x into e from fx, jsonb_array_elements(fx.payload) x where x ->> 'id' = mk;
  perform ingest_markets('nba', jsonb_build_array(e || '{"closed":true,"umaResolutionStatus":"resolved","outcomePrices":"[\"1\", \"0\"]"}'::jsonb), '2026-10-08 12:00+00');
  perform settle_resolved_markets();
end $$;
call pg_temp.as_user('a');
select post_offer(pg_temp.gid('gu'), (select id from markets where market_type = 'moneyline'), 0, 60, 100);
call pg_temp.as_user('b');
select take_offer((select id from offers where group_id = pg_temp.gid('gu')), 100);
select pg_temp.settle_moneyline_for_maker();
do $$ begin
  assert (pg_temp.row('gu', 'a')).available = 14000, 'alice won 40 coins';
  assert pg_temp.net('gu', 'a') = 4000 and pg_temp.net('gu', 'b') = -4000 and pg_temp.net('gu', 'c') = 0, 'net profit = balance − granted − buybacks';
  assert (select sum(net_profit) from group_leaderboard where group_id = pg_temp.gid('gu')) = 0, 'a group''s profits add up to zero';
  assert pg_temp.healthy(), 'healthy after settlement';
end $$;

-- ───────── Buyback rules: unlimited group ─────────
call pg_temp.as_user('c');
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gu')) $q$, '%not_busted%');                     -- carol still has 100 coins
do $$ declare s record; begin
  select * into s from buyback_status(pg_temp.gid('gu'));
  assert not s.busted and not s.can_claim and s.reason = 'not_busted' and s.amount = 10000 and s.policy = 'unlimited', 'status for a solvent member';
end $$;

call pg_temp.as_user('b');                                    -- bobby has 60 coins left → move them away → broke
reset role;
call pg_temp.lose_everything('gu', 'b', 'a');
call pg_temp.as_user('b');
do $$ declare s record; id uuid; begin
  select * into s from buyback_status(pg_temp.gid('gu'));
  assert s.busted and s.can_claim and s.reason is null and s.amount = 10000, 'broke → can buy back';
  id := claim_buyback(pg_temp.gid('gu'));
  assert (pg_temp.row('gu', 'b')).available = 10000 and (pg_temp.row('gu', 'b')).buyback_count = 1 and (pg_temp.row('gu', 'b')).buyback_coins = 10000, 'got 100 coins; counters bumped';
  assert (select amount from buybacks where group_id = pg_temp.gid('gu') and user_id = pg_temp.u('b')) = 10000, 'buyback recorded';
  assert pg_temp.net('gu', 'b') = -10000, 'buybacks count AGAINST you: he is down 100 coins even though he holds 100';
  assert pg_temp.net('gu', 'a') = 10000, 'the winner is up what the loser lost';
  assert (select sum(net_profit) from group_leaderboard where group_id = pg_temp.gid('gu')) = 0, 'still zero-sum';
  assert pg_temp.healthy(), 'healthy after buyback';
end $$;
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gu')) $q$, '%not_busted%');                     -- no longer broke

-- coins tied up in an open offer or a pending bet do NOT count as broke
select post_offer(pg_temp.gid('gu'), (select id from markets where market_type = 'totals' order by id limit 1), 0, 50, 200);   -- all 100 coins in escrow
do $$ declare s record; begin
  assert (pg_temp.row('gu', 'b')).available = 0 and (pg_temp.row('gu', 'b')).escrow = 10000, 'everything is tied up';
  select * into s from buyback_status(pg_temp.gid('gu'));
  assert not s.busted and not s.can_claim, 'not busted while coins are in escrow';
end $$;
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gu')) $q$, '%not_busted%');
select cancel_offer((select id from offers where maker_id = pg_temp.u('b') and status = 'open'));

-- unlimited really is unlimited: broke again → buy back again → count 2
reset role;
call pg_temp.lose_everything('gu', 'b', 'a');
call pg_temp.as_user('b');
select claim_buyback(pg_temp.gid('gu'));
do $$ begin
  assert (pg_temp.row('gu', 'b')).buyback_count = 2 and (pg_temp.row('gu', 'b')).buyback_coins = 20000, 'second buyback';
  assert pg_temp.net('gu', 'b') = -20000, 'net profit shows both buybacks';
end $$;

-- ───────── Weekly limit (2 per rolling 7 days, 50 coins each) ─────────
create function pg_temp.set_clock(p text) returns void language sql as $$ update clock_override set at = p::timestamptz $$;
reset role;
call pg_temp.lose_everything('gw', 'b', 'a');
call pg_temp.as_user('b');
select claim_buyback(pg_temp.gid('gw'));                                               -- #1 on day 0
select pg_temp.set_clock('2026-10-10 12:00+00');                                       -- two days later
reset role; call pg_temp.lose_everything('gw', 'b', 'a'); call pg_temp.as_user('b');
select claim_buyback(pg_temp.gid('gw'));                                               -- #2 on day 2
reset role; call pg_temp.lose_everything('gw', 'b', 'a'); call pg_temp.as_user('b');
do $$ declare s record; begin
  select * into s from buyback_status(pg_temp.gid('gw'));
  assert s.busted and not s.can_claim and s.reason = 'weekly_limit' and s.used = 2 and s.allowed = 2, 'limit reached';
  assert s.next_available = '2026-10-15 12:00+00', 'the first buyback (day 0) ages out on day 7';
end $$;
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gw')) $q$, '%buyback_limit_reached%');
select pg_temp.set_clock('2026-10-15 11:59:59+00');
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gw')) $q$, '%buyback_limit_reached%');       -- one second early
select pg_temp.set_clock('2026-10-15 12:00:01+00');
do $$ declare s record; begin
  select * into s from buyback_status(pg_temp.gid('gw'));
  assert s.can_claim and s.used = 1, 'the oldest buyback has aged out';
end $$;
select claim_buyback(pg_temp.gid('gw'));
do $$ begin assert (pg_temp.row('gw', 'b')).buyback_count = 3 and (pg_temp.row('gw', 'b')).buyback_coins = 15000, 'three buybacks of 50 coins in total'; end $$;
select pg_temp.set_clock('2026-10-08 12:00+00');

-- ───────── Vote policy: no automatic buyback ─────────
reset role; call pg_temp.lose_everything('gv', 'c', 'a'); call pg_temp.as_user('c');
do $$ declare s record; begin
  select * into s from buyback_status(pg_temp.gid('gv'));
  assert s.busted and not s.can_claim and s.reason = 'needs_vote' and s.policy = 'vote', 'vote groups need a vote';
end $$;
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gv')) $q$, '%buyback_requires_vote%');

-- ───────── Who may do what ─────────
call pg_temp.as_user('d');                                    -- dave is in none of these groups
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gu')) $q$, '%not_a_member%');
call pg_temp.expect_error($q$ select * from buyback_status(pg_temp.gid('gu')) $q$, '%not_a_member%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('gu')) $q$, '%not_signed_in%');

set local role authenticated;
call pg_temp.as_user('b');
do $$ begin
  assert (select count(*) from buyback_listing where group_id = pg_temp.gid('gu')) = 2, 'members see the group''s buyback history';
  assert (select count(*) from group_leaderboard where group_id = pg_temp.gid('gu')) = 3, 'members see the leaderboard';
  assert (select count(*) from group_leaderboard where group_id = pg_temp.gid('gv')) = 0, 'but not the leaderboard of a group they are not in';
end $$;
call pg_temp.expect_error($q$ insert into buybacks (group_id, season_id, user_id, amount) select group_id, season_id, user_id, 99999999 from buybacks limit 1 $q$, '%permission denied%');
call pg_temp.expect_error($q$ update group_members set buyback_coins = 0 $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from buyback_eligibility(pg_temp.gid('gu'), pg_temp.u('b'), now()) $q$, '%permission denied%');
call pg_temp.as_user('d');
do $$ begin
  assert (select count(*) from buyback_listing) = 0 and (select count(*) from group_leaderboard) = 0, 'outsiders see nothing';
end $$;
reset role;
set local role anon;
call pg_temp.expect_error($q$ select claim_buyback(gen_random_uuid()) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from buyback_status(gen_random_uuid()) $q$, '%permission denied%');
reset role;

-- ───────── Global score: finished seasons + live profit across every group ─────────
update profiles set lifetime_closed_profit = 2500 where id = pg_temp.u('a');
set local role authenticated;
call pg_temp.as_user('a');
do $$ declare s record; live bigint; begin
  select * into s from my_score;
  select sum(net_profit) into live from group_leaderboard where user_id = pg_temp.u('a');
  assert s.closed_profit = 2500 and s.live_profit = live and s.score = 2500 + live, 'score = closed + live profit across all groups';
  assert s.live_profit > 0, 'alice is up overall';
  assert s.wins = (select lifetime_wins from profiles where id = pg_temp.u('a')), 'record shown with the score';
  assert (select count(*) from my_score) = 1, 'you only ever see your own score';
end $$;
call pg_temp.as_user('b');
do $$ declare s record; live bigint; begin
  select * into s from my_score;
  select sum(net_profit) into live from group_leaderboard where user_id = pg_temp.u('b');
  assert s.score = live and s.closed_profit = 0, 'bobby: live profit only';
  assert live < 0, 'bobby is down (buybacks count against him)';
end $$;
reset role;

-- ───────── Zero-sum is enforced by the integrity check ─────────
do $$ begin
  assert pg_temp.healthy(), 'healthy at the end';
  perform ledger_post(gen_random_uuid(), pg_temp.gid('gu'), pg_temp.u('c'), 'available', 1, 'grant');   -- coins appear but baseline says otherwise?
  assert pg_temp.healthy(), 'a grant raises the baseline too, so profits stay zero-sum';
  update group_members set granted = granted - 1 where group_id = pg_temp.gid('gu') and user_id = pg_temp.u('c');
  assert exists (select 1 from check_ledger_integrity() where check_name = 'group_profit_not_zero_sum'), 'a drifting baseline is detected';
end $$;

rollback;
