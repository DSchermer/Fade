-- Migration 0016 tests: game_lines() gives one row per upcoming game with its moneyline and the 50/50-closest spread and total.
\set ON_ERROR_STOP on
\set open_nba_game `cat fixtures/open_nba_game.json`
\set open_nfl `cat fixtures/open_nfl_spreads.json`
\set open_nhl_ml `cat fixtures/open_nhl_moneyline.json`
begin;

create temp table fx (name text primary key, payload jsonb);
insert into fx values ('nba', :'open_nba_game'::jsonb), ('nfl', :'open_nfl'::jsonb), ('nhl', :'open_nhl_ml'::jsonb);
select ingest_markets('nba', (select payload from fx where name = 'nba'), '2026-10-08 12:00+00');
select ingest_markets('nfl', (select payload from fx where name = 'nfl'), '2026-10-08 12:00+00');
select ingest_markets('nhl', (select payload from fx where name = 'nhl'), '2026-10-08 12:00+00');
insert into clock_override (at) values ('2026-10-08 12:00+00');

-- 1. one row per game that has a moneyline
do $$ declare n_games integer; n_rows integer; begin
  select count(distinct event_id) into n_games from markets where market_type = 'moneyline' and market_phase(markets) = 'upcoming';
  select count(*) into n_rows from game_lines();
  assert n_rows = n_games and n_rows >= 2, format('one row per game with a moneyline: % rows, % games', n_rows, n_games);
  assert (select count(*) from game_lines()) = (select count(distinct event_id) from game_lines()), 'no game twice';
  assert not exists (select 1 from game_lines() where ml_market is null), 'every row has its moneyline';
end $$;

-- 2. the NBA game: the chosen spread and total are the ones closest to 50/50
do $$ declare g record; best numeric; chosen numeric; begin
  select * into g from game_lines('nba') limit 1;
  assert g.league = 'nba' and g.ml_market is not null, 'an NBA game comes back';
  assert (select market_type from markets where id = g.ml_market) = 'moneyline', 'ml_market is a moneyline';

  if g.sp_market is not null then
    assert (select market_type from markets where id = g.sp_market) = 'spreads', 'sp_market is a spread';
    select min(abs(coalesce(outcome_prices[1], 1.5) - 0.5)) into best from markets where event_id = g.event_id and market_type = 'spreads';
    select abs(coalesce(outcome_prices[1], 1.5) - 0.5) into chosen from markets where id = g.sp_market;
    assert chosen = best, 'the spread shown first is the one closest to 50/50';
    assert g.sp_line = (select line from markets where id = g.sp_market) and g.sp_outcomes = (select outcomes from markets where id = g.sp_market), 'its line and outcomes come with it';
  end if;
  if g.to_market is not null then
    assert (select market_type from markets where id = g.to_market) = 'totals', 'to_market is a total';
    select min(abs(coalesce(outcome_prices[1], 1.5) - 0.5)) into best from markets where event_id = g.event_id and market_type = 'totals';
    select abs(coalesce(outcome_prices[1], 1.5) - 0.5) into chosen from markets where id = g.to_market;
    assert chosen = best, 'the total shown first is the one closest to 50/50';
  end if;
  assert g.sp_market is not null and g.to_market is not null, 'the NBA fixture has both a spread and a total';
end $$;

-- 3. the league filter
do $$ begin
  assert not exists (select 1 from game_lines('nba') where league <> 'nba'), 'only NBA games';
  assert not exists (select 1 from game_lines('mlb')), 'no MLB games loaded, none returned';
end $$;

-- 4. games that have started are gone
update clock_override set at = '2099-01-01 00:00+00';
do $$ begin assert (select count(*) from game_lines()) = 0, 'after the start nothing is listed'; end $$;
rollback;
