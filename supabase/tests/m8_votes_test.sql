-- Milestone 8 tests: votes, group resets, buyback votes, season history.
\set ON_ERROR_STOP on
\set open_nba_game `cat fixtures/open_nba_game.json`
\set open_nfl `cat fixtures/open_nfl_spreads.json`
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

insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c','d','e','f']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n
    from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave'),('e','erin'),('f','frank')) v(u, n);
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb), ('nfl', :'open_nfl'::jsonb);
select ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-10-08 12:00+00');
create temp table ids (name text primary key, id uuid, code text);
grant all on ids to public;
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

create function pg_temp.gid(p text) returns uuid language sql as $$ select id from ids where name = p $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.row(p_group text, p_user text) returns group_members language sql as $$
  select * from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_user) $$;
create function pg_temp.healthy() returns boolean language sql as $$
  select not exists (select 1 from check_ledger_integrity()) and not exists (select 1 from check_betting_integrity())
     and not exists (select 1 from check_season_integrity()) $$;
create function pg_temp.mkt(p text, n integer default 0) returns text language sql as $$
  select id from markets where case p when 'ml' then market_type = 'moneyline' when 'sp' then market_type = 'spreads' else market_type = 'totals' end
   order by id offset n limit 1 $$;
create function pg_temp.set_clock(p text) returns void language sql as $$ update clock_override set at = p::timestamptz $$;
create function pg_temp.finish(p_market text, p_prices text) returns void language plpgsql as $$
declare e jsonb;
begin
  select x into e from fx, jsonb_array_elements(fx.payload) x where x ->> 'id' = p_market;
  perform ingest_markets('nba', jsonb_build_array(e || jsonb_build_object('closed', true, 'umaResolutionStatus', 'resolved', 'outcomePrices', p_prices)), '2026-10-08 12:00+00');
  perform settle_resolved_markets();
end $$;
create procedure pg_temp.lose_everything(p_group text, p_loser text, p_winner text) language plpgsql as $$
declare v_amt bigint; v_tx uuid := gen_random_uuid();
begin
  select available into v_amt from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_loser);
  if v_amt > 0 then
    perform ledger_post(v_tx, pg_temp.gid(p_group), pg_temp.u(p_loser),  'available', -v_amt, 'escrow_release');
    perform ledger_post(v_tx, pg_temp.gid(p_group), pg_temp.u(p_winner), 'available',  v_amt, 'escrow_release');
  end if;
end $$;
-- Create a group owned by alice with the given members (letters) joined.
create procedure pg_temp.make_group(p_name text, p_members text[], p_policy text default 'unlimited') language plpgsql as $$
declare v_code text; v_id uuid; u text;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('a')::text, true);
  v_id := create_group(p_name, 10000, p_policy, null, 10000);
  insert into ids (name, id) values (p_name, v_id);
  select invite_code into v_code from groups where id = v_id;
  foreach u in array p_members loop
    perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true);
    perform join_group(v_code);
  end loop;
end $$;
create function pg_temp.vote_of(p_group text, p_kind text) returns uuid language sql as $$
  select id from votes where group_id = pg_temp.gid(p_group) and kind = p_kind order by created_at desc, id limit 1 $$;

-- ═════════ 1. THE RESET, with real history behind it ═════════
call pg_temp.make_group('Reset Crew', array['b','c','d','e']);
-- (a) a settled bet: alice +40, bobby −20, carol −20
call pg_temp.as_user('a');
select post_offer(pg_temp.gid('Reset Crew'), pg_temp.mkt('ml'), 0, 60, 100);
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('a')), 50);
call pg_temp.as_user('c'); select take_offer((select id from offers where maker_id = pg_temp.u('a')), 50);
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');
-- (b) carol loses everything else and buys back once
reset role;
call pg_temp.lose_everything('Reset Crew', 'c', 'a');
call pg_temp.as_user('c'); select claim_buyback(pg_temp.gid('Reset Crew'));
-- (c) pending business at reset time: a bet on a game, and an open offer with a partial fill
call pg_temp.as_user('d'); select post_offer(pg_temp.gid('Reset Crew'), pg_temp.mkt('sp'), 1, 20, 10);
call pg_temp.as_user('e'); select take_offer((select id from offers where maker_id = pg_temp.u('d') and market_id = pg_temp.mkt('sp')), 10);
call pg_temp.as_user('d'); select post_offer(pg_temp.gid('Reset Crew'), pg_temp.mkt('tot'), 0, 50, 20);
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('d') and market_id = pg_temp.mkt('tot')), 5);
do $$ begin
  assert (select count(*) from bets where status = 'pending') = 2 and (select count(*) from offers where status = 'open') = 1, 'two pending bets and one open offer before the reset';
  assert pg_temp.healthy(), 'healthy before the reset';
end $$;
create temp table before_reset as
  select user_id, username, balance, net_profit, buyback_count from group_leaderboard where group_id = pg_temp.gid('Reset Crew');
create temp table rec_before as select id, lifetime_wins w, lifetime_losses l, lifetime_closed_profit cp from profiles;
do $$ begin
  assert (select sum(net_profit) from before_reset) = 0, 'profits sum to zero before the reset';
  assert (select net_profit from before_reset where username = 'alice') > 0 and (select net_profit from before_reset where username = 'bobby') < 0, 'real winners and losers exist';
end $$;

-- who may call, and what
call pg_temp.as_user('f');
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Reset Crew'), 'reset') $q$, '%not_a_member%');
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Reset Crew'), 'party') $q$, '%invalid_vote_kind%');
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Reset Crew'), null) $q$, '%invalid_vote_kind%');
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Reset Crew'), 'buyback') $q$, '%buyback_vote_not_allowed%');   -- this group has unlimited buybacks
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Reset Crew'), 'reset') $q$, '%not_signed_in%');

-- bobby calls a reset vote
call pg_temp.as_user('b');
select call_vote(pg_temp.gid('Reset Crew'), 'reset');
do $$ declare v record; begin
  select * into v from vote_listing where kind = 'reset' and group_id = pg_temp.gid('Reset Crew');
  assert v.status = 'open' and v.yes_count = 1 and v.no_count = 0 and v.electorate = 5, 'the caller''s yes is counted: 1 of 5';
  assert v.closes_at - v.opens_at = interval '24 hours', 'a 24 hour window';
  assert v.my_vote is true, 'my_vote shows my ballot';
end $$;
call pg_temp.as_user('c');
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Reset Crew'), 'reset') $q$, '%vote_already_open%');
do $$ begin
  assert vote_quorum(1) = 1 and vote_quorum(2) = 2 and vote_quorum(3) = 2 and vote_quorum(5) = 2 and vote_quorum(8) = 2 and vote_quorum(9) = 3 and vote_quorum(20) = 5,
         'quorum = min(members, max(2, ceil 25%))';
end $$;

-- the tally moves, but nothing happens until the result is certain
do $$ declare vid uuid := pg_temp.vote_of('Reset Crew', 'reset'); begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('c')::text, true); assert cast_vote(vid, true)  = 'open', 'yes 2 of 5: still open';
  perform set_config('request.jwt.claim.sub', pg_temp.u('d')::text, true); assert cast_vote(vid, false) = 'open', 'no 1';
  perform set_config('request.jwt.claim.sub', pg_temp.u('e')::text, true); assert cast_vote(vid, false) = 'open', 'no 2: four of five voted and it is still undecided';
  assert (select count(*) from seasons where group_id = pg_temp.gid('Reset Crew')) = 1, 'no reset yet';
  assert (select count(*) from offers where status = 'open') = 1 and (select count(*) from bets where status = 'pending') = 2, 'business untouched while voting';
  perform set_config('request.jwt.claim.sub', pg_temp.u('f')::text, true);
end $$;
call pg_temp.expect_error($q$ select cast_vote(pg_temp.vote_of('Reset Crew', 'reset'), true) $q$, '%vote_not_found%');   -- outsiders can't vote (or see it)
call pg_temp.as_user('c');
call pg_temp.expect_error($q$ select cast_vote(pg_temp.vote_of('Reset Crew', 'reset'), null) $q$, '%invalid_ballot%');
call pg_temp.expect_error($q$ select cast_vote(gen_random_uuid(), true) $q$, '%vote_not_found%');

-- erin changes her mind → yes 3 of 5 is more than half → the reset happens at once
call pg_temp.as_user('e');
do $$ begin assert cast_vote(pg_temp.vote_of('Reset Crew', 'reset'), true) = 'passed', 'the third yes passes it'; end $$;

do $$ declare g uuid := pg_temp.gid('Reset Crew'); v record; begin
  select * into v from votes where id = pg_temp.vote_of('Reset Crew', 'reset');
  assert v.status = 'passed' and v.yes_count = 3 and v.no_count = 1 and v.electorate = 5 and v.quorum = 2 and v.decided_at is not null, 'result recorded';
  -- business cleared
  assert not exists (select 1 from offers where group_id = g and status = 'open'), 'no open offers';
  assert not exists (select 1 from bets where group_id = g and status = 'pending'), 'no unsettled bets';
  assert (select count(*) from offers where group_id = g and cancel_reason = 'reset') = 1, 'the open offer was cancelled by the reset';
  assert (select count(*) from bets where group_id = g and status = 'void') = 2, 'both unsettled bets voided';
  assert not exists (select 1 from profiles p join rec_before r on r.id = p.id where p.lifetime_wins <> r.w or p.lifetime_losses <> r.l), 'voided bets do not touch anyone''s win-loss record';
  -- everyone is back to the starting balance with a clean slate
  assert (select count(*) from group_members where group_id = g and status = 'active' and available = 10000 and escrow = 0 and granted = 10000 and buyback_count = 0 and buyback_coins = 0) = 5, 'all five back to 100 coins, buybacks cleared';
  assert (select count(*) from group_leaderboard where group_id = g and net_profit = 0) = 5, 'leaderboard starts over';
  -- seasons
  assert (select count(*) from seasons where group_id = g) = 2, 'a second season exists';
  assert (select ended_at from seasons where group_id = g and number = 1) is not null, 'season 1 is over';
  assert (select number from seasons where id = (select current_season_id from groups where id = g)) = 2, 'the group is in season 2';
  -- history (snapshot taken BEFORE the reset)
  assert (select count(*) from season_history where group_id = g and number = 1) = 5, 'five standings saved';
  assert (select sum(final_balance) from season_history where group_id = g) = 60000, '5 × 100 coins + the 100-coin buyback';
  assert (select sum(net_profit) from season_history where group_id = g) = 0, 'saved profits still sum to zero';
  assert not exists (select 1 from season_history h join before_reset b on b.user_id = h.user_id
                      where h.net_profit <> b.net_profit or h.final_balance <> b.balance or h.buyback_count <> b.buyback_count), 'the snapshot equals the leaderboard as it was';
  assert (select buyback_count from season_history where group_id = g and username = 'carol') = 1, 'carol''s buyback is in the history';
  -- everyone's net profit became part of their lifetime score
  assert not exists (select 1 from profiles p join rec_before r on r.id = p.id join before_reset b on b.user_id = p.id
                      where p.lifetime_closed_profit <> r.cp + b.net_profit), 'lifetime score = old score + that season''s net profit';
  assert pg_temp.healthy(), 'every integrity check passes after the reset';
end $$;
call pg_temp.as_user('c');
call pg_temp.expect_error($q$ select cast_vote(pg_temp.vote_of('Reset Crew', 'reset'), true) $q$, '%vote_closed%');
-- betting works normally in the new season, and a new reset vote may be called
call pg_temp.as_user('a');
select post_offer(pg_temp.gid('Reset Crew'), pg_temp.mkt('sp', 1), 0, 50, 10);
do $$ begin
  assert (select season_id from offers where id = (select id from offers where maker_id = pg_temp.u('a') and status = 'open')) = (select current_season_id from groups where id = pg_temp.gid('Reset Crew')), 'new offers belong to season 2';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ═════════ 2. A one-person group decides at once ═════════
call pg_temp.as_user('a');
insert into ids (name, id) values ('Solo', create_group('Solo', 10000, 'unlimited', null, 10000));
select call_vote(pg_temp.gid('Solo'), 'reset');
do $$ begin
  assert (select status from votes where group_id = pg_temp.gid('Solo')) = 'passed' and (select count(*) from seasons where group_id = pg_temp.gid('Solo')) = 2, 'a group of one resets immediately';
end $$;

-- ═════════ 3. Early FAIL: 4 members, two say no ═════════
call pg_temp.make_group('Four', array['b','c','d']);
call pg_temp.as_user('b'); select call_vote(pg_temp.gid('Four'), 'reset');
call pg_temp.as_user('c'); do $$ begin assert cast_vote(pg_temp.vote_of('Four', 'reset'), false) = 'open', 'one no of four'; end $$;
call pg_temp.as_user('d'); do $$ begin assert cast_vote(pg_temp.vote_of('Four', 'reset'), false) = 'failed', 'two no of four: yes can no longer win'; end $$;
do $$ begin
  assert (select count(*) from seasons where group_id = pg_temp.gid('Four')) = 1 and (select count(*) from group_members where group_id = pg_temp.gid('Four') and available = 10000) = 4, 'a failed vote changes nothing';
  assert (select decision_note from votes where group_id = pg_temp.gid('Four')) = 'yes can no longer win', 'reason recorded';
end $$;

-- ═════════ 4. When the 24 hours run out ═════════
call pg_temp.make_group('Expiry A', array['b','c','d','e']);     -- yes 2, no 1 → passes at expiry
call pg_temp.make_group('Expiry B', array['b','c','d','e']);     -- only the caller votes → quorum not reached
call pg_temp.make_group('Expiry C', array['b','c','d','e']);     -- 1 yes, 1 no → tie → fails
call pg_temp.as_user('b'); select call_vote(pg_temp.gid('Expiry A'), 'reset'); select call_vote(pg_temp.gid('Expiry B'), 'reset'); select call_vote(pg_temp.gid('Expiry C'), 'reset');
call pg_temp.as_user('c'); select cast_vote(pg_temp.vote_of('Expiry A', 'reset'), true);
call pg_temp.as_user('d'); select cast_vote(pg_temp.vote_of('Expiry A', 'reset'), false);
select cast_vote(pg_temp.vote_of('Expiry C', 'reset'), false);
do $$ begin
  assert close_votes() = 0, 'nothing is due yet';
  perform pg_temp.set_clock('2026-10-09 11:59:59+00');
  assert close_votes() = 0, 'one second before the 24 hours are up';
  perform pg_temp.set_clock('2026-10-09 12:00:00+00');
  -- the window is over but the job has not run yet: voting is refused
  begin perform set_config('request.jwt.claim.sub', pg_temp.u('e')::text, true); perform cast_vote(pg_temp.vote_of('Expiry B', 'reset'), true); assert false, 'late vote accepted';
  exception when others then assert sqlerrm = 'vote_closed', sqlerrm; end;
  assert close_votes() = 3, 'three votes closed';
  assert close_votes() = 0, 'running it again does nothing';
  assert (select status from votes where group_id = pg_temp.gid('Expiry A')) = 'passed' and (select decision_note from votes where group_id = pg_temp.gid('Expiry A')) = 'more yes than no when time ran out', 'A passes at expiry';
  assert (select count(*) from seasons where group_id = pg_temp.gid('Expiry A')) = 2, 'and the reset happened';
  assert (select status from votes where group_id = pg_temp.gid('Expiry B')) = 'failed' and (select decision_note from votes where group_id = pg_temp.gid('Expiry B')) = 'quorum not reached', 'B fails: quorum';
  assert (select status from votes where group_id = pg_temp.gid('Expiry C')) = 'failed' and (select decision_note from votes where group_id = pg_temp.gid('Expiry C')) = 'not more yes than no', 'C fails: a tie';
  assert (select count(*) from seasons where group_id in (pg_temp.gid('Expiry B'), pg_temp.gid('Expiry C'))) = 2, 'no reset for B or C';
  perform pg_temp.set_clock('2026-10-08 12:00+00');
end $$;

-- ═════════ 5. Buyback votes (group policy: vote) ═════════
call pg_temp.make_group('Vote Policy', array['b','c','d'], 'vote');
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Vote Policy'), 'buyback') $q$, '%not_busted%');               -- bobby still has 100 coins
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('Vote Policy')) $q$, '%not_busted%');
reset role;
call pg_temp.lose_everything('Vote Policy', 'b', 'a');
call pg_temp.lose_everything('Vote Policy', 'c', 'a');
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select claim_buyback(pg_temp.gid('Vote Policy')) $q$, '%buyback_requires_vote%');   -- broke, but this group decides by vote
select call_vote(pg_temp.gid('Vote Policy'), 'buyback');
do $$ begin assert (select subject_username from vote_listing where kind = 'buyback' and group_id = pg_temp.gid('Vote Policy')) = 'bobby', 'the vote is about bobby'; end $$;
call pg_temp.expect_error($q$ select call_vote(pg_temp.gid('Vote Policy'), 'buyback') $q$, '%vote_already_open%');
call pg_temp.as_user('c');
select call_vote(pg_temp.gid('Vote Policy'), 'buyback');                                  -- carol asks too (a separate vote)
call pg_temp.as_user('d');
do $$ declare vb uuid := (select id from votes where group_id = pg_temp.gid('Vote Policy') and subject_id = pg_temp.u('b'));
begin
  assert cast_vote(vb, true) = 'open', 'yes 2 of 4 is not more than half';
  perform set_config('request.jwt.claim.sub', pg_temp.u('a')::text, true);
  assert cast_vote(vb, true) = 'passed', 'yes 3 of 4 passes';
  assert (select available from group_members where group_id = pg_temp.gid('Vote Policy') and user_id = pg_temp.u('b')) = 10000, 'bobby got the buyback amount';
  assert (select buyback_count from group_members where group_id = pg_temp.gid('Vote Policy') and user_id = pg_temp.u('b')) = 1, 'counted as a buyback';
  assert (select via from buybacks where group_id = pg_temp.gid('Vote Policy') and user_id = pg_temp.u('b')) = 'vote', 'recorded as a vote buyback';
  assert pg_temp.healthy(), 'healthy';
end $$;
-- carol's request: two no votes → fails, nothing paid
do $$ declare vc uuid := (select id from votes where group_id = pg_temp.gid('Vote Policy') and subject_id = pg_temp.u('c'));
begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('d')::text, true); perform cast_vote(vc, false);
  perform set_config('request.jwt.claim.sub', pg_temp.u('a')::text, true);
  assert cast_vote(vc, false) = 'failed', 'two no of four fails it';
  assert (select available + escrow from group_members where group_id = pg_temp.gid('Vote Policy') and user_id = pg_temp.u('c')) = 0, 'carol is still broke';
end $$;
-- she may ask again later; if she is no longer broke when it passes, nothing is paid
call pg_temp.as_user('c'); select call_vote(pg_temp.gid('Vote Policy'), 'buyback');
reset role;
call pg_temp.lose_everything('Vote Policy', 'a', 'c');                                    -- alice hands carol some coins in the meantime
call pg_temp.as_user('b'); select cast_vote((select id from votes where subject_id = pg_temp.u('c') and status = 'open'), true);
call pg_temp.as_user('d'); 
do $$ begin
  assert cast_vote((select id from votes where subject_id = pg_temp.u('c') and status = 'open'), true) = 'cancelled', 'passes, but carol is no longer broke → cancelled';
  assert (select count(*) from buybacks where user_id = pg_temp.u('c') and group_id = pg_temp.gid('Vote Policy')) = 0, 'no buyback paid';
  assert pg_temp.healthy(), 'healthy';
end $$;
-- a reset cancels buyback votes that are still open
reset role;
call pg_temp.lose_everything('Vote Policy', 'c', 'b');
call pg_temp.as_user('c'); select call_vote(pg_temp.gid('Vote Policy'), 'buyback');
call pg_temp.as_user('d'); select call_vote(pg_temp.gid('Vote Policy'), 'reset');
call pg_temp.as_user('b'); select cast_vote(pg_temp.vote_of('Vote Policy', 'reset'), true);
call pg_temp.as_user('a'); select cast_vote(pg_temp.vote_of('Vote Policy', 'reset'), true);
do $$ begin
  assert (select status from votes where group_id = pg_temp.gid('Vote Policy') and kind = 'reset' order by created_at desc limit 1) = 'passed', 'reset passed';
  assert not exists (select 1 from votes where group_id = pg_temp.gid('Vote Policy') and status = 'open'), 'open buyback votes were cancelled by the reset';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ═════════ 5b. Random run: bets, buybacks, resolutions, reset votes and clock jumps, all mixed ═════════
call pg_temp.make_group('Chaos', array['b','c','d','e']);
update group_members set available = available where false;
do $$
declare
  g uuid := pg_temp.gid('Chaos');
  users text[] := array['a','b','c','d','e'];
  mks text[] := array(select id from markets where league = 'nfl' order by id);
  off record; vt record; err text; i integer; r double precision; u text; k integer := 0;
  n_post integer := 0; n_take integer := 0; n_res integer := 0; n_vote integer := 0; n_bb integer := 0; n_reset integer := 0;
  t timestamptz := '2026-10-08 12:00+00';
  allowed text[] := array['insufficient_balance', 'market_not_open', 'offer_not_open', 'not_enough_shares', 'cannot_take_own_offer',
                          'not_offer_maker', 'market_started', 'not_busted', 'buyback_limit_reached', 'vote_already_open', 'vote_closed',
                          'vote_not_found', 'buyback_vote_not_allowed', 'owner_must_transfer'];
begin
  perform setseed(0.57721);
  update markets set game_start = '2027-01-01 00:00+00' where league = 'nfl';   -- these games are far away, so the clock jumps below don't start them
  -- everyone gets a bigger bankroll so the run goes deep (minted as buybacks, which the books track)
  foreach u in array users loop perform ledger_post(gen_random_uuid(), g, pg_temp.u(u), 'available', 200000, 'buyback'); end loop;
  for i in 1..3500 loop
    u := users[1 + floor(random() * 5)::int];
    perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true);
    r := random();
    begin
      if r < 0.25 then
        perform post_offer(g, mks[1 + floor(random() * array_length(mks, 1))::int], floor(random() * 2)::int, 1 + floor(random() * 99)::int, 1 + floor(random() * 60)::int);
        n_post := n_post + 1;
      elsif r < 0.60 then
        select id, shares_open into off from offers where group_id = g and status = 'open' order by random() limit 1;
        if off.id is not null then perform take_offer(off.id, 1 + floor(random() * off.shares_open)::int); n_take := n_take + 1; end if;
        off := null;
      elsif r < 0.68 then
        select id into off from offers where group_id = g and status = 'open' order by random() limit 1;
        if off.id is not null then perform cancel_offer(off.id); end if;
        off := null;
      elsif r < 0.72 then                                   -- (rarely) Polymarket finalises a market (winner or void), the job settles it
        if random() > 0.07 then raise exception 'insufficient_balance'; end if;       -- counted as a harmless no-op
        k := 1 + floor(random() * array_length(mks, 1))::int;
        update markets set closed = true, uma_status = 'resolved',
               outcome_prices = case floor(random() * 3)::int when 0 then '{1,0}' when 1 then '{0,1}' else '{0.5,0.5}' end::numeric[]
         where id = mks[k] and resolution = 'pending';
        update markets set resolution = market_resolution(closed, uma_status, outcome_prices) where id = mks[k] and resolution = 'pending';
        perform settle_resolved_markets(); n_res := n_res + 1;
      elsif r < 0.75 then
        perform claim_buyback(g); n_bb := n_bb + 1;
      elsif r < 0.77 then
        perform call_vote(g, 'reset'); n_vote := n_vote + 1;
      elsif r < 0.85 then
        select id into vt from votes where group_id = g and status = 'open' order by random() limit 1;
        if vt.id is not null then perform cast_vote(vt.id, random() < 0.5); end if;
        vt := null;
      elsif r < 0.88 then
        if random() > 0.25 then raise exception 'insufficient_balance'; end if;
        t := t + make_interval(hours => 1 + floor(random() * 20)::int);          -- the clock moves; votes may expire
        update clock_override set at = t;
        perform close_votes();
      end if;
    exception when others then
      err := sqlerrm;
      if err <> all (allowed) then raise exception 'UNEXPECTED ERROR at step %: %', i, err; end if;
    end;
    if i % 350 = 0 then
      if not pg_temp.healthy() then
        raise exception 'books broke at step %: %', i, (select string_agg(check_name || ' ' || coalesce(detail, ''), E'\n') from
            (select * from check_ledger_integrity() union all select * from check_betting_integrity() union all select * from check_season_integrity()) x);
      end if;
    end if;
  end loop;
  perform settle_resolved_markets();
  perform pg_temp.set_clock('2026-10-08 12:00+00');
  select count(*) into n_reset from votes where group_id = g and kind = 'reset' and status = 'passed';
  assert pg_temp.healthy(), 'books balance after the random run';
  assert (select count(*) from seasons where group_id = g) = n_reset + 1, 'one season per passed reset';
  assert n_post > 300 and n_take > 150 and n_vote > 20 and n_res >= 3, format('run too thin: post %s take %s vote %s', n_post, n_take, n_vote);
  assert n_reset >= 1, 'at least one reset happened during the run';
  raise notice 'chaos run: % posts, % takes, % resolutions, % buybacks, % votes called, % resets passed', n_post, n_take, n_res, n_bb, n_vote, n_reset;
end $$;
select pg_temp.set_clock('2026-10-08 12:00+00');

-- ═════════ 6. Permissions and visibility ═════════
set local role authenticated;
call pg_temp.as_user('a');
do $$ begin
  assert (select count(*) from vote_listing where group_id = pg_temp.gid('Reset Crew')) = 1, 'members see their group''s votes';
  assert (select count(*) from vote_ballots where vote_id = pg_temp.vote_of('Reset Crew', 'reset')) = 4, 'and who voted (4 ballots)';
  assert (select count(*) from season_history where group_id = pg_temp.gid('Reset Crew')) = 5, 'and past seasons';
end $$;
call pg_temp.as_user('f');
do $$ begin assert (select count(*) from vote_listing) = 0 and (select count(*) from vote_ballots) = 0 and (select count(*) from season_history) = 0, 'outsiders see nothing'; end $$;
call pg_temp.expect_error($q$ insert into vote_ballots (vote_id, user_id, yes) values (gen_random_uuid(), gen_random_uuid(), true) $q$, '%permission denied%');
call pg_temp.expect_error($q$ update votes set status = 'passed' $q$, '%permission denied%');
call pg_temp.expect_error($q$ select evaluate_vote(gen_random_uuid(), true) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select close_votes() $q$, '%permission denied%');
call pg_temp.expect_error($q$ select apply_group_reset(null) $q$, '%permission denied%');
reset role;
set local role anon;
call pg_temp.expect_error($q$ select call_vote(gen_random_uuid(), 'reset') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select cast_vote(gen_random_uuid(), true) $q$, '%permission denied%');
reset role;

-- ═════════ 7. The books catch tampering with seasons ═════════
do $$ begin
  assert pg_temp.healthy(), 'healthy before tampering';
  update seasons set ended_at = null where group_id = pg_temp.gid('Reset Crew') and number = 1;
  assert exists (select 1 from check_season_integrity() where check_name = 'season_not_current'), 'two running seasons are detected';
  update seasons set ended_at = now() where group_id = pg_temp.gid('Reset Crew') and number = 1;
  begin
    update votes set decided_at = null where group_id = pg_temp.gid('Four');
    assert false, 'a finished vote without a decision time was accepted';
  exception when check_violation then null; end;           -- the table itself refuses it
end $$;
rollback;
