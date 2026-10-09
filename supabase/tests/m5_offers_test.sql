-- Milestone 5 tests: post / take / cancel / auto-cancel, escrow math, security, and a random-operations fuzz run.
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
create procedure pg_temp.as_user(p_user uuid) language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_user::text, true); end $$;

-- ── Fixtures: 5 people, group G1 (A,B,C,E) and group G2 (D), one real NBA game ──
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000e1');
insert into profiles (id, username) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'), ('00000000-0000-0000-0000-0000000000b1', 'bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carol'), ('00000000-0000-0000-0000-0000000000d1', 'dave'),
  ('00000000-0000-0000-0000-0000000000e1', 'erin');
create temp table ids (name text primary key, id uuid, txt text);
grant all on ids to public;

call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('g1', create_group('Friends'));
call pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
insert into ids (name, id) values ('g2', create_group('Other Group'));
do $$ declare code text; begin
  select invite_code into code from groups where id = (select id from ids where name = 'g1');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true); perform join_group(code);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true); perform join_group(code);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', true); perform join_group(code);
end $$;

select ingest_markets('nba', :'open_nba_game'::jsonb, '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');           -- "now" for these tests
insert into ids (name, txt) select 'ml', id from markets where market_type = 'moneyline';

create function pg_temp.g1() returns uuid language sql as $$ select id from ids where name = 'g1' $$;
create function pg_temp.ml() returns text language sql as $$ select txt from ids where name = 'ml' $$;
create function pg_temp.bal(p_user text, p_what text) returns bigint language sql as $$
  select case p_what when 'avail' then available when 'esc' then escrow else available + escrow end
    from group_members where group_id = pg_temp.g1() and user_id = ('00000000-0000-0000-0000-0000000000' || p_user || '1')::uuid $$;
create function pg_temp.healthy() returns boolean language sql as $$
  select not exists (select 1 from check_ledger_integrity()) and not exists (select 1 from check_betting_integrity()) $$;

do $$ begin assert pg_temp.healthy(), 'books balance at the start'; end $$;

-- ───────── Post ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o1', post_offer(pg_temp.g1(), pg_temp.ml(), 0, 60, 100));   -- "Celtics win, 60¢, 100 shares"
do $$ declare o offers; begin
  select * into o from offers where id = (select id from ids where name = 'o1');
  assert o.maker_id = '00000000-0000-0000-0000-0000000000a1' and o.outcome = 0 and o.price_cents = 60, 'offer stored';
  assert o.shares_total = 100 and o.shares_open = 100 and o.status = 'open' and o.shares_cancelled = 0, 'all shares open';
  assert o.season_id = (select current_season_id from groups where id = o.group_id), 'current season recorded';
  assert pg_temp.bal('a', 'avail') = 4000 and pg_temp.bal('a', 'esc') = 6000, 'maker escrows 100 × 60¢ = 60 coins';
  assert pg_temp.bal('a', 'total') = 10000, 'nothing created or destroyed';
  assert (select tracked from markets where id = pg_temp.ml()), 'market is now tracked by the refresh job';
  assert pg_temp.healthy(), 'books balance after post';
end $$;

-- ───────── Post: validation ─────────
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 2, 60, 1) $q$, '%invalid_outcome%');
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), null, 60, 1) $q$, '%invalid_outcome%');
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 0, 0, 1) $q$, '%invalid_price%');
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 0, 100, 1) $q$, '%invalid_price%');
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, 0) $q$, '%invalid_shares%');
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, -3) $q$, '%invalid_shares%');
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 0, 60, 100) $q$, '%insufficient_balance%');   -- only 40 coins left
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), 'no-such-market', 0, 50, 1) $q$, '%market_not_found%');
call pg_temp.expect_error($q$ select post_offer((select id from ids where name = 'g2'), pg_temp.ml(), 0, 50, 1) $q$, '%not_a_member%');
call pg_temp.expect_error($q$ select post_offer(gen_random_uuid(), pg_temp.ml(), 0, 50, 1) $q$, '%not_a_member%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, 1) $q$, '%not_signed_in%');
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
-- exactly the whole balance is fine (40 coins = 80 × 50¢)
insert into ids (name, id) values ('o_all_in', post_offer(pg_temp.g1(), pg_temp.ml(), 1, 50, 80));
do $$ begin assert pg_temp.bal('a', 'avail') = 0 and pg_temp.bal('a', 'esc') = 10000, 'can stake exactly everything'; end $$;
call pg_temp.expect_error($q$ select post_offer(pg_temp.g1(), pg_temp.ml(), 1, 1, 1) $q$, '%insufficient_balance%');
select cancel_offer((select id from ids where name = 'o_all_in'));
do $$ begin assert pg_temp.bal('a', 'avail') = 4000 and pg_temp.bal('a', 'esc') = 6000, 'cancel refunds the 40 coins'; end $$;

-- ───────── Market state gates ─────────
do $$ begin
  update markets set accepting = false where id = pg_temp.ml();
  begin perform post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, 1); assert false, 'not accepting must block'; exception when others then assert sqlerrm = 'market_not_open', sqlerrm; end;
  update markets set accepting = true, closed = true where id = pg_temp.ml();
  begin perform post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, 1); assert false, 'closed must block'; exception when others then assert sqlerrm = 'market_not_open', sqlerrm; end;
  update markets set closed = false, resolution = 'void' where id = pg_temp.ml();
  begin perform post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, 1); assert false, 'resolved must block'; exception when others then assert sqlerrm = 'market_not_open', sqlerrm; end;
  update markets set resolution = 'pending' where id = pg_temp.ml();
  update clock_override set at = '2026-10-08 23:00:00+00';                 -- the instant the game starts
  begin perform post_offer(pg_temp.g1(), pg_temp.ml(), 0, 50, 1); assert false, 'no betting once started'; exception when others then assert sqlerrm = 'market_not_open', sqlerrm; end;
  update clock_override set at = '2026-10-08 22:59:59+00';
  perform post_offer(pg_temp.g1(), pg_temp.ml(), 0, 1, 1);                 -- one second before start is still fine
  update clock_override set at = '2026-10-08 12:00+00';
end $$;
select cancel_offer((select id from offers where maker_id = '00000000-0000-0000-0000-0000000000a1' and price_cents = 1));

-- ───────── Take: the example from CLAUDE.md ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
insert into ids (name, id) values ('b1', take_offer((select id from ids where name = 'o1'), 50));   -- fade 50 of the 100 shares
do $$ declare b bets; begin
  select * into b from bets where id = (select id from ids where name = 'b1');
  assert b.maker_stake = 3000 and b.taker_stake = 2000, '50 shares @60¢: maker 30 coins vs taker 20 coins';
  assert b.maker_stake + b.taker_stake = 5000, 'pot is exactly 50 coins';
  assert b.maker_id = '00000000-0000-0000-0000-0000000000a1' and b.taker_id = '00000000-0000-0000-0000-0000000000b1', 'sides';
  assert b.maker_outcome = 0 and b.price_cents = 60 and b.shares = 50 and b.status = 'pending', 'bet details';
  assert (select shares_open from offers where id = b.offer_id) = 50 and (select status from offers where id = b.offer_id) = 'open', '50 shares stay open';
  assert pg_temp.bal('b', 'avail') = 8000 and pg_temp.bal('b', 'esc') = 2000, 'taker escrows 20 coins';
  assert pg_temp.bal('a', 'avail') = 4000 and pg_temp.bal('a', 'esc') = 6000, 'maker balance unchanged by a take (stake already escrowed)';
  assert pg_temp.healthy(), 'books balance after take';
end $$;
-- a second taker buys the rest; the offer becomes "filled"
call pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into ids (name, id) values ('b2', take_offer((select id from ids where name = 'o1'), 50));
do $$ begin
  assert (select status from offers where id = (select id from ids where name = 'o1')) = 'filled', 'offer filled';
  assert (select shares_open from offers where id = (select id from ids where name = 'o1')) = 0, 'no shares left';
  assert pg_temp.healthy(), 'books balance after full fill';
end $$;
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o1'), 1) $q$, '%offer_not_open%');

-- ───────── Take: validation ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o2', post_offer(pg_temp.g1(), pg_temp.ml(), 1, 30, 20));      -- backs the 2nd team at 30¢, 20 shares
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), 1) $q$, '%cannot_take_own_offer%');
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), 0) $q$, '%invalid_shares%');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), null) $q$, '%invalid_shares%');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), 21) $q$, '%not_enough_shares%');
call pg_temp.expect_error($q$ select take_offer(gen_random_uuid(), 1) $q$, '%offer_not_found%');
call pg_temp.expect_error($q$ select cancel_offer((select id from ids where name = 'o2')) $q$, '%not_offer_maker%');
-- a person in a different group cannot see, take or cancel it, and learns nothing about it
call pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), 1) $q$, '%offer_not_found%');
call pg_temp.expect_error($q$ select cancel_offer((select id from ids where name = 'o2')) $q$, '%offer_not_found%');
-- a member with too little available cannot take: C locks up 80 coins, then tries
call pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into ids (name, id) values ('o_c', post_offer(pg_temp.g1(), pg_temp.ml(), 0, 80, 100));
do $$ begin assert pg_temp.bal('c', 'avail') = 0 and pg_temp.bal('c', 'esc') = 10000, 'C is fully committed'; end $$;
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), 1) $q$, '%insufficient_balance%');

-- ───────── Partial fill, then cancel: only the unfilled shares come back ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
insert into ids (name, id) values ('b3', take_offer((select id from ids where name = 'o2'), 5));      -- 5 × 70¢ = 3.5 coins
do $$ begin assert pg_temp.bal('b', 'avail') = 7650 and pg_temp.bal('b', 'esc') = 2350, 'B escrowed 3.5 more coins'; end $$;
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
do $$ declare refund bigint; begin
  refund := cancel_offer((select id from ids where name = 'o2'));
  assert refund = 450, '15 unfilled shares × 30¢ = 4.5 coins refunded, got ' || refund;
  assert (select status from offers where id = (select id from ids where name = 'o2')) = 'cancelled', 'offer cancelled';
  assert (select shares_cancelled from offers where id = (select id from ids where name = 'o2')) = 15, '15 shares cancelled';
  assert (select status from bets where id = (select id from ids where name = 'b3')) = 'pending', 'the 5 taken shares stand';
  assert pg_temp.bal('a', 'avail') = 3850 and pg_temp.bal('a', 'esc') = 6150, 'maker escrow now covers only taken shares';
  assert pg_temp.healthy(), 'books balance after cancel';
end $$;
call pg_temp.expect_error($q$ select cancel_offer((select id from ids where name = 'o2')) $q$, '%offer_not_open%');
call pg_temp.expect_error($q$ select cancel_offer((select id from ids where name = 'o1')) $q$, '%offer_not_open%');     -- fully filled
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o2'), 1) $q$, '%offer_not_open%');

-- ───────── Event start: no live betting; unfilled shares cancel automatically ─────────
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o3', post_offer(pg_temp.g1(), pg_temp.ml(), 0, 10, 10));
update clock_override set at = '2026-10-08 23:00:00+00';
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o3'), 1) $q$, '%market_not_open%');
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
call pg_temp.expect_error($q$ select cancel_offer((select id from ids where name = 'o3')) $q$, '%market_started%');
do $$ begin
  assert auto_cancel_started() = 2, 'o3 (A) and o_c (C) were still open';
  assert (select count(*) from offers where status = 'open') = 0, 'nothing open after start';
  assert (select cancel_reason from offers where id = (select id from ids where name = 'o3')) = 'started', 'reason recorded';
  assert pg_temp.bal('c', 'avail') = 0 + 8000 and pg_temp.bal('c', 'esc') = 2000, 'C got the 80 coins back (keeps the 20 she staked in her take)';
  assert auto_cancel_started() = 0, 'second run does nothing (idempotent)';
  assert pg_temp.healthy(), 'books balance after auto-cancel';
end $$;

-- A market that closes early (e.g. postponement) also clears its open offers.
update clock_override set at = '2026-10-08 12:00+00';
insert into ids (name, txt) select 'sp', id from markets where market_type = 'spreads' order by id limit 1;
call pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ids (name, id) values ('o4', post_offer(pg_temp.g1(), (select txt from ids where name = 'sp'), 0, 40, 10));
update markets set closed = true where id = (select txt from ids where name = 'sp');
call pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
call pg_temp.expect_error($q$ select take_offer((select id from ids where name = 'o4'), 1) $q$, '%market_not_open%');
do $$ begin
  assert auto_cancel_started() = 1, 'closed market offer cancelled';
  assert (select cancel_reason from offers where id = (select id from ids where name = 'o4')) = 'market_closed', 'reason: market_closed';
  assert pg_temp.healthy(), 'books balance';
  assert (select sum(available + escrow) from group_members where group_id = pg_temp.g1()) = 40000, 'four members × 100 coins: betting never creates or destroys coins';
end $$;
update markets set closed = false where id = (select txt from ids where name = 'sp');

-- ───────── Who can see and do what ─────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
do $$ begin
  assert (select count(*) from offer_listing) = 7, 'B sees all 7 offers ever posted in his group (o1, all-in, 1-cent, o2, o_c, o3, o4)';
  assert (select count(*) from bet_listing) = 3, 'B sees the 3 bets of his group';
  assert (select maker_username from offer_listing where id = (select id from ids where name = 'o1')) = 'alice', 'maker name shown';
  assert (select count(*) from bet_listing where taker_username = 'bob' and maker_username = 'alice') = 2, 'bets show both names';
  assert (select count(*) from bet_listing where phase = 'upcoming') = 3, 'phase available on bets';
end $$;
call pg_temp.expect_error($q$ insert into offers (group_id, season_id, maker_id, market_id, outcome, price_cents, shares_total, shares_open) select group_id, season_id, maker_id, market_id, 0, 50, 5, 5 from offers limit 1 $q$, '%permission denied%');
call pg_temp.expect_error($q$ update offers set shares_open = 0 $q$, '%permission denied%');
call pg_temp.expect_error($q$ update bets set status = 'won_taker', settled_at = now() $q$, '%permission denied%');
call pg_temp.expect_error($q$ delete from bets $q$, '%permission denied%');
call pg_temp.expect_error($q$ select auto_cancel_started() $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from check_betting_integrity() $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from clock_override $q$, '%permission denied%');
call pg_temp.expect_error($q$ update markets set accepting = true $q$, '%permission denied%');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);       -- Dave: other group
do $$ begin
  assert (select count(*) from offer_listing) = 0 and (select count(*) from bet_listing) = 0, 'outsiders see no offers or bets';
  assert (select count(*) from offers) = 0 and (select count(*) from bets) = 0, 'nor the raw tables';
end $$;
reset role;
set local role anon;
call pg_temp.expect_error($q$ select post_offer(gen_random_uuid(), 'x', 0, 50, 1) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select take_offer(gen_random_uuid(), 1) $q$, '%permission denied%');
reset role;

-- ───────── The database itself refuses nonsense, even if a bug tried to write it ─────────
do $$ declare o offers; begin
  select * into o from offers limit 1;
  begin  -- betting against yourself
    insert into bets (offer_id, group_id, season_id, market_id, maker_id, taker_id, maker_outcome, price_cents, shares, maker_stake, taker_stake)
    values (o.id, o.group_id, o.season_id, o.market_id, o.maker_id, o.maker_id, 0, 60, 1, 60, 40);
    assert false, 'self-bet accepted';
  exception when check_violation then null; end;
  begin  -- stakes that do not fill the pot
    insert into bets (offer_id, group_id, season_id, market_id, maker_id, taker_id, maker_outcome, price_cents, shares, maker_stake, taker_stake)
    values (o.id, o.group_id, o.season_id, o.market_id, o.maker_id, '00000000-0000-0000-0000-0000000000e1', 0, 60, 1, 60, 39);
    assert false, 'short pot accepted';
  exception when check_violation then null; end;
  begin  -- more shares open than exist
    update offers set shares_open = shares_total + 1 where id = o.id;
    assert false, 'impossible offer accepted';
  exception when check_violation then null; end;
end $$;

-- ───────── Random operations: thousands of posts, takes, cancels, clock ticks ─────────
-- Afterwards every integrity check must still pass and the group must hold exactly the coins it was given.
do $$
declare
  users uuid[] := array['00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
                        '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000e1']::uuid[];
  markets_ text[] := array(select id from markets where league = 'nba' order by id);
  g uuid := pg_temp.g1();
  off record; err text; i integer; r double precision; u uuid;
  n_post integer := 0; n_take integer := 0; n_cancel integer := 0; n_auto integer := 0; n_err integer := 0;
  allowed text[] := array['insufficient_balance', 'market_not_open', 'offer_not_open', 'not_enough_shares',
                          'cannot_take_own_offer', 'not_offer_maker', 'market_started'];
begin
  perform setseed(0.31337);
  -- a bigger bankroll (5,000 extra coins each, as buybacks) so the run can go deep
  foreach u in array users loop perform ledger_post(gen_random_uuid(), g, u, 'available', 500000, 'buyback'); end loop;
  update clock_override set at = '2026-10-08 12:00+00';
  for i in 1..4000 loop
    u := users[1 + floor(random() * 4)::int];
    perform set_config('request.jwt.claim.sub', u::text, true);
    r := random();
    begin
      if i = 2500 then                                          -- the game starts: everything open must clear
        update clock_override set at = '2026-10-08 23:00:00+00';
      elsif i = 1500 then                                       -- one market closes early (postponement)
        update markets set closed = true where id = markets_[3];
      elsif r < 0.30 then
        perform post_offer(g, markets_[1 + floor(random() * array_length(markets_, 1))::int],
                           floor(random() * 2)::int, 1 + floor(random() * 99)::int, 1 + floor(random() * 40)::int);
        n_post := n_post + 1;
      elsif r < 0.75 then
        select id, shares_open into off from offers where group_id = g and status = 'open' order by random() limit 1;
        if off.id is not null then
          perform take_offer(off.id, 1 + floor(random() * off.shares_open)::int);
          n_take := n_take + 1;
        end if;
        off := null;
      elsif r < 0.90 then
        select id into off from offers where group_id = g and status = 'open' order by random() limit 1;
        if off.id is not null then perform cancel_offer(off.id); n_cancel := n_cancel + 1; end if;
        off := null;
      elsif r < 0.95 then
        n_auto := n_auto + auto_cancel_started();
      end if;
    exception when others then
      err := sqlerrm;
      if err <> all (allowed) then raise exception 'UNEXPECTED ERROR in random run at step %: %', i, err; end if;
      n_err := n_err + 1;
    end;
    if i % 400 = 0 then
      assert pg_temp.healthy(), 'books out of balance at step ' || i;
      assert (select sum(available + escrow) from group_members where group_id = g) = 2040000, 'coins created or destroyed at step ' || i;
    end if;
  end loop;
  perform auto_cancel_started();
  assert pg_temp.healthy(), 'books balance after the random run';
  assert (select sum(available + escrow) from group_members where group_id = g) = 2040000, 'coins conserved after random run';
  assert n_post > 200 and n_take > 200 and n_cancel > 50 and n_auto > 20, format('run too thin: post %s take %s cancel %s auto %s', n_post, n_take, n_cancel, n_auto);
  assert exists (select 1 from offers where status = 'filled') and exists (select 1 from offers where status = 'cancelled' and shares_total > shares_cancelled),
         'saw fully filled offers and partly filled then cancelled offers';
  assert (select count(*) from bets) > 150, 'plenty of bets created';
  assert not exists (select 1 from offers where status = 'open'), 'no open offers once the game has started';
  raise notice 'random run: % posts, % takes, % cancels, % auto-cancels, % refused, % bets', n_post, n_take, n_cancel, n_auto, n_err, (select count(*) from bets);
end $$;

rollback;
