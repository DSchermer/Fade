-- Migration 0015 tests: the feed shows which group an item belongs to, how its offer stands, the market kind and a comment preview.
\set ON_ERROR_STOP on
\set open_nba_game `cat fixtures/open_nba_game.json`
begin;

create procedure pg_temp.as_user(p_user text) language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', ('00000000-0000-0000-0000-0000000000' || p_user || '1'), true); end $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select ('00000000-0000-0000-0000-0000000000' || p || '1')::uuid $$;

insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n from (values ('a','alice'),('b','bobby'),('c','carol')) v(u, n);
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb);
create temp table ids (name text primary key, id uuid);
grant all on ids to public;
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');
create function pg_temp.gid(p text) returns uuid language sql as $$ select id from ids where name = p $$;
create function pg_temp.mkt(p text) returns text language sql as $$
  select id from markets where case p when 'ml' then market_type = 'moneyline' when 'sp' then market_type = 'spreads' else market_type = 'totals' end order by id limit 1 $$;

-- alice and bobby share "Alpha"; alice and carol share "Beta" (so alice has two groups, bobby/carol one each)
call pg_temp.as_user('a');
insert into ids values ('Alpha', create_group('Alpha', 10000, 'unlimited', null, 10000));
insert into ids values ('Beta',  create_group('Beta',  10000, 'unlimited', null, 10000));
do $$ declare ca text := (select invite_code from groups where id = pg_temp.gid('Alpha')); cb text := (select invite_code from groups where id = pg_temp.gid('Beta')); begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('b')::text, true); perform join_group(ca);
  perform set_config('request.jwt.claim.sub', pg_temp.u('c')::text, true); perform join_group(cb);
end $$;

-- ═════════ 1. Offer items: group name, offer state, market kind, game start ═════════
call pg_temp.as_user('a');
select post_offer(pg_temp.gid('Alpha'), pg_temp.mkt('sp'), 0, 60, 40);
select post_offer(pg_temp.gid('Beta'),  pg_temp.mkt('ml'), 1, 55, 10);
do $$ declare f feed_listing; begin
  select * into f from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha');
  assert f.group_name = 'Alpha', 'the item names its group';
  assert f.offer_status = 'open' and f.offer_shares_open = 40, 'a fresh offer is open with all its shares';
  assert f.market_type = 'spreads' and f.game_start is not null, 'and says what kind of market, and when the game starts';
  assert f.ref_type = 'offer' and f.ref_id is not null and f.latest_comment is null, 'no comment yet';
  select * into f from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Beta');
  assert f.group_name = 'Beta' and f.market_type = 'moneyline', 'the other group''s item names the other group';
  assert (select count(distinct group_name) from feed_listing) = 2, 'alice''s one feed spans both groups';
end $$;

-- ═════════ 2. The offer state follows the offer ═════════
call pg_temp.as_user('b');
select take_offer((select ref_id from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha')), 15);
do $$ declare f feed_listing; begin
  select * into f from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha');
  assert f.offer_status = 'open' and f.offer_shares_open = 25, '15 taken → 25 left';
  select * into f from feed_listing where kind = 'offer_taken' and group_id = pg_temp.gid('Alpha');
  assert f.market_type = 'spreads' and f.game_start is not null and f.offer_status is null and f.bet_status = 'pending', 'a "taken" item knows its market through the bet';
end $$;
call pg_temp.as_user('a');
select cancel_offer((select ref_id from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha')));
do $$ declare f feed_listing; begin
  select * into f from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha');
  assert f.offer_shares_open = 0 and f.offer_status <> 'open', 'after cancelling the rest, nothing is open any more';
end $$;

-- ═════════ 3. Latest comment preview ═════════
call pg_temp.as_user('b');
select add_comment((select id from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha')), 'first one');
select add_comment((select id from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha')), 'second one');
-- (inside one test transaction both comments get the same clock time, so make the first one older, as it would be in real life)
update comments set created_at = created_at - interval '1 minute' where body = 'first one';
call pg_temp.as_user('a');
do $$ declare f feed_listing; begin
  select * into f from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha');
  assert f.comment_count = 2, 'two comments counted';
  assert f.latest_comment ->> 'body' = 'second one' and f.latest_comment ->> 'username' = 'bobby', 'the preview is the newest comment and its author';
end $$;
-- a block hides the blocked person's comment from the preview too
select block_user(pg_temp.u('b'));
do $$ declare f feed_listing; begin
  select * into f from feed_listing where kind = 'offer_posted' and group_id = pg_temp.gid('Alpha');
  assert f.id is not null, 'alice''s own offer item is still there';
  assert f.comment_count = 0 and f.latest_comment is null, 'but bobby''s comments are gone from the count and the preview';
end $$;
rollback;
