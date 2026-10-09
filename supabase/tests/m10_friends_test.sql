-- Milestone 10 tests: friend requests, suggestions, and the friends leaderboard.
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

insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c','d','e','f','7']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n
    from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave'),('e','erin'),('f','frank'),('7','grace')) v(u, n);
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb);
create temp table ids (name text primary key, id uuid);
grant all on ids to public;
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

create function pg_temp.gid(p text) returns uuid language sql as $$ select id from ids where name = p $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
create function pg_temp.healthy() returns boolean language sql as $$
  select not exists (select 1 from check_ledger_integrity()) and not exists (select 1 from check_betting_integrity())
     and not exists (select 1 from check_season_integrity()) $$;
create function pg_temp.mkt(p text, n integer default 0) returns text language sql as $$
  select id from markets where case p when 'ml' then market_type = 'moneyline' when 'sp' then market_type = 'spreads' else market_type = 'totals' end
   order by id offset n limit 1 $$;
create function pg_temp.finish(p_market text, p_prices text) returns void language plpgsql as $$
declare e jsonb;
begin
  select x into e from fx, jsonb_array_elements(fx.payload) x where x ->> 'id' = p_market;
  perform ingest_markets('nba', jsonb_build_array(e || jsonb_build_object('closed', true, 'umaResolutionStatus', 'resolved', 'outcomePrices', p_prices)), '2026-10-08 12:00+00');
  perform settle_resolved_markets();
end $$;

-- Groups: G1 = alice, bobby, carol. G2 = alice, dave. G3 = alice, carol, dave. Erin, frank and grace are elsewhere.
call pg_temp.as_user('a');
insert into ids values ('g1', create_group('Group One', 10000, 'unlimited', null, 10000)), ('g2', create_group('Group Two', 10000, 'unlimited', null, 10000)), ('g3', create_group('Group Three', 10000, 'unlimited', null, 10000));
do $$ declare u text; code text; g text; begin
  for u, g in select * from (values ('b','g1'),('c','g1'),('d','g2'),('c','g3'),('d','g3')) v(a, b) loop
    select invite_code into code from groups where id = pg_temp.gid(g);
    perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true); perform join_group(code);
  end loop;
end $$;
call pg_temp.as_user('e'); insert into ids values ('ge', create_group('Erin Only', 10000, 'unlimited', null, 10000));

-- ═════════ 1. Requests ═════════
call pg_temp.as_user('a');
do $$ begin assert send_friend_request('  BOBBY ') = 'sent', 'usernames are matched ignoring case and spaces'; end $$;
call pg_temp.expect_error($q$ select send_friend_request('bobby') $q$, '%request_pending%');
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%invalid_target%');
call pg_temp.expect_error($q$ select send_friend_request('nobody_here') $q$, '%user_not_found%');
call pg_temp.expect_error($q$ select send_friend_request('') $q$, '%user_not_found%');
call pg_temp.expect_error($q$ select send_friend_request(null) $q$, '%user_not_found%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select send_friend_request('bobby') $q$, '%not_signed_in%');
do $$ begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('a')::text, true);
  assert (select count(*) from my_friend_requests() where direction = 'outgoing' and username = 'bobby') = 1, 'alice sees her outgoing request';
  perform set_config('request.jwt.claim.sub', pg_temp.u('b')::text, true);
  assert (select count(*) from my_friend_requests() where direction = 'incoming' and username = 'alice') = 1, 'bobby sees the incoming request';
  assert (select count(*) from friend_scores()) = 1, 'a pending request does not make you friends yet';
end $$;
call pg_temp.expect_error($q$ select respond_friend_request(pg_temp.u('c'), true) $q$, '%request_not_found%');
call pg_temp.expect_error($q$ select respond_friend_request(pg_temp.u('a'), null) $q$, '%invalid_target%');
-- the person who SENT it cannot accept their own request
call pg_temp.as_user('a');
call pg_temp.expect_error($q$ select respond_friend_request(pg_temp.u('b'), true) $q$, '%request_not_found%');
call pg_temp.as_user('b');
select respond_friend_request(pg_temp.u('a'), true);
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%already_friends%');
do $$ begin assert (select count(*) from my_friend_requests()) = 0, 'no requests left once accepted'; end $$;

-- decline: the row disappears and they may ask again
call pg_temp.as_user('c'); select send_friend_request('alice');
call pg_temp.as_user('a'); select respond_friend_request(pg_temp.u('c'), false);
do $$ begin assert not exists (select 1 from friendships where requester = pg_temp.u('c')), 'declined request is gone'; end $$;
call pg_temp.as_user('c'); select send_friend_request('alice');                                         -- may ask again
-- asking someone who already asked you = yes
call pg_temp.as_user('a');
do $$ begin assert send_friend_request('carol') = 'accepted', 'mutual request becomes a friendship'; end $$;
-- cancel an outgoing request
call pg_temp.as_user('a'); select send_friend_request('dave');
do $$ begin
  perform cancel_friend_request(pg_temp.u('d'));
  assert not exists (select 1 from friendships where addressee = pg_temp.u('d')), 'cancelled';
  perform cancel_friend_request(pg_temp.u('d'));                                                          -- nothing to cancel: harmless
end $$;
-- you can't cancel on someone else's behalf, or remove a non-friend
call pg_temp.as_user('d'); select send_friend_request('alice');
call pg_temp.as_user('b'); select cancel_friend_request(pg_temp.u('d')); select remove_friend(pg_temp.u('d'));
do $$ begin assert exists (select 1 from friendships where requester = pg_temp.u('d') and addressee = pg_temp.u('a')), 'unrelated people cannot touch it'; end $$;
call pg_temp.as_user('a'); select respond_friend_request(pg_temp.u('d'), true);

-- ═════════ 2. The friends leaderboard ═════════
-- Alice vs bobby: a real, settled bet in Group One. Alice wins 40 coins from bobby.
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('g1'), pg_temp.mkt('ml'), 0, 60, 100);
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('a')), 100);
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');
-- Dave wins 10 coins from carol in Group Three.
call pg_temp.as_user('d'); select post_offer(pg_temp.gid('g3'), pg_temp.mkt('sp'), 0, 50, 20);
call pg_temp.as_user('c'); select take_offer((select id from offers where maker_id = pg_temp.u('d') and group_id = pg_temp.gid('g3')), 20);
select pg_temp.finish(pg_temp.mkt('sp'), '["1", "0"]');
call pg_temp.as_user('a');
do $$ declare r record; begin
  assert (select count(*) from friend_scores()) = 4, 'me + bobby + carol + dave';
  select * into r from friend_scores() where is_me;
  assert r.username = 'alice' and r.score = 4000 and r.wins = 1 and r.losses = 0, 'alice: +40, record 1-0';
  assert (select score from friend_scores() where username = 'bobby') = -4000, 'bobby: −40';
  assert (select score from friend_scores() where username = 'dave') = 1000, 'dave: +10';
  assert (select score from friend_scores() where username = 'carol') = -1000, 'carol: −10';
  assert (select array_agg(username order by score desc, username) from friend_scores()) = array['alice', 'dave', 'carol', 'bobby'], 'ranked by score';
  assert not exists (select 1 from friend_scores() where username in ('erin', 'frank', 'grace')), 'strangers never appear';
end $$;
-- carol's view: she is friends with alice only
call pg_temp.as_user('c');
do $$ begin assert (select array_agg(username order by username) from friend_scores()) = array['alice', 'carol'], 'friendship works both ways, and not through other friends'; end $$;
-- a buyback counts against the score
reset role; call pg_temp.as_user('b');
do $$ declare v_amt bigint; v_tx uuid := gen_random_uuid(); begin
  select available into v_amt from group_members where group_id = pg_temp.gid('g1') and user_id = pg_temp.u('b');
  perform ledger_post(v_tx, pg_temp.gid('g1'), pg_temp.u('b'), 'available', -v_amt, 'escrow_release');
  perform ledger_post(v_tx, pg_temp.gid('g1'), pg_temp.u('a'), 'available',  v_amt, 'escrow_release');
end $$;
select claim_buyback(pg_temp.gid('g1'));
call pg_temp.as_user('a');
do $$ begin assert (select score from friend_scores() where username = 'bobby') = -10000 - 0 + 6000 - 6000 or (select score from friend_scores() where username = 'bobby') < -4000, 'bobby is even further down after losing the rest and buying back'; end $$;
-- scores survive leaving a group
call pg_temp.as_user('b'); select leave_group(pg_temp.gid('g1'));
call pg_temp.as_user('a');
do $$ declare s bigint; begin
  select score into s from friend_scores() where username = 'bobby';
  assert s = (select lifetime_closed_profit from profiles where id = pg_temp.u('b')), 'after leaving, bobby''s score is exactly his closed profit';
  assert s < -4000, 'and it still counts what he lost';
end $$;

-- ═════════ 3. Suggestions ═════════
call pg_temp.as_user('a');
do $$ begin
  -- alice shares G1 with carol (friend), G2 with dave (friend), G3 with carol & dave: everyone is already a friend
  assert (select count(*) from friend_suggestions()) = 0, 'nobody left to suggest';
end $$;
call pg_temp.as_user('e'); select join_group((select invite_code from groups where id = pg_temp.gid('g3')));      -- erin joins Group Three
call pg_temp.as_user('a');
do $$ begin
  assert (select array_agg(username) from friend_suggestions()) = array['erin'], 'erin is suggested (shares Group Three)';
  assert (select shared_groups from friend_suggestions() where username = 'erin') = 1, 'with 1 shared group';
end $$;
call pg_temp.as_user('e'); select join_group((select invite_code from groups where id = pg_temp.gid('g2')));      -- ...and Group Two
call pg_temp.as_user('a');
do $$ begin assert (select shared_groups from friend_suggestions() where username = 'erin') = 2, 'two shared groups now'; end $$;
-- not suggested once a request is pending, once blocked, or once banned
select send_friend_request('erin');
do $$ begin assert (select count(*) from friend_suggestions()) = 0, 'a pending request removes the suggestion'; end $$;
select cancel_friend_request(pg_temp.u('e'));
select block_user(pg_temp.u('e'));
do $$ begin assert (select count(*) from friend_suggestions()) = 0, 'a blocked person is not suggested'; end $$;
select unblock_user(pg_temp.u('e'));
select mod_ban_user(pg_temp.u('e'));
do $$ begin assert (select count(*) from friend_suggestions()) = 0, 'a banned person is not suggested'; end $$;
select mod_unban_user(pg_temp.u('e'));
call pg_temp.as_user('f');
do $$ begin assert (select count(*) from friend_suggestions()) = 0, 'someone in no group gets no suggestions'; end $$;

-- ═════════ 4. Blocks and bans ═════════
call pg_temp.as_user('a'); select block_user(pg_temp.u('e'));
call pg_temp.expect_error($q$ select send_friend_request('erin') $q$, '%user_not_found%');                    -- I blocked her
call pg_temp.as_user('e');
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%user_not_found%');                   -- she can't find me either
call pg_temp.as_user('a'); select unblock_user(pg_temp.u('e'));
-- blocking an existing friend ends the friendship
call pg_temp.as_user('a'); select block_user(pg_temp.u('d'));
do $$ begin
  assert not exists (select 1 from friend_scores() where username = 'dave'), 'a blocked friend leaves the leaderboard';
  assert not exists (select 1 from friendships where (requester = pg_temp.u('a') and addressee = pg_temp.u('d')) or (requester = pg_temp.u('d') and addressee = pg_temp.u('a'))), 'the friendship row is gone';
end $$;
call pg_temp.as_user('d');
do $$ begin assert not exists (select 1 from friend_scores() where username = 'alice'), 'and from her side too'; end $$;
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%user_not_found%');
-- a banned user can't be requested and can't request
call pg_temp.as_user('a'); select unblock_user(pg_temp.u('d'));
select mod_ban_user(pg_temp.u('7'));
call pg_temp.expect_error($q$ select send_friend_request('grace') $q$, '%user_not_found%');
call pg_temp.as_user('7');
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%account_disabled%');
select mod_unban_user(pg_temp.u('7'));

-- ═════════ 5. Remove a friend, and the 50-request cap ═════════
call pg_temp.as_user('a'); select remove_friend(pg_temp.u('c'));
do $$ begin
  assert not exists (select 1 from friend_scores() where username = 'carol'), 'removed';
  perform set_config('request.jwt.claim.sub', pg_temp.u('c')::text, true);
  assert not exists (select 1 from friend_scores() where username = 'alice'), 'removed from both sides';
end $$;
insert into auth.users (id) select ('10000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid from generate_series(1, 50) i;
insert into profiles (id, username) select ('10000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'extra' || lpad(i::text, 3, '0') from generate_series(1, 50) i;
call pg_temp.as_user('f');
do $$ declare i integer; begin
  for i in 1..50 loop perform send_friend_request('extra' || lpad(i::text, 3, '0')); end loop;
  begin perform send_friend_request('alice'); assert false, 'cap not enforced'; exception when others then assert sqlerrm = 'too_many_requests', sqlerrm; end;
end $$;

-- accepting one request must not accept the same person's OTHER pending requests
do $$ declare s uuid := '10000000-0000-0000-0000-000000000001'; r1 uuid := '10000000-0000-0000-0000-000000000002'; r2 uuid := '10000000-0000-0000-0000-000000000003';
begin
  perform set_config('request.jwt.claim.sub', s::text, true);
  perform send_friend_request('extra002'); perform send_friend_request('extra003');
  perform set_config('request.jwt.claim.sub', r1::text, true);
  perform respond_friend_request(s, true);
  assert (select status from friendships where requester = s and addressee = r1) = 'accepted', 'accepted by the person it was sent to';
  assert (select status from friendships where requester = s and addressee = r2) = 'pending', 'their other request is untouched';
end $$;

-- ═════════ 6. Privacy and permissions ═════════
set local role authenticated;
call pg_temp.as_user('f');
do $$ begin assert (select count(*) from friendships) = 50, 'you only see your own requests in the table'; end $$;
call pg_temp.expect_error($q$ insert into friendships (requester, addressee, status) values (pg_temp.u('f'), pg_temp.u('a'), 'accepted') $q$, '%permission denied%');
call pg_temp.expect_error($q$ update friendships set status = 'accepted' $q$, '%permission denied%');
call pg_temp.expect_error($q$ select requestable_user('alice') $q$, '%permission denied%');
do $$ begin assert (select count(*) from friend_scores()) = 1, 'frank has no friends yet, only himself'; end $$;
reset role;
set local role anon;
call pg_temp.expect_error($q$ select * from friend_scores() $q$, '%permission denied%');
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from friend_suggestions() $q$, '%permission denied%');
reset role;
do $$ begin assert pg_temp.healthy(), 'friends never touch the money books'; end $$;
rollback;
