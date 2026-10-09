\set ON_ERROR_STOP on
-- Builds a busy, realistic database through the same server functions the app calls (see run.sh).
\set open_nba_game `cat ../fixtures/open_nba_game.json`
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb);
create temp table ids (name text primary key, id uuid, code text);
grant all on ids to public;
insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c','d','e','f']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n
    from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave'),('e','erin'),('f','fred')) v(u, n);
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

create procedure pg_temp.as_user(p_user text) language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', ('00000000-0000-0000-0000-0000000000' || p_user || '1'), false); end $$;
create function pg_temp.gid(p text) returns uuid language sql as $$ select id from ids where name = p $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;
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


-- ═════ groups ═════
call pg_temp.as_user('a');
insert into ids (name, id) values ('G1', create_group('Main Crew', 10000, 'unlimited', null, 10000)),
                                  ('G2', create_group('Weekly Crew', 10000, 'weekly', 2, 5000)),
                                  ('G3', create_group('Vote Crew', 10000, 'vote', null, 7500));
update ids set code = (select invite_code from groups g where g.id = ids.id);
do $$ declare c1 text := (select code from ids where name='G1'); c2 text := (select code from ids where name='G2'); c3 text := (select code from ids where name='G3'); u text; begin
  foreach u in array array['b','c','d','e','f'] loop perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, false); perform join_group(c1); end loop;
  foreach u in array array['b','c'] loop perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, false); perform join_group(c2); end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.u('b')::text, false); perform join_group(c3);
end $$;

-- ═════ bets in G1 ═════
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('G1'), pg_temp.mkt('ml'), 0, 50, 20);
call pg_temp.as_user('d'); select take_offer((select id from offers where maker_id = pg_temp.u('a') and market_id = pg_temp.mkt('ml')), 20);
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('G1'), pg_temp.mkt('sp'), 0, 40, 10);
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('a') and market_id = pg_temp.mkt('sp')), 6);
call pg_temp.as_user('c'); select post_offer(pg_temp.gid('G1'), pg_temp.mkt('tot'), 1, 30, 10);
call pg_temp.as_user('a'); select take_offer((select id from offers where maker_id = pg_temp.u('c') and market_id = pg_temp.mkt('tot')), 10);
call pg_temp.as_user('b'); select post_offer(pg_temp.gid('G1'), pg_temp.mkt('tot', 1), 0, 65, 7);
-- a voided bet (50/50)
call pg_temp.as_user('c'); select post_offer(pg_temp.gid('G1'), pg_temp.mkt('sp', 1), 0, 55, 5);
call pg_temp.as_user('d'); select take_offer((select id from offers where maker_id = pg_temp.u('c') and market_id = pg_temp.mkt('sp', 1)), 5);
select pg_temp.finish(pg_temp.mkt('sp', 1), '["0.5", "0.5"]');
-- a cancelled offer
call pg_temp.as_user('d'); select post_offer(pg_temp.gid('G1'), pg_temp.mkt('tot', 2), 1, 45, 3);
select cancel_offer((select id from offers where maker_id = pg_temp.u('d') and market_id = pg_temp.mkt('tot', 2)));

-- ═════ G2 (weekly): bobby loses everything, buys back ═════
call pg_temp.as_user('b'); select post_offer(pg_temp.gid('G2'), pg_temp.mkt('tot', 3), 0, 50, 200);
call pg_temp.as_user('c'); select take_offer((select id from offers where maker_id = pg_temp.u('b') and market_id = pg_temp.mkt('tot', 3)), 200);
select pg_temp.finish(pg_temp.mkt('tot', 3), '["0", "1"]');
call pg_temp.as_user('b'); select claim_buyback(pg_temp.gid('G2'));

-- ═════ G3 (vote): bobby busted, asks the group; then a reset vote passes ═════
call pg_temp.as_user('b'); select post_offer(pg_temp.gid('G3'), pg_temp.mkt('tot', 4), 0, 50, 200);
call pg_temp.as_user('a'); select take_offer((select id from offers where maker_id = pg_temp.u('b') and market_id = pg_temp.mkt('tot', 4)), 200);
select pg_temp.finish(pg_temp.mkt('tot', 4), '["0", "1"]');
call pg_temp.as_user('b'); select call_vote(pg_temp.gid('G3'), 'buyback');
call pg_temp.as_user('a'); select cast_vote((select id from votes where group_id = pg_temp.gid('G3') and kind = 'buyback' and status = 'open'), true);
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('G3'), pg_temp.mkt('sp', 2), 0, 50, 10);   -- will be cancelled by the reset
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('a') and market_id = pg_temp.mkt('sp', 2)), 4);
call pg_temp.as_user('a'); select call_vote(pg_temp.gid('G3'), 'reset');
call pg_temp.as_user('b'); select cast_vote((select id from votes where group_id = pg_temp.gid('G3') and kind = 'reset' and status = 'open'), true);

-- ═════ an open reset vote in G1 with a ballot ═════
call pg_temp.as_user('c'); select call_vote(pg_temp.gid('G1'), 'reset');
call pg_temp.as_user('a'); select cast_vote((select id from votes where group_id = pg_temp.gid('G1') and status = 'open'), false);

-- ═════ social ═════
call pg_temp.as_user('a');
select send_friend_request('bobby'); select send_friend_request('carol');
call pg_temp.as_user('b'); select respond_friend_request(pg_temp.u('a'), true);
call pg_temp.as_user('d'); select send_friend_request('alice');
call pg_temp.as_user('a');
select mute_user(pg_temp.u('e'));
call pg_temp.as_user('c'); select block_user(pg_temp.u('d'));
call pg_temp.as_user('a');
select register_device_token(repeat('a', 64)); select set_notification_pref('new_offer', false);
select toggle_reaction((select id from feed_items where kind = 'offer_taken' and group_id = pg_temp.gid('G1') order by created_at limit 1), '🔥');
select add_comment((select id from feed_items where kind = 'offer_taken' and group_id = pg_temp.gid('G1') order by created_at limit 1), 'my comment');
call pg_temp.as_user('b'); select toggle_reaction((select id from feed_items where kind = 'offer_taken' and group_id = pg_temp.gid('G1') order by created_at limit 1), '😂');
select add_comment((select id from feed_items where kind = 'offer_taken' and group_id = pg_temp.gid('G1') order by created_at limit 1), 'bobby''s comment');
call pg_temp.as_user('b'); select report_content('comment', (select id from comments where body = 'my comment'), 'spam');

\echo 'integrity:'
select * from check_ledger_integrity(); select * from check_betting_integrity(); select * from check_season_integrity();
