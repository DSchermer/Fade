-- Milestone 11 tests: the push-notification queue and in-app account deletion.
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

insert into auth.users (id) select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid from unnest(array['a','b','c','d','e','f']) u;
insert into profiles (id, username)
  select ('00000000-0000-0000-0000-0000000000' || u || '1')::uuid, n
    from (values ('a','alice'),('b','bobby'),('c','carol'),('d','dave'),('e','erin'),('f','frank')) v(u, n);
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
create function pg_temp.bal(p_group text, p_user text) returns bigint language sql as $$
  select available + escrow from group_members where group_id = pg_temp.gid(p_group) and user_id = pg_temp.u(p_user) $$;
create function pg_temp.queued(p_user text, p_kind text default null) returns bigint language sql as $$
  select count(*) from notification_outbox where user_id = pg_temp.u(p_user) and (p_kind is null or kind = p_kind) $$;

-- ═════════ 0. Text helpers match the app ═════════
do $$ begin
  assert american_text(60) = '-150' and american_text(40) = '+150' and american_text(50) = '+100' and american_text(99) = '-9900' and american_text(1) = '+9900'
     and american_text(55) = '-122' and american_text(33) = '+203' and american_text(51) = '-104' and american_text(62) = '-163', 'american odds text';
  assert (select bool_and(american_text(p) = case when p = 50 then '+100' when p > 50 then '-' || round(100.0 * p / (100 - p))::int else '+' || round(100.0 * (100 - p) / p)::int end) from generate_series(1, 99) p), 'all 99 prices';
  assert price_text(60) = '60¢ (-150)', 'both formats';
  assert coins_text(10000) = '100' and coins_text(3050) = '30.5' and coins_text(3025) = '30.25' and coins_text(5) = '0.05' and coins_text(101) = '1.01'
     and coins_text(0) = '0' and coins_text(-150) = '-1.5' and coins_text(-5) = '-0.05' and coins_text(123456700) = '1,234,567', 'coin text matches the app';
end $$;

-- ═════════ 1. Devices and preferences ═════════
call pg_temp.as_user('a');
call pg_temp.expect_error($q$ select register_device_token('short') $q$, '%invalid_token%');
call pg_temp.expect_error($q$ select register_device_token('zzzzzzzzzzzzzzzzzzzzzzzz') $q$, '%invalid_token%');
call pg_temp.expect_error($q$ select register_device_token(repeat('a', 64), 'staging') $q$, '%invalid_token%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select register_device_token(repeat('a', 64)) $q$, '%not_signed_in%');
-- everyone gets a phone (alice, bobby, carol, dave); erin and frank have none
do $$ declare u text; i integer := 0; begin
  foreach u in array array['a','b','c','d'] loop
    i := i + 1;
    perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true);
    perform register_device_token(repeat(i::text, 64));
  end loop;
  assert (select count(*) from device_tokens) = 4, 'four phones registered';
  perform set_config('request.jwt.claim.sub', pg_temp.u('b')::text, true);
  perform register_device_token(repeat('1', 64), 'sandbox');                                -- alice's phone now belongs to bobby
  assert (select user_id from device_tokens where token = repeat('1', 64)) = pg_temp.u('b') and (select count(*) from device_tokens) = 4, 'a token moves to whoever signs in on that phone';
  perform register_device_token(repeat('f', 64));
  perform set_config('request.jwt.claim.sub', pg_temp.u('a')::text, true);
  perform register_device_token(repeat('1', 64));                                           -- and back again
  perform unregister_device_token(repeat('f', 64));                                         -- (not hers: nothing happens)
  assert exists (select 1 from device_tokens where token = repeat('f', 64)), 'you cannot remove someone else''s phone';
  perform set_config('request.jwt.claim.sub', pg_temp.u('b')::text, true);
  perform unregister_device_token(repeat('f', 64));
  assert not exists (select 1 from device_tokens where token = repeat('f', 64)), 'but you can remove your own';
end $$;
do $$ declare p notification_prefs; begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('c')::text, true);
  p := my_notification_prefs();
  assert p.new_offer and p.offer_taken and p.bet_settled and p.vote_called and p.vote_result, 'everything is on by default';
  perform set_notification_pref('new_offer', false);
  assert not (my_notification_prefs()).new_offer and (my_notification_prefs()).offer_taken, 'turn one off';
  perform set_notification_pref('new_offer', true);
  assert (my_notification_prefs()).new_offer, 'and back on';
end $$;
call pg_temp.expect_error($q$ select set_notification_pref('everything', false) $q$, '%invalid_pref%');
call pg_temp.expect_error($q$ select set_notification_pref('new_offer', null) $q$, '%invalid_pref%');

-- ═════════ 2. What gets queued, for whom ═════════
-- Group: alice (owner), bobby, carol, dave, erin (no phone)
call pg_temp.as_user('a');
insert into ids values ('G', create_group('Push Crew', 10000, 'unlimited', null, 10000));
do $$ declare code text := (select invite_code from groups where id = pg_temp.gid('G')); u text; begin
  foreach u in array array['b','c','d','e'] loop perform set_config('request.jwt.claim.sub', pg_temp.u(u)::text, true); perform join_group(code); end loop;
end $$;
delete from notification_outbox;
-- (carol turns off "new offers"; dave mutes alice; erin has no phone)
call pg_temp.as_user('c'); select set_notification_pref('new_offer', false);
call pg_temp.as_user('d'); select mute_user(pg_temp.u('a'));

call pg_temp.as_user('a'); select post_offer(pg_temp.gid('G'), pg_temp.mkt('ml'), 0, 60, 100);
do $$ declare r record; begin
  assert pg_temp.queued('b', 'new_offer') = 1, 'bobby is told about the new offer';
  assert pg_temp.queued('a') = 0, 'the poster is not told about their own offer';
  assert pg_temp.queued('c') = 0, 'carol turned that kind off';
  assert pg_temp.queued('d') = 0, 'dave muted alice';
  assert pg_temp.queued('e') = 0, 'erin has no phone';
  select * into r from notification_outbox where user_id = pg_temp.u('b');
  assert r.title = 'New offer in Push Crew' and r.body = '@alice is backing Celtics to win at 60¢ (-150) — 100 shares', 'the message text: ' || r.body;
  assert (r.data ->> 'group_id')::uuid = pg_temp.gid('G'), 'carries the group so the app can open it';
end $$;
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('a')), 50);
do $$ declare r record; begin
  assert pg_temp.queued('a', 'offer_taken') = 1 and pg_temp.queued('b', 'offer_taken') = 0, 'only the maker is told their offer was taken';
  select * into r from notification_outbox where user_id = pg_temp.u('a') and kind = 'offer_taken';
  assert r.title = 'Your offer was taken' and r.body = '@bobby took 50 shares, backing Cavaliers to win at 40¢ (+150) · Push Crew', 'taken text: ' || r.body;
end $$;
call pg_temp.as_user('c'); select take_offer((select id from offers where maker_id = pg_temp.u('a')), 50);
delete from notification_outbox;
select pg_temp.finish(pg_temp.mkt('ml'), '["1", "0"]');                                  -- alice's side wins both bets
do $$ declare ra record; rb record; begin
  assert pg_temp.queued('a', 'bet_settled') = 2 and pg_temp.queued('b', 'bet_settled') = 1 and pg_temp.queued('c', 'bet_settled') = 1, 'both sides of each bet are told';
  select * into ra from notification_outbox where user_id = pg_temp.u('a') order by id limit 1;
  assert ra.title = 'You won 20 coins', 'winner title: ' || ra.title;
  assert ra.body like 'Celtics vs. Cavaliers · new balance % coins · Push Crew', 'balance in the message: ' || ra.body;
  select * into rb from notification_outbox where user_id = pg_temp.u('b');
  assert rb.title = 'You lost 20 coins' and rb.body = 'Celtics vs. Cavaliers · new balance 80 coins · Push Crew', 'loser sees the new balance: ' || rb.body;
end $$;
-- the balance in alice's LAST message equals what she really has
do $$ begin assert (select body from notification_outbox where user_id = pg_temp.u('a') order by id desc limit 1) like '% new balance 140 coins%', 'alice finished on 140'; end $$;
-- a void
delete from notification_outbox;
call pg_temp.as_user('c'); select post_offer(pg_temp.gid('G'), pg_temp.mkt('sp'), 0, 50, 4);
call pg_temp.as_user('b'); select take_offer((select id from offers where maker_id = pg_temp.u('c') and market_id = pg_temp.mkt('sp')), 4);
delete from notification_outbox;
select pg_temp.finish(pg_temp.mkt('sp'), '["0.5", "0.5"]');
do $$ begin assert (select title from notification_outbox where user_id = pg_temp.u('b') and kind = 'bet_settled') = 'Bet voided — stakes refunded', 'void message'; end $$;
-- votes
delete from notification_outbox;
call pg_temp.as_user('b'); select call_vote(pg_temp.gid('G'), 'reset');
do $$ declare r record; begin
  assert pg_temp.queued('b') = 0 and pg_temp.queued('a', 'vote_called') = 1 and pg_temp.queued('c', 'vote_called') = 1 and pg_temp.queued('d', 'vote_called') = 1, 'everyone else is told a vote was called';
  select * into r from notification_outbox where user_id = pg_temp.u('a');
  assert r.title = 'Reset vote in Push Crew' and r.body like '@bobby called a vote to reset the group.%', 'vote text';
end $$;
call pg_temp.as_user('a'); select cast_vote((select id from votes where group_id = pg_temp.gid('G') and status = 'open'), true);
call pg_temp.as_user('c'); select cast_vote((select id from votes where group_id = pg_temp.gid('G') and status = 'open'), true);
do $$ begin
  assert (select status from votes where group_id = pg_temp.gid('G')) = 'passed', 'the reset passed (3 of 5)';
  assert pg_temp.queued('a', 'vote_result') = 1 and pg_temp.queued('b', 'vote_result') = 1 and pg_temp.queued('d', 'vote_result') = 1 and pg_temp.queued('e') = 0, 'result sent to every member with a phone';
  assert (select title from notification_outbox where user_id = pg_temp.u('a') and kind = 'vote_result') = 'Reset vote passed', 'result title';
end $$;
-- blocking: carol blocks bobby → she isn't told about bobby's activity
delete from notification_outbox;
call pg_temp.as_user('c'); select block_user(pg_temp.u('b')); select set_notification_pref('new_offer', true);
call pg_temp.as_user('b'); select post_offer(pg_temp.gid('G'), pg_temp.mkt('tot'), 0, 50, 2);
do $$ begin assert pg_temp.queued('c') = 0 and pg_temp.queued('a', 'new_offer') = 1, 'a blocker is not notified of the blocked person''s offers'; end $$;
-- banned users receive nothing
delete from notification_outbox;
select mod_ban_user(pg_temp.u('d'));
call pg_temp.as_user('b'); select post_offer(pg_temp.gid('G'), pg_temp.mkt('tot', 1), 0, 50, 2);
do $$ begin assert pg_temp.queued('d') = 0, 'a banned account is not messaged'; end $$;
select mod_unban_user(pg_temp.u('d'));

-- ═════════ 3. Delivery (what the send-push function calls) ═════════
delete from notification_outbox; delete from device_tokens where user_id = pg_temp.u('b');
call pg_temp.as_user('b'); select register_device_token(repeat('b', 64)); select register_device_token(repeat('c', 64), 'sandbox');   -- bobby has two phones
call pg_temp.as_user('a'); select post_offer(pg_temp.gid('G'), pg_temp.mkt('tot', 2), 0, 50, 2);
do $$ declare n integer; begin
  select count(*) into n from claim_notifications(10);
  assert n = 3, 'alice''s offer: bobby on 2 phones + carol on 1 -> 3 deliveries, got ' || n;      -- (dave is unmuted? he muted alice; erin has no phone)
  assert (select count(*) from claim_notifications(10)) = 0, 'a claimed message is not handed out again straight away';
  assert (select attempts from notification_outbox limit 1) = 1, 'attempts counted';
  update notification_outbox set claimed_at = now() - interval '5 minutes';
  assert (select count(*) from claim_notifications(10)) = 3, 'a claim that was never finished is retried after 2 minutes';
  perform finish_notification((select id from notification_outbox where user_id = pg_temp.u('b')), true);
  assert (select sent_at from notification_outbox where user_id = pg_temp.u('b')) is not null, 'marked sent';
  perform finish_notification((select id from notification_outbox where user_id = pg_temp.u('c')), false, 'BadDeviceToken', array[repeat('3', 64)]);
  assert (select last_error from notification_outbox where user_id = pg_temp.u('c')) = 'BadDeviceToken' and not exists (select 1 from device_tokens where token = repeat('3', 64)), 'failure recorded and the dead phone forgotten';
  update notification_outbox set claimed_at = now() - interval '5 minutes', attempts = 5 where user_id = pg_temp.u('c');
  assert (select count(*) from claim_notifications(10)) = 0, 'gives up after 5 attempts';
  update notification_outbox set sent_at = now() - interval '8 days';
  perform claim_notifications(1);
  assert (select count(*) from notification_outbox where sent_at is not null) = 0, 'old sent messages are cleaned up';
end $$;
set local role authenticated;
call pg_temp.as_user('b');
call pg_temp.expect_error($q$ select * from claim_notifications(5) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select finish_notification(1, true) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from notification_outbox $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from device_tokens $q$, '%permission denied%');
call pg_temp.expect_error($q$ select enqueue_notification(gen_random_uuid(), 'new_offer', 'x', 'y', '{}') $q$, '%permission denied%');
do $$ begin assert (select count(*) from notification_prefs) = 1, 'you can only see your own preferences'; end $$;
reset role;
set local role anon;
call pg_temp.expect_error($q$ select register_device_token(repeat('a', 64)) $q$, '%permission denied%');
call pg_temp.expect_error($q$ select my_notification_prefs() $q$, '%permission denied%');
reset role;
do $$ begin assert pg_temp.healthy(), 'notifications never touch the money books'; end $$;
rollback;
