-- Milestone 9 tests: the feed, reactions, comments, the content filter, reports, moderation, blocks and mutes.
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
create function pg_temp.feed(p_kind text) returns feed_items language sql as $$
  select * from feed_items where group_id = pg_temp.gid('Feed Crew') and kind = p_kind order by created_at desc, id limit 1 $$;
create procedure pg_temp.lose_everything(p_group text, p_loser text, p_winner text) language plpgsql as $$
declare v_amt bigint; v_tx uuid := gen_random_uuid();
begin
  select available into v_amt from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_loser);
  if v_amt > 0 then
    perform ledger_post(v_tx, pg_temp.gid(p_group), pg_temp.u(p_loser),  'available', -v_amt, 'escrow_release');
    perform ledger_post(v_tx, pg_temp.gid(p_group), pg_temp.u(p_winner), 'available',  v_amt, 'escrow_release');
  end if;
end $$;

-- ═════════ 0. Side labels (used in the feed text) ═════════
do $$ declare m markets; begin
  select * into m from markets where question = 'Spread: Cavaliers (-1.5)';
  assert market_side_label(m, 0) = 'Cavaliers -1.5' and market_side_label(m, 1) = 'Celtics +1.5', 'spread labels';
  select * into m from markets where question like '%O/U 220.5';
  assert market_side_label(m, 0) = 'Over 220.5' and market_side_label(m, 1) = 'Under 220.5', 'total labels';
  select * into m from markets where market_type = 'moneyline';
  assert market_side_label(m, 0) = 'Celtics to win' and market_side_label(m, 1) = 'Cavaliers to win', 'moneyline labels';
end $$;

-- ═════════ 1. Feed items appear on their own ═════════
call pg_temp.as_user('a');
insert into ids values ('Feed Crew', create_group('Feed Crew', 10000, 'unlimited', null, 10000));
do $$ declare code text := (select invite_code from groups where id = pg_temp.gid('Feed Crew')); u text; begin
  foreach u in array array['b', 'c', 'd'] loop
    perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true); perform join_group(code);
  end loop;
end $$;
-- erin is in a different group
call pg_temp.as_user('e');
insert into ids values ('Other', create_group('Erin Place', 10000, 'unlimited', null, 10000));

call pg_temp.as_user('a');
select post_offer(pg_temp.gid('Feed Crew'), pg_temp.mkt('ml'), 0, 60, 100);
call pg_temp.as_user('b');
select take_offer((select id from offers where maker_id = pg_temp.u('a')), 50);
do $$ declare f feed_items; begin
  f := pg_temp.feed('offer_posted');
  assert f.actor_id = pg_temp.u('a') and f.payload ->> 'maker' = 'alice' and f.payload ->> 'side' = 'Celtics to win'
     and (f.payload ->> 'price_cents')::int = 60 and (f.payload ->> 'shares')::int = 100 and f.payload ->> 'event_title' = 'Celtics vs. Cavaliers', 'offer item: who, side, price, size';
  f := pg_temp.feed('offer_taken');
  assert f.actor_id = pg_temp.u('b') and f.payload ->> 'taker' = 'bobby' and f.payload ->> 'maker_side' = 'Celtics to win' and f.payload ->> 'taker_side' = 'Cavaliers to win'
     and (f.payload ->> 'maker_stake')::bigint = 3000 and (f.payload ->> 'taker_stake')::bigint = 2000 and (f.payload ->> 'shares')::int = 50, 'taken item: both sides and stakes';
end $$;
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');
do $$ declare f feed_items; begin
  f := pg_temp.feed('bet_settled');
  assert f.payload ->> 'result' = 'decided' and f.payload ->> 'winner' = 'alice' and f.payload ->> 'loser' = 'bobby' and (f.payload ->> 'gain')::bigint = 2000, 'settled item: winner, loser, gain';
end $$;
-- a void
call pg_temp.as_user('c'); select post_offer(pg_temp.gid('Feed Crew'), pg_temp.mkt('sp'), 0, 50, 4);
call pg_temp.as_user('d'); select take_offer((select id from offers where maker_id = pg_temp.u('c') and market_id = pg_temp.mkt('sp')), 4);
select pg_temp.finish(pg_temp.mkt('sp'), '["0.5", "0.5"]');
do $$ begin assert exists (select 1 from feed_items where kind = 'bet_settled' and payload ->> 'result' = 'void' and actor_id is null), 'void item'; end $$;
-- buyback
reset role; call pg_temp.lose_everything('Feed Crew', 'c', 'a'); call pg_temp.as_user('c'); select claim_buyback(pg_temp.gid('Feed Crew'));
do $$ declare f feed_items; begin
  f := pg_temp.feed('buyback');
  assert f.payload ->> 'who' = 'carol' and (f.payload ->> 'amount')::bigint = 10000 and f.payload ->> 'via' = 'policy', 'buyback item';
end $$;
-- votes
call pg_temp.as_user('b'); select call_vote(pg_temp.gid('Feed Crew'), 'reset');
do $$ begin assert (pg_temp.feed('vote_called')).payload ->> 'vote_kind' = 'reset' and (pg_temp.feed('vote_called')).payload ->> 'caller' = 'bobby', 'vote called item'; end $$;
call pg_temp.as_user('c'); select cast_vote((select id from votes where group_id = pg_temp.gid('Feed Crew') and status = 'open'), false);
call pg_temp.as_user('d'); select cast_vote((select id from votes where group_id = pg_temp.gid('Feed Crew') and status = 'open'), false);
do $$ declare f feed_items; begin
  f := pg_temp.feed('vote_result');
  assert f.payload ->> 'status' = 'failed' and (f.payload ->> 'no')::int = 2, 'vote result item (failed 1-2 of 4)';
  assert (select count(*) from feed_items where group_id = pg_temp.gid('Feed Crew')) = 9, '9 items: 2 offers, 2 takes, 2 settlements, 1 buyback, 1 vote called, 1 vote result';
end $$;
do $$ begin assert pg_temp.healthy(), 'feed triggers do not disturb the money books'; end $$;

-- ═════════ 2. Who sees the feed ═════════
set local role authenticated;
call pg_temp.as_user('d');
do $$ declare f record; begin
  assert (select count(*) from feed_listing where group_id = pg_temp.gid('Feed Crew')) = 9, 'a member sees all 9 items';
  select * into f from feed_listing where kind = 'offer_posted' and actor_username = 'alice';
  assert f.comment_count = 0 and f.reactions = '{}'::jsonb and f.my_reactions = '{}', 'no comments or reactions yet';
end $$;
call pg_temp.as_user('e');
do $$ begin assert (select count(*) from feed_listing where group_id = pg_temp.gid('Feed Crew')) = 0 and (select count(*) from feed_items) = 0, 'an outsider sees none of it'; end $$;
reset role;

-- ═════════ 3. Reactions ═════════
create temp table item as select id from feed_items where kind = 'offer_posted' and actor_id = pg_temp.u('a');
grant all on item to public;
call pg_temp.as_user('b');
do $$ begin
  assert toggle_reaction((select id from item), '🔥') = true, 'added';
  assert toggle_reaction((select id from item), '🔥') = false, 'tap again removes it';
  assert toggle_reaction((select id from item), '🔥') = true and toggle_reaction((select id from item), '😂') = true, 'two different emojis are fine';
end $$;
call pg_temp.as_user('c'); select toggle_reaction((select id from item), '🔥');
call pg_temp.expect_error($q$ select toggle_reaction((select id from item), '🤡') $q$, '%invalid_emoji%');
call pg_temp.expect_error($q$ select toggle_reaction((select id from item), null) $q$, '%invalid_emoji%');
call pg_temp.expect_error($q$ select toggle_reaction(gen_random_uuid(), '🔥') $q$, '%item_not_found%');
call pg_temp.as_user('e');
call pg_temp.expect_error($q$ select toggle_reaction((select id from item), '🔥') $q$, '%item_not_found%');          -- outsiders can't even tell it exists
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select toggle_reaction((select id from item), '🔥') $q$, '%not_signed_in%');
set local role authenticated;
call pg_temp.as_user('b');
do $$ declare f record; begin
  select * into f from feed_listing where id = (select id from item);
  assert (f.reactions ->> '🔥')::int = 2 and (f.reactions ->> '😂')::int = 1, 'counts per emoji';
  assert f.my_reactions @> array['😂', '🔥'] and cardinality(f.my_reactions) = 2, 'and which ones are mine';
end $$;
reset role;

-- ═════════ 4. Comments and the content filter ═════════
call pg_temp.as_user('c');
create temp table cm (name text primary key, id uuid);
grant all on cm to public;
insert into cm values ('c1', add_comment((select id from item), '  Easy money for Alice 🔥  '));
call pg_temp.as_user('d');
insert into cm values ('d1', add_comment((select id from item), 'Fading this one'));
do $$ begin
  assert (select body from comments where id = (select id from cm where name = 'c1')) = 'Easy money for Alice 🔥', 'text is trimmed, emoji kept';
end $$;
call pg_temp.expect_error($q$ select add_comment((select id from item), '') $q$, '%invalid_comment%');
call pg_temp.expect_error($q$ select add_comment((select id from item), '    ') $q$, '%invalid_comment%');
call pg_temp.expect_error($q$ select add_comment((select id from item), null) $q$, '%invalid_comment%');
call pg_temp.expect_error($q$ select add_comment((select id from item), repeat('x', 501)) $q$, '%invalid_comment%');
do $$ begin perform add_comment((select id from item), repeat('x', 500)); end $$;                                   -- exactly 500 is fine
-- the filter: blocked, including common disguises
call pg_temp.expect_error($q$ select add_comment((select id from item), 'FUCK this') $q$, '%content_not_allowed%');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'what a sh1t bet') $q$, '%content_not_allowed%');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'fuuuuuck') $q$, '%content_not_allowed%');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'you are a b!tch') $q$, '%content_not_allowed%');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'just KYS') $q$, '%content_not_allowed%');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'go   die, loser') $q$, '%content_not_allowed%') ;
call pg_temp.expect_error($q$ select add_comment((select id from item), 'I will kill you') $q$, '%content_not_allowed%');
-- ...but ordinary words that merely CONTAIN a bad string are fine
do $$ begin
  perform add_comment((select id from item), 'The classic Scunthorpe problem, Dickens, an assassin and shiitake on a bass boat');
  perform add_comment((select id from item), 'Locks of the week: Celtics -150');
end $$;
call pg_temp.as_user('e');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'hello') $q$, '%item_not_found%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select add_comment((select id from item), 'hello') $q$, '%not_signed_in%');
call pg_temp.as_user('d');
-- rate limit: 10 a minute (this run has used 4 already)
do $$ declare i integer; begin
  for i in 1..6 loop perform add_comment((select id from item), 'spam ' || i); end loop;
  begin perform add_comment((select id from item), 'one too many'); assert false, 'rate limit not enforced'; exception when others then assert sqlerrm = 'slow_down', sqlerrm; end;
end $$;
set local role authenticated;
call pg_temp.as_user('b');
do $$ begin
  assert (select count(*) from comment_listing where feed_item_id = (select id from item)) = 11, 'members read the 11 comments';
  assert (select comment_count from feed_listing where id = (select id from item)) = 11, 'and the feed counts them';
  assert (select username from comment_listing where id = (select id from cm where name = 'c1')) = 'carol', 'with the author''s name';
end $$;
call pg_temp.expect_error($q$ insert into comments (feed_item_id, group_id, user_id, body) select id, group_id, actor_id, 'x' from feed_items limit 1 $q$, '%permission denied%');
call pg_temp.expect_error($q$ update comments set body = 'edited' $q$, '%permission denied%');
reset role;
-- deleting my own comment, and only mine
call pg_temp.as_user('b');
select delete_my_comment((select id from cm where name = 'c1'));                                       -- carol's: nothing happens
do $$ begin assert exists (select 1 from comments where id = (select id from cm where name = 'c1')), 'you cannot delete someone else''s comment'; end $$;
call pg_temp.as_user('c');
select delete_my_comment((select id from cm where name = 'c1'));
do $$ begin assert not exists (select 1 from comments where id = (select id from cm where name = 'c1')), 'but you can delete your own'; end $$;

-- the same filter guards names other people see
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select set_username('fuck_you') $q$, '%content_not_allowed%');
call pg_temp.expect_error($q$ select set_username('sh1t_head') $q$, '%content_not_allowed%');
select set_username('bobby_b');
call pg_temp.expect_error($q$ select create_group('Shit Show', 10000) $q$, '%content_not_allowed%');
select create_group('Friday Fun', 10000);
select set_username('bobby');

-- ═════════ 5. Reports ═════════
create temp table rp (name text primary key, id uuid);
grant all on rp to public;
call pg_temp.as_user('b');
insert into cm values ('d2', (select id from comments where body = 'Fading this one'));
insert into rp values ('r1', report_content('comment', (select id from cm where name = 'd2'), 'harassment', 'repeated trolling'));
do $$ begin
  assert report_content('comment', (select id from cm where name = 'd2'), 'harassment') = (select id from rp where name = 'r1'), 'reporting twice returns the same report';
  assert (select count(*) from reports) = 1, 'no duplicate';
end $$;
call pg_temp.as_user('c');
select report_content('comment', (select id from cm where name = 'd2'), 'spam');                                -- a second person
select report_content('user', pg_temp.u('d'), 'harassment', 'x');
select report_content('feed_item', (select id from item), 'other');
call pg_temp.expect_error($q$ select report_content('comment', (select id from cm where name = 'd2'), 'because') $q$, '%invalid_report%');
call pg_temp.expect_error($q$ select report_content('video', (select id from cm where name = 'd2'), 'spam') $q$, '%invalid_report%');
call pg_temp.expect_error($q$ select report_content('user', pg_temp.u('c'), 'spam') $q$, '%invalid_report%');         -- not yourself
call pg_temp.as_user('d');
call pg_temp.expect_error($q$ select report_content('comment', (select id from comments where user_id = pg_temp.u('d') limit 1), 'spam') $q$, '%invalid_report%');   -- not your own comment
call pg_temp.as_user('e');
call pg_temp.expect_error($q$ select report_content('comment', (select id from cm where name = 'd2'), 'spam') $q$, '%report_target_not_found%');   -- can't see it, can't report it
call pg_temp.expect_error($q$ select report_content('user', pg_temp.u('d'), 'spam') $q$, '%report_target_not_found%');                              -- shares no group
do $$ declare r record; begin
  select * into r from open_reports where target_type = 'comment';
  assert r.times_reported = 2 and r.content = 'Fading this one' and r.author = 'dave' and r.reason in ('harassment', 'spam'), 'you (the owner) see who, what and how often';
  assert (select count(*) from open_reports) = 4, 'four open reports (2 on the comment, 1 user, 1 feed item)';
end $$;
-- the app's users cannot read or answer reports
set local role authenticated;
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select * from reports $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from open_reports $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from banned_terms $q$, '%permission denied%');
call pg_temp.expect_error($q$ select mod_ban_user(pg_temp.u('d')) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select mod_hide_comment(gen_random_uuid()) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select mod_hide_feed_item(gen_random_uuid()) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select mod_resolve_report(gen_random_uuid(), 'dismissed') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select contains_banned_term('x') $q$, '%permission denied%');
reset role;

-- ═════════ 6. Acting on reports (what you do in the dashboard) ═════════
select mod_hide_comment((select id from cm where name = 'd2'), 'trolling');
do $$ begin
  assert (select hidden from comments where id = (select id from cm where name = 'd2')) = true, 'comment hidden';
  assert (select count(*) from reports where target_type = 'comment' and status = 'actioned') = 2, 'both reports on it marked actioned';
  assert (select count(*) from open_reports) = 2, 'two still open';
end $$;
set local role authenticated; call pg_temp.as_user('b');
do $$ begin assert not exists (select 1 from comment_listing where id = (select id from cm where name = 'd2')), 'members no longer see a hidden comment'; end $$;
reset role;
-- ban dave: no new offers, takes, comments or reactions; existing bets still settle; he cannot join anything new
select mod_ban_user(pg_temp.u('d'), 'repeated harassment');
do $$ begin assert (select banned from profiles where id = pg_temp.u('d')) and (select count(*) from reports where target_type = 'user' and status = 'actioned') = 1, 'banned and the report closed'; end $$;
-- even code that skips the functions can't create activity for a banned account: the tables refuse it themselves
do $$ begin
  begin insert into comments (feed_item_id, group_id, user_id, body) select id, group_id, pg_temp.u('d'), 'sneaky' from feed_items limit 1; assert false, 'comment row accepted';
  exception when others then assert sqlerrm = 'account_disabled', sqlerrm; end;
  begin insert into reactions (feed_item_id, user_id, emoji) select id, pg_temp.u('d'), '🔥' from feed_items limit 1; assert false, 'reaction row accepted';
  exception when others then assert sqlerrm = 'account_disabled', sqlerrm; end;
  begin insert into offers (group_id, season_id, maker_id, market_id, outcome, price_cents, shares_total, shares_open)
        select group_id, season_id, pg_temp.u('d'), market_id, 0, 50, 1, 1 from offers limit 1; assert false, 'offer row accepted';
  exception when others then assert sqlerrm = 'account_disabled', sqlerrm; end;
  begin insert into bets (offer_id, group_id, season_id, market_id, maker_id, taker_id, maker_outcome, price_cents, shares, maker_stake, taker_stake)
        select id, group_id, season_id, market_id, maker_id, pg_temp.u('d'), 0, 50, 1, 50, 50 from offers where maker_id <> pg_temp.u('d') limit 1; assert false, 'bet row accepted';
  exception when others then assert sqlerrm = 'account_disabled', sqlerrm; end;
end $$;
call pg_temp.as_user('d');
call pg_temp.expect_error($q$ select post_offer(pg_temp.gid('Feed Crew'), pg_temp.mkt('tot'), 0, 50, 1) $q$, '%account_disabled%');
call pg_temp.expect_error($q$ select add_comment((select id from item), 'hello again') $q$, '%account_disabled%');
call pg_temp.expect_error($q$ select toggle_reaction((select id from item), '🔥') $q$, '%account_disabled%');
call pg_temp.as_user('a');
select post_offer(pg_temp.gid('Feed Crew'), pg_temp.mkt('tot'), 0, 50, 1);
call pg_temp.as_user('d');
call pg_temp.expect_error($q$ select take_offer((select id from offers where market_id = pg_temp.mkt('tot') and status = 'open'), 1) $q$, '%account_disabled%');
select mod_unban_user(pg_temp.u('d'));
select take_offer((select id from offers where market_id = pg_temp.mkt('tot') and status = 'open'), 1);       -- fine again
select mod_hide_feed_item((select id from item), 'test');
do $$ begin
  assert (select hidden from feed_items where id = (select id from item)) and (select count(*) from reports where target_type = 'feed_item' and status = 'actioned') = 1, 'feed item hidden, report closed';
  perform mod_resolve_report((select id from reports where target_type = 'comment' limit 1), 'dismissed', 'ok');
  assert pg_temp.healthy(), 'moderation never touches the money books';
end $$;

-- ═════════ 7. Block and mute ═════════
delete from comments where user_id = pg_temp.u('d') and body like 'spam%';     -- (clears dave from the 10-a-minute limit used above)
call pg_temp.as_user('c'); select add_comment((select id from feed_items where kind = 'offer_taken' limit 1), 'carol says hi');
call pg_temp.as_user('d'); select add_comment((select id from feed_items where kind = 'offer_taken' limit 1), 'dave says hi');
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select block_user(pg_temp.u('b')) $q$, '%invalid_target%');
call pg_temp.expect_error($q$ select block_user(gen_random_uuid()) $q$, '%invalid_target%');
call pg_temp.expect_error($q$ select mute_user(null) $q$, '%invalid_target%');
select block_user(pg_temp.u('c')); select block_user(pg_temp.u('c'));                                      -- twice is fine
select mute_user(pg_temp.u('d'));
do $$ begin
  assert (select count(*) from my_blocked_and_muted() where kind = 'blocked' and username = 'carol') = 1 and (select count(*) from my_blocked_and_muted() where kind = 'muted' and username = 'dave') = 1, 'settings list shows both';
end $$;
set local role authenticated;
do $$ declare it uuid := (select id from feed_items where kind = 'offer_taken' limit 1); begin
  assert not exists (select 1 from comment_listing where feed_item_id = it and username in ('carol', 'dave')), 'bobby sees neither the blocked nor the muted person''s comments';
  assert not exists (select 1 from feed_listing where actor_username = 'carol'), 'nor carol''s feed activity';
  assert exists (select 1 from feed_listing where actor_username = 'alice') and exists (select 1 from feed_listing where actor_username = 'bobby'), 'everyone else''s activity (and his own) is still there';
end $$;
call pg_temp.as_user('c');
do $$ declare it uuid := (select id from feed_items where kind = 'offer_taken' limit 1); begin
  assert (select count(*) from comment_listing where feed_item_id = it and username = 'carol') = 1, 'carol still sees her own';
  assert not exists (select 1 from feed_listing where actor_username = 'bobby'), 'a block hides bobby from carol too';
end $$;
call pg_temp.as_user('d');
do $$ declare it uuid := (select id from feed_items where kind = 'offer_taken' limit 1); begin
  assert exists (select 1 from feed_listing where actor_username = 'bobby'), 'a MUTE is one-way: dave still sees bobby''s activity';
end $$;
call pg_temp.as_user('b');
do $$ begin assert (select count(*) from blocks) = 1 and (select count(*) from mutes) = 1, 'you only ever see your own blocks and mutes'; end $$;
reset role;
call pg_temp.as_user('b');
select unblock_user(pg_temp.u('c')); select unmute_user(pg_temp.u('d'));
set local role authenticated;
do $$ begin assert exists (select 1 from comment_listing where username = 'carol') and exists (select 1 from comment_listing where username = 'dave'), 'unblock and unmute bring everything back'; end $$;
reset role;

-- ═════════ 8. Permissions ═════════
set local role anon;
call pg_temp.expect_error($q$ select toggle_reaction(gen_random_uuid(), '🔥') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select add_comment(gen_random_uuid(), 'x') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select report_content('user', gen_random_uuid(), 'spam') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select block_user(gen_random_uuid()) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from feed_listing $q$, '%permission denied%');
reset role;
do $$ begin assert pg_temp.healthy(), 'healthy at the end'; end $$;
rollback;
