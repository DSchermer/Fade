-- Milestone 4 tests: Polymarket ingest, the finality rule, sync + refresh jobs.
-- Uses REAL Polymarket responses saved in tests/fixtures/ (captured 2026-10-08).
\set ON_ERROR_STOP on
\set open_nba_game  `cat fixtures/open_nba_game.json`
\set open_nfl       `cat fixtures/open_nfl_spreads.json`
\set open_nhl_ml    `cat fixtures/open_nhl_moneyline.json`
\set open_mlb_tot   `cat fixtures/open_mlb_totals.json`
\set res_win        `cat fixtures/resolved_win.json`
\set res_void       `cat fixtures/resolved_void_5050.json`
\set res_dispute    `cat fixtures/resolved_after_dispute.json`
\set proposed_soccer `cat fixtures/proposed_not_final.json`
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

create temp table fx (name text primary key, payload jsonb);
insert into fx values
  ('nba_game', :'open_nba_game'::jsonb), ('nfl', :'open_nfl'::jsonb), ('nhl_ml', :'open_nhl_ml'::jsonb),
  ('mlb_tot', :'open_mlb_tot'::jsonb), ('win', :'res_win'::jsonb), ('void', :'res_void'::jsonb),
  ('dispute', :'res_dispute'::jsonb), ('soccer', :'proposed_soccer'::jsonb);

-- ───────── 1. The finality rule: only closed + 'resolved' + terminal prices settles ─────────
do $$ begin
  assert market_resolution(true, 'resolved', '{1,0}')     = 'outcome_0', 'first outcome wins';
  assert market_resolution(true, 'resolved', '{0,1}')     = 'outcome_1', 'second outcome wins';
  assert market_resolution(true, 'resolved', '{0.5,0.5}') = 'void',      '50/50 is a void';
  assert market_resolution(true, 'resolved', '{1.0,0.0}') = 'outcome_0', 'numeric 1.0 equals 1';
  -- never final:
  assert market_resolution(false, 'resolved', '{1,0}')    = 'pending', 'not closed';
  assert market_resolution(null,  'resolved', '{1,0}')    = 'pending', 'closed unknown';
  assert market_resolution(true,  'proposed', '{1,0}')    = 'pending', 'proposed is not final';
  assert market_resolution(true,  'disputed', '{1,0}')    = 'pending', 'disputed is not final';
  assert market_resolution(true,  null,       '{1,0}')    = 'pending', 'closed with no resolution data';
  assert market_resolution(true,  'Resolved', '{1,0}')    = 'pending', 'status must match exactly';
  assert market_resolution(true,  'settled',  '{1,0}')    = 'pending', 'unknown status words are not final';
  assert market_resolution(true,  'resolved', '{0.7,0.3}') = 'pending', 'non-terminal prices';
  assert market_resolution(true,  'resolved', '{1,1}')    = 'pending', 'both-win is nonsense';
  assert market_resolution(true,  'resolved', '{0,0}')    = 'pending', 'both-lose is nonsense';
  assert market_resolution(true,  'resolved', '{1}')      = 'pending', 'wrong length';
  assert market_resolution(true,  'resolved', null)       = 'pending', 'missing prices';
end $$;

-- ───────── 2. Ingest a whole real game (moneyline + spreads + totals) ─────────
do $$ declare n integer; expected integer := (select jsonb_array_length(payload) from fx where name = 'nba_game'); begin
  n := ingest_markets('nba', (select payload from fx where name = 'nba_game'), '2026-10-08 12:00+00');
  assert n = expected and n = 11, 'all 11 markets of the game stored, got ' || n;
  assert (select count(*) from markets where league = 'nba') = 11, 'rows stored';
  assert (select count(distinct event_id) from markets) = 1, 'one game';
  assert (select count(*) from markets where market_type = 'moneyline') = 1, 'one moneyline';
end $$;
do $$ declare m markets; begin
  select * into m from markets where market_type = 'moneyline';
  assert m.question = 'Celtics vs. Cavaliers', 'moneyline question';
  assert m.outcomes = array['Celtics', 'Cavaliers'], 'two outcomes parsed from JSON-in-a-string';
  assert m.line is null, 'moneyline has no line';
  assert m.game_start = '2026-10-08 23:00+00', 'start time parsed';
  assert m.event_title = 'Celtics vs. Cavaliers', 'game title from the event';
  assert m.resolution = 'pending' and not m.closed and m.accepting, 'open, pending';
  assert market_phase(m, '2026-10-08 12:00+00') = 'upcoming', 'upcoming before start';
  assert market_phase(m, '2026-10-08 23:00:01+00') = 'started', 'started after start';
  assert array_length(m.outcome_prices, 1) = 2, 'prices kept for ordering';
  select * into m from markets where question = 'Spread: Cavaliers (-1.5)';
  assert m.line = -1.5 and m.market_type = 'spreads' and m.outcomes[1] = 'Cavaliers', 'spread line parsed';
  select * into m from markets where question like '%O/U 220.5';
  assert m.line = 220.5 and m.market_type = 'totals' and m.outcomes = array['Over', 'Under'], 'total line parsed';
end $$;

-- Re-ingesting changes nothing (idempotent), and other leagues load too.
do $$ begin
  assert ingest_markets('nba', (select payload from fx where name = 'nba_game'), '2026-10-08 12:30+00') = 11, 'second run still 11';
  assert (select count(*) from markets) = 11, 'no duplicates';
  assert ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-10-08 12:00+00') = 12, 'nfl spreads';
  assert ingest_markets('nhl', (select payload from fx where name = 'nhl_ml'), '2026-10-08 12:00+00') = 3, 'nhl moneylines';
  assert ingest_markets('mlb', (select payload from fx where name = 'mlb_tot'), '2026-10-08 12:00+00') = 3, 'mlb totals';
  assert (select count(*) from markets) = 29, 'all stored';
  assert (select count(*) from markets where league = 'nfl' and market_type = 'spreads') = 12, 'nfl spread lines (alternate lines included)';
end $$;
call pg_temp.expect_error($q$ select ingest_markets('cricket', '[]', now()) $q$, '%unknown_league%');

-- ───────── 3. Time windows for NEW markets ─────────
delete from markets where league in ('nfl', 'nhl', 'mlb');
do $$ begin
  assert ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-09-01 00:00+00') = 0, 'game > 7 days away is ignored';
  assert ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-10-30 00:00+00') = 0, 'old finished game is ignored';
  assert not exists (select 1 from markets where league = 'nfl'), 'nothing stored';
end $$;

-- ───────── 4. Garbage in → skipped, never crashes the batch ─────────
delete from sync_log;
do $$
declare e0 jsonb := (select payload -> 0 from fx where name = 'nhl_ml'); good jsonb; n integer;
begin
  good := jsonb_set(e0, '{id}', '"good1"');
  n := ingest_markets('nhl', jsonb_build_array(
         jsonb_set(e0, '{id}', '"bad-outcomes"') || jsonb_build_object('outcomes', '["a","b","c"]'),
         jsonb_set(e0, '{id}', 'null'),
         jsonb_set(e0, '{id}', '"bad-type"')     || jsonb_build_object('sportsMarketType', 'first_half_totals'),
         jsonb_set(e0, '{id}', '"bad-prices"')   || jsonb_build_object('outcomePrices', '["x","y"]'),
         jsonb_set(e0, '{id}', '"bad-start"')    || jsonb_build_object('gameStartTime', 'not a date'),
         jsonb_set(e0, '{id}', '"no-start"')     || jsonb_build_object('gameStartTime', null),
         good),
       '2026-10-08 12:00+00');
  assert n = 1, 'only the good market is stored, got ' || n;
  assert (select count(*) from markets where league = 'nhl') = 1 and exists (select 1 from markets where id = 'good1'), 'good one present';
  assert (select count(*) from sync_log where kind = 'ingest_skip') = 2, 'bad numbers/dates are logged';
  assert ingest_markets('nhl', '{"not":"an array"}', now()) = 0, 'object payload ignored';
  assert ingest_markets('nhl', null, now()) = 0, 'null payload ignored';
  assert ingest_markets('nhl', (select payload from fx where name = 'soccer'), now()) = 0, 'non-league market (no sportsMarketType) ignored';
end $$;
delete from markets where league = 'nhl';

-- ───────── 5. Real finished games ─────────
do $$ declare m markets; begin
  perform ingest_markets('nba', (select payload from fx where name = 'win'), '2026-10-08 06:00+00');
  select * into m from markets where id = '5167474';
  assert m.resolution = 'outcome_0' and m.outcomes[1] = 'Bucks' and m.closed and m.uma_status = 'resolved', 'Bucks won';
  assert m.resolved_at = '2026-10-08 06:00+00', 'resolved_at recorded';
  assert market_phase(m, '2026-10-08 06:00+00') = 'settled', 'phase settled';

  perform ingest_markets('mlb', (select payload from fx where name = 'void'), '2026-10-08 06:00+00');
  select * into m from markets where id = '5279716';
  assert m.resolution = 'void' and m.outcome_prices = array[0.5, 0.5], 'real 50/50 market is a void';
  assert market_phase(m, '2026-10-08 06:00+00') = 'void', 'phase void';

  perform ingest_markets('mlb', (select payload from fx where name = 'dispute'), '2026-10-08 06:00+00');
  select * into m from markets where id = '5361542';
  assert m.resolution = 'outcome_1' and m.outcomes[2] = 'Under', 'real market that was disputed, then resolved: Under';
  assert m.uma_history like '%disputed%', 'dispute history kept';
end $$;
delete from markets;

-- ───────── 6. Lifecycle of one market: open → proposed → disputed → resolved → never reverts ─────────
delete from sync_log; delete from uma_status_seen;
do $$
declare
  e0 jsonb := (select payload -> 0 from fx where name = 'nhl_ml');
  now1 timestamptz := '2026-10-08 12:00+00';
  m markets; mid text := e0 ->> 'id';
begin
  perform ingest_markets('nhl', jsonb_build_array(e0), now1);
  select * into m from markets where markets.id = mid;
  assert m.resolution = 'pending' and market_phase(m, now1) = 'upcoming', 'starts upcoming';

  perform ingest_markets('nhl', jsonb_build_array(e0 || '{"closed":true,"umaResolutionStatus":"proposed","outcomePrices":"[\"1\", \"0\"]"}'), now1);
  select * into m from markets where markets.id = mid;
  assert m.resolution = 'pending' and market_phase(m, now1) = 'proposed', 'proposed is not final';

  perform ingest_markets('nhl', jsonb_build_array(e0 || '{"closed":true,"umaResolutionStatus":"disputed","outcomePrices":"[\"1\", \"0\"]"}'), now1);
  select * into m from markets where markets.id = mid;
  assert m.resolution = 'pending' and market_phase(m, now1) = 'disputed', 'disputed is not final';
  assert exists (select 1 from uma_status_seen where status = 'disputed'), 'new status word recorded';

  perform ingest_markets('nhl', jsonb_build_array(e0 || '{"closed":true,"umaResolutionStatus":"resolved","outcomePrices":"[\"1\", \"0\"]"}'), now1 + interval '1 day');
  select * into m from markets where markets.id = mid;
  assert m.resolution = 'outcome_0' and market_phase(m, now1) = 'settled', 'resolved → settled';
  assert m.resolved_at = now1 + interval '1 day', 'resolved_at is when we first saw it final';

  -- a later contradicting message cannot change a final result; it is logged
  perform ingest_markets('nhl', jsonb_build_array(e0 || '{"closed":true,"umaResolutionStatus":"resolved","outcomePrices":"[\"0\", \"1\"]"}'), now1 + interval '2 days');
  select * into m from markets where markets.id = mid;
  assert m.resolution = 'outcome_0' and m.resolved_at = now1 + interval '1 day', 'result kept';
  assert (select count(*) from sync_log where kind = 'resolution_conflict') = 1, 'conflict logged for the owner';

  -- even an "open again" message cannot un-settle it
  perform ingest_markets('nhl', jsonb_build_array(e0), now1 + interval '3 days');
  select * into m from markets where markets.id = mid;
  assert m.resolution = 'outcome_0', 'settled stays settled';
end $$;

-- start time moves are picked up; an open market becomes "started" once its time passes
do $$
declare e0 jsonb := (select payload -> 1 from fx where name = 'nhl_ml'); m markets;
begin
  perform ingest_markets('nhl', jsonb_build_array(e0), '2026-10-08 12:00+00');
  perform ingest_markets('nhl', jsonb_build_array(e0 || '{"gameStartTime":"2026-10-09 02:00:00+00"}'), '2026-10-08 13:00+00');
  select * into m from markets where id = e0 ->> 'id';
  assert m.game_start = '2026-10-09 02:00+00', 'postponed start time stored';
  assert market_phase(m, '2026-10-08 23:30+00') = 'upcoming', 'still upcoming at the old start time';
  assert market_phase(m, '2026-10-09 02:00:01+00') = 'started', 'started after the new time';
end $$;
delete from markets;

-- ───────── 7. sync_markets with a stubbed network ─────────
create temp table fx_calls (url text);
grant all on fx_calls to public;
create or replace function public.fetch_json(p_url text) returns jsonb language plpgsql as $$
declare e jsonb; ty text;
begin
  insert into fx_calls values (p_url);
  if p_url like '%tag_id=100381%' then raise exception 'http_status_503'; end if;          -- MLB is "down"
  ty := substring(p_url from 'sports_market_types=([a-z]+)');
  if p_url like '%tag_id=745%' and p_url like '%offset=0%' then
    return coalesce((select jsonb_agg(x) from jsonb_array_elements((select payload from fx where name = 'nba_game')) x
                      where x ->> 'sportsMarketType' = ty), '[]');
  end if;
  if p_url like '%tag_id=899%' and ty = 'moneyline' then
    e := (select payload -> 0 from fx where name = 'nhl_ml');
    if p_url like '%offset=0%' then      -- a full page of 100 → the sync must ask for the next page
      return (select jsonb_agg(jsonb_set(e, '{id}', to_jsonb('syn-' || lpad(i::text, 3, '0')))) from generate_series(1, 100) i);
    elsif p_url like '%offset=100%' then -- a short page → the sync must stop
      return (select jsonb_agg(jsonb_set(e, '{id}', to_jsonb('syn-' || lpad(i::text, 3, '0')))) from generate_series(101, 102) i);
    end if;
  end if;
  return '[]';
end $$;

delete from sync_log;
insert into sync_log (at, kind, ok, detail) values ('2026-09-01 00:00+00', 'discover', true, 'old row');
do $$ declare total integer; begin
  total := sync_markets('2026-10-08 12:00+00');
  assert total = 113, '11 nba + 102 nhl, got ' || total;
  -- (the 3 failed MLB calls are not counted: the stub's own log row is rolled back along with its error)
  assert (select count(*) from fx_calls) = 10, 'nba 3 + nfl 3 + nhl 4 (2 pages of moneyline + spreads + totals) = 10, got ' || (select count(*) from fx_calls);
  assert (select count(*) from markets where league = 'nhl') = 102, 'pagination collected both pages';
  assert (select count(*) from markets where league = 'nba') = 11, 'nba stored';
  assert exists (select 1 from fx_calls where url like '%closed=false%tag_id=745%end_date_max=2026-10-16T12:00:00Z'), 'asks only for open markets, up to 8 days out';
  assert exists (select 1 from fx_calls where url like '%tag_id=450%sports_market_types=spreads%'), 'nfl spreads requested';
  assert (select count(*) from sync_log where kind = 'discover' and not ok and detail like 'mlb/%http_status_503%') = 3, 'MLB failures logged, others unaffected';
  assert (select count(*) from sync_log where kind = 'discover' and ok) = 1, 'summary row written';
  assert not exists (select 1 from sync_log where detail = 'old row'), 'old log rows pruned';
end $$;

-- ───────── 8. refresh_markets with a stubbed network ─────────
delete from markets; delete from sync_log; delete from fx_calls;
select ingest_markets('nba', (select payload from fx where name = 'nba_game'), '2026-10-08 12:00+00');
select ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-10-08 12:00+00');
update markets set last_synced_at = '2026-10-08 12:00+00';
update markets set tracked = true where id = (select id from markets where league = 'nfl' order by id limit 1);

create or replace function public.fetch_json(p_url text) returns jsonb language plpgsql as $$
declare mid text := substring(p_url from '/markets/([0-9]+)$'); e jsonb;
begin
  insert into fx_calls values (p_url);
  e := (select x from (select jsonb_array_elements(payload) x from fx where name in ('nba_game', 'nfl')) s where x ->> 'id' = mid limit 1);
  if mid = (select (payload -> 1) ->> 'id' from fx where name = 'nba_game') then
    return e || '{"gameStartTime":"2026-10-08 23:30:00+00"}'::jsonb;                    -- game moved 30 min later
  elsif mid = (select (payload -> 2) ->> 'id' from fx where name = 'nba_game') then
    return e || '{"closed":true,"umaResolutionStatus":"resolved","outcomePrices":"[\"1\", \"0\"]"}'::jsonb;  -- finished
  elsif mid = (select (payload -> 3) ->> 'id' from fx where name = 'nba_game') then
    raise exception 'http_status_404';
  end if;
  return e;
end $$;

-- Before any game is near its start (and with nothing tracked) nothing is refreshed:
update markets set tracked = false;
do $$ begin assert refresh_markets('2026-10-08 12:00+00') = 0, 'nothing to refresh yet'; end $$;
update markets set tracked = true where id = (select id from markets where league = 'nfl' order by id limit 1);
delete from fx_calls; update markets set last_synced_at = '2026-10-08 12:00+00';
do $$ declare n integer; a text; b text; c text; begin
  a := (select (payload -> 1) ->> 'id' from fx where name = 'nba_game');
  b := (select (payload -> 2) ->> 'id' from fx where name = 'nba_game');
  c := (select (payload -> 3) ->> 'id' from fx where name = 'nba_game');
  n := refresh_markets('2026-10-08 22:00+00');
  -- 11 nba markets near start + 1 tracked nfl = 12 attempts; the failed one's call row is rolled back with its error
  assert (select count(*) from fx_calls) = 11, '12 attempts, 1 failed (unrecorded), got ' || (select count(*) from fx_calls);
  assert n = 11, 'one of the 12 failed, got ' || n;
  assert (select game_start from markets where id = a) = '2026-10-08 23:30+00', 'moved start time picked up';
  assert (select resolution from markets where id = b) = 'outcome_0', 'finished market resolved by refresh';
  assert (select last_synced_at from markets where id = c) = '2026-10-08 22:00+00', 'failed market goes to the back of the queue';
  assert (select count(*) from sync_log where kind = 'refresh' and not ok and detail like c || ': http_status_404') = 1, 'failure logged';
  assert (select count(*) from fx_calls where url like '%/markets/' || b) = 1, 'resolved market fetched once';
  -- once final it is no longer refreshed
  delete from fx_calls;
  perform refresh_markets('2026-10-08 22:00+00');
  assert not exists (select 1 from fx_calls where url like '%/markets/' || b), 'settled markets are not refreshed again';
end $$;

-- ───────── 9. Who can see / do what ─────────
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$ begin
  assert (select count(*) from markets) > 0, 'signed-in users can read markets';
  assert (select count(*) from market_listing where phase is not null) > 0, 'listing view works with phase';
end $$;
call pg_temp.expect_error($q$ update markets set resolution = 'outcome_0' $q$, '%permission denied%');
call pg_temp.expect_error($q$ delete from markets $q$, '%permission denied%');
call pg_temp.expect_error($q$ insert into markets (id) values ('x') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from sync_log $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from sports_tags $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from uma_status_seen $q$, '%permission denied%');
call pg_temp.expect_error($q$ select sync_markets() $q$, '%permission denied%');
call pg_temp.expect_error($q$ select refresh_markets() $q$, '%permission denied%');
call pg_temp.expect_error($q$ select ingest_markets('nba', '[]') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select fetch_json('https://example.com') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select market_resolution(true, 'resolved', '{1,0}') $q$, '%permission denied%');
reset role;
set local role anon;
call pg_temp.expect_error($q$ select * from markets $q$, '%permission denied%');
reset role;

rollback;
