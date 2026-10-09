-- In-app account deletion: everything about the person goes, every group's books still balance.
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

insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c','d','e']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n
    from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave'),('e','erin')) v(u, n);
create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb);
create temp table ids (name text primary key, id uuid, code text);
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
create function pg_temp.bal(p_group text, p_user text) returns bigint language sql as $$
  select available + escrow from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_user) $$;

-- ═════════ A busy life: three groups, bets, friends, comments, a phone ═════════
call pg_temp.as_user('a');
insert into ids (name, id) values ('D1', create_group('Main Crew', 10000, 'unlimited', null, 10000)), ('D2', create_group('Just Me', 10000, 'unlimited', null, 10000));
call pg_temp.as_user('e');
insert into ids (name, id) values ('D3', create_group('Erin Crew', 10000, 'unlimited', null, 10000));
update ids set code = (select invite_code from groups g where g.id = ids.id);
do $$ declare code1 text := (select code from ids where name = 'D1'); code3 text := (select code from ids where name = 'D3'); u text; begin
  foreach u in array array['b','c','d'] loop perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true); perform join_group(code1); end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.u('a')::text, true); perform join_group(code3);                  -- alice is an ordinary member of Erin's group
end $$;

-- (1) a settled win over dave: alice +10 coins  (2) a pending bet with bobby (alice maker)  (3) a pending bet with carol (alice taker)  (4) an open offer
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('D1'), pg_temp.mkt('ml'), 0, 50, 20);
call pg_temp.as_user('d'); select take_offer((select id from offers where maker_id = pg_temp.u('a') and market_id = pg_temp.mkt('ml')), 20);
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('D1'), pg_temp.mkt('sp'), 0, 40, 10);
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('a') and market_id = pg_temp.mkt('sp')), 6);
call pg_temp.as_user('c'); select post_offer(pg_temp.gid('D1'), pg_temp.mkt('tot'), 1, 30, 10);
call pg_temp.as_user('a'); select take_offer((select id from offers where maker_id = pg_temp.u('c') and market_id = pg_temp.mkt('tot')), 10);
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('D3'), pg_temp.mkt('tot', 1), 0, 50, 4);                          -- an open offer in Erin's group
-- social life
call pg_temp.as_user('a');
select send_friend_request('bobby'); select send_friend_request('carol');
call pg_temp.as_user('b'); select respond_friend_request(pg_temp.u('a'), true);
call pg_temp.as_user('a');
select block_user(pg_temp.u('d')); select mute_user(pg_temp.u('c'));
select register_device_token(repeat('a', 64)); select set_notification_pref('new_offer', false);
select toggle_reaction((select id from feed_items where kind = 'offer_taken' limit 1), '🔥');
select add_comment((select id from feed_items where kind = 'offer_taken' limit 1), 'my comment');
call pg_temp.as_user('b'); select add_comment((select id from feed_items where kind = 'offer_taken' limit 1), 'bobby''s comment');
call pg_temp.as_user('c'); select call_vote(pg_temp.gid('D1'), 'reset');
call pg_temp.as_user('a'); select cast_vote((select id from votes where group_id = pg_temp.gid('D1') and status = 'open'), false);
call pg_temp.as_user('b'); select report_content('comment', (select id from comments where body = 'my comment'), 'spam');
call pg_temp.as_user('a'); select report_content('user', pg_temp.u('d'), 'harassment');

create temp table before as
  select (select count(*) from feed_items where payload::text like '%"alice"%') as feed_mentions,
         (select available + escrow from group_members where group_id = pg_temp.gid('D1') and user_id = pg_temp.u('b')) as bobby_before,
         (select available + escrow from group_members where group_id = pg_temp.gid('D1') and user_id = pg_temp.u('c')) as carol_before,
         (select lifetime_wins || '-' || lifetime_losses from profiles where id = pg_temp.u('b')) as bobby_record,
         (select lifetime_wins || '-' || lifetime_losses from profiles where id = pg_temp.u('d')) as dave_record,
         (select count(*) from notification_outbox) as outbox;
do $$ begin
  assert (select feed_mentions from before) > 0, 'alice appears in feed text before deletion';
  assert (select count(*) from bets where status = 'pending') = 2 and (select count(*) from offers where status = 'open') = 2, 'two pending bets and two open offers (4 shares left in Main Crew, 4 in Erin''s group)';
  assert pg_temp.healthy(), 'healthy before';
end $$;

-- ═════════ Delete ═════════
call pg_temp.as_user('a');
select delete_my_account();

do $$ declare p profiles; begin
  select * into p from profiles where id = pg_temp.u('a');
  assert p.username is null and p.display_name = 'Deleted user' and p.deleted_at is not null and p.price_format = 'cents', 'profile anonymised';
  assert not exists (select 1 from auth.users where id = pg_temp.u('a')), 'the sign-in account is gone';
  assert p.lifetime_closed_profit = (select coalesce(sum(realized_profit), 0) from group_members where user_id = pg_temp.u('a')), 'her (anonymous) score matches what she realised on the way out';
  -- groups
  assert not exists (select 1 from group_members where user_id = pg_temp.u('a') and status = 'active'), 'out of every group';
  assert (select count(*) from group_members where user_id = pg_temp.u('a') and status = 'left' and available = 0 and escrow = 0 and granted = 0 and buyback_coins = 0) = 3, 'three clean exits';
  assert not exists (select 1 from offers where maker_id = pg_temp.u('a') and status = 'open'), 'no open offers of hers remain';
  assert not exists (select 1 from bets where status = 'pending' and (maker_id = pg_temp.u('a') or taker_id = pg_temp.u('a'))), 'no unsettled bets of hers remain';
  assert (select count(*) from bets where status = 'void') = 2, 'both unsettled bets were voided';
  -- the people on the other side lose nothing
  assert (select lifetime_wins || '-' || lifetime_losses from profiles where id = pg_temp.u('b')) = (select bobby_record from before), 'voided bets leave bobby''s record alone';
  assert (select lifetime_wins || '-' || lifetime_losses from profiles where id = pg_temp.u('d')) = (select dave_record from before), 'and dave''s';
  -- ownership went to the member who had been there longest
  assert (select role from group_members where group_id = pg_temp.gid('D1') and user_id = pg_temp.u('b')) = 'owner', 'bobby inherited Main Crew';
  assert (select count(*) from group_members where group_id = pg_temp.gid('D1') and role = 'owner' and status = 'active') = 1, 'exactly one owner';
  -- everything personal is gone
  assert not exists (select 1 from device_tokens where user_id = pg_temp.u('a')) and not exists (select 1 from notification_prefs where user_id = pg_temp.u('a'))
     and not exists (select 1 from notification_outbox where user_id = pg_temp.u('a')), 'phone, preferences and queued messages gone';
  assert not exists (select 1 from friendships where requester = pg_temp.u('a') or addressee = pg_temp.u('a')), 'friendships and requests gone';
  assert not exists (select 1 from blocks where blocker = pg_temp.u('a') or blocked = pg_temp.u('a')) and not exists (select 1 from mutes where muter = pg_temp.u('a') or muted = pg_temp.u('a')), 'blocks and mutes gone';
  assert not exists (select 1 from reactions where user_id = pg_temp.u('a')) and not exists (select 1 from comments where user_id = pg_temp.u('a')), 'reactions and comments gone';
  assert exists (select 1 from comments where body = 'bobby''s comment'), 'other people''s comments stay';
  assert not exists (select 1 from vote_ballots where user_id = pg_temp.u('a')), 'her open-vote ballot is gone';
  assert (select count(*) from feed_items where payload::text like '%"alice"%') = 0, 'her name is gone from saved feed text';
  assert (select count(*) from feed_items where payload::text like '%"deleted user"%') > 0, 'replaced by "deleted user"';
  assert pg_temp.healthy(), 'every group still balances after the deletion';
end $$;
-- her business was refunded exactly: bobby (taker of 6 shares @ 60¢) and carol (maker, 10 shares @ 30¢) are made whole
do $$ begin
  assert (select count(*) from ledger where kind = 'bet_void' and bucket = 'available') = 4, 'two voided bets × two refunds';
  assert pg_temp.bal('D1', 'b') = 10000 and pg_temp.bal('D1', 'c') = 10000, 'bobby and carol are back to exactly 100 coins';
end $$;
-- the name is free again, and she can't be found
call pg_temp.as_user('e');
do $$ begin
  assert not exists (select 1 from friend_suggestions() where username = 'alice') and not exists (select 1 from friend_scores() where username = 'alice'), 'no longer listed anywhere';
  assert not exists (select 1 from group_leaderboard where username = 'alice' and group_id = pg_temp.gid('D3')), 'off the leaderboards';
end $$;
call pg_temp.expect_error($q$ select send_friend_request('alice') $q$, '%user_not_found%');
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000f1');
insert into profiles (id) values ('00000000-0000-0000-0000-0000000000f1');
call pg_temp.as_user('f'); select set_username('alice');
do $$ begin assert (select username from profiles where id = pg_temp.u('f')) = 'alice', 'a new person can take the username'; end $$;
-- the empty group's invite code is dead
call pg_temp.as_user('e');
call pg_temp.expect_error($q$ select join_group((select code from ids where name = 'D2')) $q$, '%group_not_found%');
-- deleting twice, and deleting while signed out
call pg_temp.as_user('a');
call pg_temp.expect_error($q$ select delete_my_account() $q$, '%not_signed_in%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select delete_my_account() $q$, '%not_signed_in%');
-- a brand-new account with nothing in it can be deleted too
call pg_temp.as_user('f'); select delete_my_account();
do $$ begin assert (select deleted_at from profiles where id = pg_temp.u('f')) is not null, 'empty accounts delete cleanly'; end $$;
-- permissions
set local role anon;
call pg_temp.expect_error($q$ select delete_my_account() $q$, '%permission denied%');
reset role;
do $$ begin assert pg_temp.healthy(), 'healthy at the end'; end $$;
rollback;
