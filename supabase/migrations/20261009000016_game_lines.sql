-- Migration 0016 (UI redesign, Games tab): one row per upcoming game with the three "main" markets the Games list shows:
-- the moneyline, the spread whose line is closest to 50/50, and the total whose line is closest to 50/50.
-- (Polymarket lists dozens of alternate lines per game; sending all of them to the phone just to pick one would be slow.
-- Polymarket's prices are used ONLY to pick which line to show first. They never set anyone's odds.)
-- The best open offer prices are worked out on the phone from the group's open offers, so this function is the same for everyone.
create function public.game_lines(p_league text default null)
returns table (
  event_id    text,
  event_title text,
  league      text,
  game_start  timestamptz,
  ml_market   text,
  ml_outcomes text[],
  sp_market   text,
  sp_outcomes text[],
  sp_line     numeric,
  to_market   text,
  to_outcomes text[],
  to_line     numeric
)
language sql stable security invoker as $$
  with up as (
    select m.* from public.markets m
     where public.market_phase(m) = 'upcoming' and (p_league is null or m.league = p_league)
  ),
  ml as (select distinct on (u.event_id) u.* from up u where u.market_type = 'moneyline' order by u.event_id, u.id),
  sp as (select distinct on (u.event_id) u.* from up u where u.market_type = 'spreads'
          order by u.event_id, abs(coalesce(u.outcome_prices[1], 1.5) - 0.5), u.line, u.id),
  tt as (select distinct on (u.event_id) u.* from up u where u.market_type = 'totals'
          order by u.event_id, abs(coalesce(u.outcome_prices[1], 1.5) - 0.5), u.line, u.id)
  select ml.event_id, ml.event_title, ml.league, ml.game_start,
         ml.id, ml.outcomes,
         sp.id, sp.outcomes, sp.line,
         tt.id, tt.outcomes, tt.line
    from ml
    left join sp on sp.event_id = ml.event_id
    left join tt on tt.event_id = ml.event_id
   order by ml.game_start, ml.event_id
   limit 300;
$$;
revoke all on function public.game_lines(text) from public, anon;
grant execute on function public.game_lines(text) to authenticated;
