-- Milestone 6 tests: paying out bets when Polymarket finalises a game.
-- Markets are driven to "final" through the REAL finality rule (ingest of closed/resolved Polymarket data).
\set ON_ERROR_STOP on
\set open_nba_game `cat fixtures/open_nba_game.json`
\set open_nfl      `cat fixtures/open_nfl_spreads.json`
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
create procedure pg_temp.as_user(p_user uuid) language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_user::text, true); end $$;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000e1');
insert into profiles (id, username) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'), ('00000000-0000-0000-0000-0000000000b1', 'bobby'),
  ('00000000-0000-0000-0000-0000000000c1', 'carol'), ('00000000-0000-0000-0000-0000000000d1', 'dave'),
  ('00000000-0000-0000-0000-0000000000e1', 'erin');
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb), ('nfl', :'open_nfl'::jsonb);
create temp table ids (name text primary key, id uuid, txt text);
grant all on ids to public;
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
select ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

-- G1: alice, bobby, carol (100 coins each). G2: separate group for the random run.
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('g1', create_group('Settle Crew'));
do $$ declare code text; begin
  select invite_code into code from groups where id = (select id from ids where name = 'g1');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true); perform join_group(code);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true); perform join_group(code);
end $$;

create function pg_temp.g1() returns uuid language sql as $$ select id from ids where name = 'g1' $$;
create function pg_temp.mk(p_name text) returns text language sql as $$ select txt from ids where name = p_name $$;
create function pg_temp.bal(p_user text, p_what text) returns bigint language sql as $$
  select case p_what when 'avail' then available when 'esc' then escrow else available + escrow end
    from group_members where group_id = pg_temp.g1() and user_id = ('00000000-0000-0000-0000-0000000000' || p_user || '1')::uuid $$;
create function pg_temp.record(p_user text) returns text language sql as $$
  select lifetime_wins || '-' || lifetime_losses from profiles where id = ('00000000-0000-0000-0000-0000000000' || p_user || '1')::uuid $$;
create function pg_temp.healthy() returns boolean language sql as $$
  select not exists (select 1 from check_ledger_integrity()) and not exists (select 1 from check_betting_integrity()) $$;
-- Move a market through Polymarket's own fields, then let the real finality rule decide.
create function pg_temp.polymarket_says(p_market text, p_prices text, p_status text, p_closed boolean default true) returns void language plpgsql as $$
declare e jsonb;
begin
  select x into e from fx, jsonb_array_elements(fx.payload) x where fx.name = 'nba' and x ->> 'id' = p_market;
  perform ingest_markets('nba', jsonb_build_array(e || jsonb_build_object('closed', p_closed, 'umaResolutionStatus', p_status, 'outcomePrices', p_prices)),
                         '2026-10-08 12:00+00');
end $$;

insert into ids (name, txt) select 'm1', id from markets where market_type = 'moneyline';
insert into ids (name, txt) select 'm2', id from markets where question = 'Spread: Cavaliers (-1.5)';
insert into ids (name, txt) select 'm3', id from markets where question like '%O/U 220.5';
insert into ids (name, txt) select 'm4', id from markets where market_type = 'spreads' and league = 'nba' and id <> (select txt from ids where name = 'm2') order by id limit 1;
insert into ids (name, txt) select 'm5', id from markets where market_type = 'totals' and league = 'nba' and id <> (select txt from ids where name = 'm3') order by id limit 1;
insert into ids (name, txt) select 'm6', id from markets where market_type = 'spreads' and league = 'nba' and id not in (select txt from ids where txt is not null) order by id limit 1;
insert into ids (name, txt) select 'm7', id from markets where market_type = 'spreads' and league = 'nba' and id not in (select txt from ids where txt is not null) order by id limit 1;
do $$ begin assert (select count(distinct txt) from ids where txt is not null) = 7, 'seven distinct markets'; assert pg_temp.healthy(), 'healthy at start'; end $$;

-- ───────── S1: the maker's side wins ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o1', post_offer(pg_temp.g1(), pg_temp.mk('m1'), 0, 60, 100));
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select take_offer((select id from ids where name = 'o1'), 50);
call pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select take_offer((select id from ids where name = 'o1'), 50);
do $$ begin
  assert settle_market(pg_temp.mk('m1')) = 0, 'an unresolved market pays nothing';
  assert settle_resolved_markets() = 0, 'nothing final yet';
end $$;
select pg_temp.polymarket_says(pg_temp.mk('m1'), '["1", "0"]', 'resolved');          -- first outcome wins; maker backed it
do $$ begin
  assert (select resolution from markets where id = pg_temp.mk('m1')) = 'outcome_0', 'the real rule marked it final';
  assert settle_market(pg_temp.mk('m1')) = 2, 'both bets settled';
  assert (select count(*) from bets where status = 'won_maker' and market_id = pg_temp.mk('m1')) = 2, 'maker won both';
  assert (select count(*) from bets where settled_at is not null and market_id = pg_temp.mk('m1')) = 2, 'settled_at recorded';
  assert pg_temp.bal('a', 'avail') = 14000 and pg_temp.bal('a', 'esc') = 0, 'maker: 40 + (50 + 50) coins';
  assert pg_temp.bal('b', 'avail') = 8000 and pg_temp.bal('b', 'esc') = 0, 'taker B lost his 20 coins';
  assert pg_temp.bal('c', 'avail') = 8000 and pg_temp.bal('c', 'esc') = 0, 'taker C lost her 20 coins';
  assert pg_temp.record('a') = '2-0' and pg_temp.record('b') = '0-1' and pg_temp.record('c') = '0-1', 'records updated';
  assert pg_temp.healthy(), 'books balance after settlement';
  -- running it again changes nothing, ever
  assert settle_market(pg_temp.mk('m1')) = 0, 'second run pays nothing';
  assert settle_resolved_markets() = 0, 'scheduled run finds nothing left';
  assert pg_temp.bal('a', 'total') = 14000 and pg_temp.record('a') = '2-0', 'no double payment';
end $$;

-- ───────── S2: the taker wins ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
insert into ids (name, id) values ('o2', post_offer(pg_temp.g1(), pg_temp.mk('m2'), 0, 30, 40));    -- backs outcome 0 at 30¢
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select take_offer((select id from ids where name = 'o2'), 40);                                       -- A fades him: 40 × 70¢ = 28 coins
select pg_temp.polymarket_says(pg_temp.mk('m2'), '["0", "1"]', 'resolved');                          -- second outcome wins
do $$ begin
  assert settle_resolved_markets() = 1, 'one bet settled';
  assert (select status from bets where market_id = pg_temp.mk('m2')) = 'won_taker', 'taker won';
  assert pg_temp.bal('a', 'avail') = 15200 and pg_temp.bal('a', 'esc') = 0, 'A: 112 + whole pot of 40 coins';
  assert pg_temp.bal('b', 'avail') = 6800 and pg_temp.bal('b', 'esc') = 0, 'B lost his 12 coins';
  assert pg_temp.record('a') = '3-0' and pg_temp.record('b') = '0-2', 'records';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ───────── S3: a 50/50 is a void — everyone gets their own stake back ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into ids (name, id) values ('o3', post_offer(pg_temp.g1(), pg_temp.mk('m3'), 1, 25, 20));
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select take_offer((select id from ids where name = 'o3'), 20);
do $$ begin assert pg_temp.bal('c', 'esc') = 500 and pg_temp.bal('b', 'esc') = 1500, 'stakes held in escrow'; end $$;
select pg_temp.polymarket_says(pg_temp.mk('m3'), '["0.5", "0.5"]', 'resolved');
do $$ begin
  assert settle_resolved_markets() = 1, 'void bet settled';
  assert (select status from bets where market_id = pg_temp.mk('m3')) = 'void', 'bet is void';
  assert pg_temp.bal('c', 'avail') = 8000 and pg_temp.bal('c', 'esc') = 0, 'C refunded exactly her 5 coins';
  assert pg_temp.bal('b', 'avail') = 6800 and pg_temp.bal('b', 'esc') = 0, 'B refunded exactly his 15 coins';
  assert pg_temp.record('b') = '0-2' and pg_temp.record('c') = '0-1', 'a void does not touch win-loss records';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ───────── S4: anything short of "closed + resolved + terminal prices" pays NOTHING ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o4', post_offer(pg_temp.g1(), pg_temp.mk('m4'), 0, 50, 10));
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select take_offer((select id from ids where name = 'o4'), 10);
do $$
declare cases text[][] := array[
  ['["1", "0"]', 'proposed',  'true'],  ['["1", "0"]', 'disputed', 'true'],  ['["1", "0"]', null, 'true'],
  ['["1", "0"]', 'resolved',  'false'], ['["0.7", "0.3"]', 'resolved', 'true'], ['["1", "0"]', 'Resolved', 'true']];
  c text[]; i integer;
begin
  for i in 1..array_length(cases, 1) loop
    c := cases[i:i][1:3];
    perform pg_temp.polymarket_says(pg_temp.mk('m4'), c[1], c[2], c[3]::boolean);
    assert settle_market(pg_temp.mk('m4')) = 0 and settle_resolved_markets() = 0, 'paid early on case ' || i;
    assert (select status from bets where market_id = pg_temp.mk('m4')) = 'pending', 'still pending on case ' || i;
    assert pg_temp.bal('a', 'esc') = 500 and pg_temp.bal('b', 'esc') = 500, 'escrow untouched on case ' || i;
  end loop;
  assert pg_temp.healthy(), 'healthy while waiting';
end $$;
select pg_temp.polymarket_says(pg_temp.mk('m4'), '["0", "1"]', 'resolved');                          -- finally final
do $$ begin
  assert settle_resolved_markets() = 1, 'paid once it is really final';
  assert (select status from bets where market_id = pg_temp.mk('m4')) = 'won_taker', 'taker B won';
  assert pg_temp.bal('a', 'avail') = 14700 and pg_temp.bal('b', 'avail') = 7300, 'balances';
  assert pg_temp.record('a') = '3-1' and pg_temp.record('b') = '1-2' and pg_temp.record('c') = '0-1', 'records after four settlements';
  assert pg_temp.bal('a', 'total') + pg_temp.bal('b', 'total') + pg_temp.bal('c', 'total') = 30000, 'coins conserved';
end $$;

-- ───────── S5: an offer still open when its market ends is returned during settlement ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o5', post_offer(pg_temp.g1(), pg_temp.mk('m5'), 1, 40, 30));
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select take_offer((select id from ids where name = 'o5'), 10);
-- (simulate the cancel job lagging: the market resolves while 20 shares are still open)
update markets set closed = true, uma_status = 'resolved', outcome_prices = '{0,1}', resolution = 'outcome_1' where id = pg_temp.mk('m5');
do $$ begin
  assert settle_market(pg_temp.mk('m5')) = 1, 'the one taken bet settled';
  assert (select status from offers where id = (select id from ids where name = 'o5')) = 'cancelled', 'leftover shares cancelled';
  assert (select shares_cancelled from offers where id = (select id from ids where name = 'o5')) = 20, '20 shares returned';
  assert pg_temp.bal('a', 'avail') = 15300 and pg_temp.bal('a', 'esc') = 0, 'maker won 6 coins and got 8 coins of unfilled shares back';
  assert pg_temp.bal('b', 'avail') = 6700 and pg_temp.bal('b', 'esc') = 0, 'taker lost 6 coins';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ───────── S6: the scheduled job settles every finished market in one go ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select post_offer(pg_temp.g1(), pg_temp.mk('m6'), 0, 50, 10);
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select take_offer((select id from offers where market_id = pg_temp.mk('m6')), 10);
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select post_offer(pg_temp.g1(), pg_temp.mk('m7'), 1, 20, 5);
call pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select take_offer((select id from offers where market_id = pg_temp.mk('m7')), 5);
select pg_temp.polymarket_says(pg_temp.mk('m6'), '["1", "0"]', 'resolved');
select pg_temp.polymarket_says(pg_temp.mk('m7'), '["0", "1"]', 'resolved');
do $$ begin
  assert settle_resolved_markets() = 2, 'both markets settled in one run';
  assert pg_temp.bal('a', 'total') = 14800 and pg_temp.bal('b', 'total') = 7100 and pg_temp.bal('c', 'total') = 8100, 'final balances';
  assert pg_temp.bal('a', 'esc') + pg_temp.bal('b', 'esc') + pg_temp.bal('c', 'esc') = 0, 'nothing left in escrow';
  assert pg_temp.record('a') = '4-2' and pg_temp.record('b') = '2-3' and pg_temp.record('c') = '1-2', 'final records';
  assert not exists (select 1 from bets where status = 'pending'), 'no bet left pending';
  assert pg_temp.healthy(), 'healthy';
end $$;

-- ───────── Who can see / do what ─────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
do $$ begin
  assert (select count(*) from bet_listing where status in ('won_maker', 'won_taker', 'void')) = 8, 'members see all 8 settled results';
  assert (select count(*) from bet_listing where status = 'void') = 1, 'including the void';
end $$;
call pg_temp.expect_error($q$ select settle_market('x') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select settle_resolved_markets() $q$, '%permission denied%');
call pg_temp.expect_error($q$ update bets set status = 'won_taker' $q$, '%permission denied%');
call pg_temp.expect_error($q$ update profiles set lifetime_wins = 999 $q$, '%permission denied%');
reset role;

-- ───────── Random run: thousands of operations, then every market resolves at random ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('g2', create_group('Random Crew'));
do $$ declare code text; begin
  select invite_code into code from groups where id = (select id from ids where name = 'g2');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true); perform join_group(code);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true); perform join_group(code);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true); perform join_group(code);
end $$;
do $$
declare
  g uuid := (select id from ids where name = 'g2');
  users uuid[] := array['00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
                        '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000e1']::uuid[];
  mks text[] := array(select id from markets where league = 'nfl' order by id);
  off record; err text; i integer; r double precision; u uuid; k integer;
  n_take integer := 0; before_a bigint[]; after_a bigint[]; pending_before integer;
  total_before bigint;
  allowed text[] := array['insufficient_balance', 'market_not_open', 'offer_not_open', 'not_enough_shares',
                          'cannot_take_own_offer', 'not_offer_maker', 'market_started'];
begin
  perform setseed(0.2718);
  foreach u in array users loop perform ledger_post(gen_random_uuid(), g, u, 'available', 500000, 'buyback'); end loop;
  for i in 1..2500 loop
    u := users[1 + floor(random() * 4)::int];
    perform set_config('request.jwt.claim.sub', u::text, true);
    r := random();
    begin
      if r < 0.30 then
        perform post_offer(g, mks[1 + floor(random() * array_length(mks, 1))::int], floor(random() * 2)::int,
                           1 + floor(random() * 99)::int, 1 + floor(random() * 40)::int);
      elsif r < 0.80 then
        select id, shares_open into off from offers where group_id = g and status = 'open' order by random() limit 1;
        if off.id is not null then perform take_offer(off.id, 1 + floor(random() * off.shares_open)::int); n_take := n_take + 1; end if;
        off := null;
      else
        select id into off from offers where group_id = g and status = 'open' order by random() limit 1;
        if off.id is not null then perform cancel_offer(off.id); end if;
        off := null;
      end if;
    exception when others then
      err := sqlerrm;
      if err <> all (allowed) then raise exception 'UNEXPECTED ERROR at step %: %', i, err; end if;
    end;
  end loop;
  assert pg_temp.healthy(), 'healthy before resolution';
  assert (select count(*) from bets where group_id = g) > 150, 'lots of bets to settle';

  -- every market now resolves differently: winner 0, winner 1, void, or "not final yet" (proposed / disputed / unknown word)
  for k in 1..array_length(mks, 1) loop
    case k % 6
      when 0 then update markets set closed = true, uma_status = 'resolved', outcome_prices = '{1,0}', resolution = 'outcome_0' where id = mks[k];
      when 1 then update markets set closed = true, uma_status = 'resolved', outcome_prices = '{0,1}', resolution = 'outcome_1' where id = mks[k];
      when 2 then update markets set closed = true, uma_status = 'resolved', outcome_prices = '{0.5,0.5}', resolution = 'void' where id = mks[k];
      when 3 then update markets set closed = true, uma_status = 'proposed' where id = mks[k];
      when 4 then update markets set closed = true, uma_status = 'disputed' where id = mks[k];
      else null;                                                                  -- still open, still pending
    end case;
  end loop;
  select count(*) into pending_before from bets where group_id = g and status = 'pending';
  select sum(available + escrow) into total_before from group_members where group_id = g;
  assert total_before = 2040000, 'four members: 4 × (100 coins granted + 5,000 coins minted)';
  assert settle_resolved_markets() > 50, 'a lot of bets settled';

  assert pg_temp.healthy(), 'books balance after random settlement';
  assert (select sum(available + escrow) from group_members where group_id = g) = 2040000, 'the group still holds exactly the coins it was given';
  assert not exists (select 1 from bets b join markets m on m.id = b.market_id
                      where b.group_id = g and b.status = 'pending' and m.resolution <> 'pending'), 'every bet on a final market is settled';
  assert not exists (select 1 from bets b join markets m on m.id = b.market_id
                      where b.group_id = g and b.status <> 'pending' and m.resolution = 'pending'), 'no bet on a non-final market was paid';
  assert exists (select 1 from bets where group_id = g and status = 'pending'), 'bets on not-yet-final markets are still pending';
  assert exists (select 1 from bets where group_id = g and status = 'void') and exists (select 1 from bets where group_id = g and status = 'won_maker')
     and exists (select 1 from bets where group_id = g and status = 'won_taker'), 'all three result types occurred';
  assert not exists (select 1 from offers o join markets m on m.id = o.market_id where o.group_id = g and o.status = 'open' and m.resolution <> 'pending'),
         'no open offers left on finished markets';
  -- a second pass changes nothing at all
  select array_agg(available order by user_id) into before_a from group_members where group_id = g;
  assert settle_resolved_markets() = 0, 'second pass pays nothing';
  select array_agg(available order by user_id) into after_a from group_members where group_id = g;
  assert before_a = after_a, 'balances identical after second pass';
  assert (select sum(lifetime_wins) from profiles) = (select sum(lifetime_losses) from profiles), 'every win is somebody else''s loss';
  assert (select sum(lifetime_wins) from profiles) = (select count(*) from bets where status in ('won_maker', 'won_taker')), 'wins = settled non-void bets';
  raise notice 'random settlement: % takes, % bets settled, % still pending', n_take,
    (select count(*) from bets where group_id = g and status <> 'pending'), (select count(*) from bets where group_id = g and status = 'pending');
end $$;


-- ───────── The database catches a bad settlement if code ever got one wrong ─────────
do $$ begin
  update bets set status = 'won_maker' where market_id = pg_temp.mk('m2');           -- but the market said outcome_1 won
  assert exists (select 1 from check_betting_integrity() where check_name = 'bet_result_mismatch'), 'wrong winner is detected';
  update bets set status = 'won_taker' where market_id = pg_temp.mk('m2');
  update profiles set lifetime_wins = lifetime_wins + 1 where username = 'alice';
  assert exists (select 1 from check_betting_integrity() where check_name = 'record_mismatch'), 'wrong record is detected';
  update profiles set lifetime_wins = lifetime_wins - 1 where username = 'alice';
  perform ledger_post(gen_random_uuid(), pg_temp.g1(), '00000000-0000-0000-0000-0000000000a1', 'available', 1, 'bet_payout', 'bet', (select id from bets where market_id = pg_temp.mk('m1') limit 1));
  assert exists (select 1 from check_betting_integrity() where check_name = 'bet_payout_mismatch'), 'an extra coin paid out is detected';
end $$;
rollback;
