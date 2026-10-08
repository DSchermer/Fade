-- Fade — Milestone 4: mirror Polymarket sports markets.
-- Design: all logic lives in SQL so it can be tested against saved real Polymarket JSON.
--   fetch_json()      the only function that touches the network (uses the `http` extension)
--   ingest_markets()  validates + stores markets from one API response
--   sync_markets()    scheduled every 15 min: discover upcoming NFL/NBA/MLB/NHL moneyline/spread/total markets
--   refresh_markets() scheduled every 5 min: re-check markets near/after start (start-time moves, resolution)
-- Polymarket prices are stored ONLY to pick which line to show first on screen. They never set odds.

create table public.sports_tags (
  league text primary key check (league in ('nfl', 'nba', 'mlb', 'nhl')),
  tag_id integer not null
);
insert into public.sports_tags (league, tag_id) values ('nba', 745), ('nfl', 450), ('mlb', 100381), ('nhl', 899);

create table public.markets (
  id             text primary key,                     -- Polymarket market id
  condition_id   text,
  league         text not null references public.sports_tags (league),
  market_type    text not null check (market_type in ('moneyline', 'spreads', 'totals')),
  question       text not null,
  outcomes       text[] not null check (array_length(outcomes, 1) = 2),
  line           numeric,                              -- spread / total line, null for moneyline
  game_start     timestamptz not null,
  event_id       text not null,                        -- the game these markets belong to
  event_title    text not null,
  event_slug     text,
  accepting      boolean not null default false,       -- Polymarket "acceptingOrders"
  closed         boolean not null default false,
  uma_status     text,                                 -- Polymarket "umaResolutionStatus"
  uma_history    text,                                 -- raw "umaResolutionStatuses" (audit trail)
  outcome_prices numeric[],                            -- latest Polymarket prices; display ordering only
  resolution     text not null default 'pending'
                   check (resolution in ('pending', 'outcome_0', 'outcome_1', 'void')),
  resolved_at    timestamptz,
  tracked        boolean not null default false,       -- set when an offer/bet references it (Milestone 5)
  first_seen_at  timestamptz not null default now(),
  last_synced_at timestamptz not null default now()
);
create index markets_browse_idx on public.markets (league, game_start) where resolution = 'pending';
create index markets_event_idx on public.markets (event_id);

create table public.sync_log (
  id     bigint generated always as identity primary key,
  at     timestamptz not null default now(),
  kind   text not null,
  ok     boolean not null,
  detail text
);
-- Every distinct umaResolutionStatus Polymarket sends us, so surprises are visible.
create table public.uma_status_seen (
  status            text primary key,
  first_seen_at     timestamptz not null default now(),
  example_market_id text
);

alter table public.sports_tags     enable row level security;
alter table public.markets         enable row level security;
alter table public.sync_log        enable row level security;
alter table public.uma_status_seen enable row level security;
create policy markets_read on public.markets for select to authenticated using (true);   -- public data
grant select on public.markets to authenticated;
-- sports_tags, sync_log, uma_status_seen: RLS on, no policy, no grant → clients cannot see them.

-- ───────────────────────── The finality rule ─────────────────────────
-- Settle ONLY when: closed AND status is exactly 'resolved' AND prices are terminal.
-- Everything else (proposed, disputed, unknown, missing data, odd prices) stays pending.
create function public.market_resolution(p_closed boolean, p_uma text, p_prices numeric[])
returns text language sql immutable as $$
  select case
    when p_closed is not true                       then 'pending'
    when p_uma is distinct from 'resolved'          then 'pending'
    when p_prices is null or cardinality(p_prices) <> 2 then 'pending'
    when p_prices[1] = 1   and p_prices[2] = 0      then 'outcome_0'
    when p_prices[1] = 0   and p_prices[2] = 1      then 'outcome_1'
    when p_prices[1] = 0.5 and p_prices[2] = 0.5    then 'void'      -- 50/50 = no action, refund both sides
    else 'pending'
  end;
$$;

-- What to tell the user: upcoming | started | proposed | disputed | settled | void
create function public.market_phase(m public.markets, p_now timestamptz default now())
returns text language sql stable as $$
  select case
    when m.resolution = 'void'                              then 'void'
    when m.resolution in ('outcome_0', 'outcome_1')         then 'settled'
    when not m.closed and m.accepting and p_now < m.game_start then 'upcoming'
    when m.uma_status = 'proposed'                          then 'proposed'
    when m.uma_status is not null and m.uma_status <> 'resolved' then 'disputed'
    else 'started'
  end;
$$;

create view public.market_listing with (security_invoker = true) as
  select m.*, public.market_phase(m) as phase from public.markets m;
grant select on public.market_listing to authenticated;
grant execute on function public.market_phase(public.markets, timestamptz) to authenticated;

-- ───────────────────────── Parsing helpers ─────────────────────────
create function public.try_jsonb(p_text text) returns jsonb
language plpgsql immutable as $$
begin
  return p_text::jsonb;
exception when others then
  return null;
end $$;

-- Polymarket sends arrays like "outcomes" as JSON *inside* a JSON string. Accept either form.
create function public.json_array_field(p_obj jsonb, p_key text) returns jsonb
language sql immutable as $$
  select case when jsonb_typeof(p_obj -> p_key) = 'array' then p_obj -> p_key
              else public.try_jsonb(p_obj ->> p_key) end;
$$;

-- ───────────────────────── Ingest ─────────────────────────
create function public.ingest_markets(p_league text, p_payload jsonb, p_now timestamptz default now())
returns integer
language plpgsql security definer set search_path = public as $$
declare
  e jsonb;
  n integer := 0;
  v_id text; v_type text;
  v_outcomes jsonb; v_prices_json jsonb; v_prices numeric[];
  v_start timestamptz;
  v_ev jsonb; v_event_id text; v_event_title text; v_event_slug text;
  v_uma text; v_closed boolean; v_accepting boolean; v_line numeric; v_res text;
  v_old public.markets%rowtype; v_has_old boolean;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'array' then
    return 0;
  end if;
  if not exists (select 1 from public.sports_tags where league = p_league) then
    raise exception 'unknown_league';
  end if;

  for e in select * from jsonb_array_elements(p_payload) loop
    begin
      v_id   := e ->> 'id';
      v_type := e ->> 'sportsMarketType';
      continue when v_id is null or v_type is null or v_type not in ('moneyline', 'spreads', 'totals');

      v_outcomes := public.json_array_field(e, 'outcomes');
      continue when v_outcomes is null or jsonb_typeof(v_outcomes) <> 'array' or jsonb_array_length(v_outcomes) <> 2;

      v_prices_json := public.json_array_field(e, 'outcomePrices');
      continue when v_prices_json is null or jsonb_typeof(v_prices_json) <> 'array' or jsonb_array_length(v_prices_json) <> 2;
      v_prices := array(select (x #>> '{}')::numeric from jsonb_array_elements(v_prices_json) x);

      v_start := (e ->> 'gameStartTime')::timestamptz;
      continue when v_start is null;

      select * into v_old from public.markets where id = v_id;
      v_has_old := found;

      v_ev          := e -> 'events' -> 0;
      v_event_id    := coalesce(v_ev ->> 'id', v_old.event_id);
      v_event_title := coalesce(v_ev ->> 'title', v_old.event_title);
      v_event_slug  := coalesce(v_ev ->> 'slug', v_old.event_slug);
      continue when v_event_id is null or v_event_title is null;

      -- New markets only when the game is upcoming (within 7 days) or only just started.
      if not v_has_old and (v_start < p_now - interval '12 hours' or v_start > p_now + interval '7 days') then
        continue;
      end if;

      v_line      := nullif(e ->> 'line', '')::numeric;
      v_closed    := coalesce((e ->> 'closed')::boolean, false);
      v_accepting := coalesce((e ->> 'acceptingOrders')::boolean, false);
      v_uma       := nullif(e ->> 'umaResolutionStatus', '');
      v_res       := public.market_resolution(v_closed, v_uma, v_prices);

      if v_uma is not null then
        insert into public.uma_status_seen (status, example_market_id) values (v_uma, v_id)
        on conflict (status) do nothing;
      end if;

      -- A final result is never changed by a later message; disagreement is logged for the owner.
      if v_has_old and v_old.resolution <> 'pending' and v_res <> 'pending' and v_res <> v_old.resolution then
        insert into public.sync_log (kind, ok, detail)
        values ('resolution_conflict', false, v_id || ': kept ' || v_old.resolution || ', API now says ' || v_res);
      end if;

      insert into public.markets as m (
        id, condition_id, league, market_type, question, outcomes, line, game_start,
        event_id, event_title, event_slug, accepting, closed, uma_status, uma_history,
        outcome_prices, resolution, resolved_at, last_synced_at)
      values (
        v_id, e ->> 'conditionId', p_league, v_type, coalesce(e ->> 'question', v_event_title),
        array(select jsonb_array_elements_text(v_outcomes)), v_line, v_start,
        v_event_id, v_event_title, v_event_slug, v_accepting, v_closed, v_uma, e ->> 'umaResolutionStatuses',
        v_prices, v_res, case when v_res <> 'pending' then p_now end, p_now)
      on conflict (id) do update set
        condition_id   = excluded.condition_id,
        question       = excluded.question,
        outcomes       = excluded.outcomes,
        line           = excluded.line,
        game_start     = excluded.game_start,
        event_id       = excluded.event_id,
        event_title    = excluded.event_title,
        event_slug     = excluded.event_slug,
        accepting      = excluded.accepting,
        closed         = excluded.closed,
        uma_status     = excluded.uma_status,
        uma_history    = excluded.uma_history,
        outcome_prices = excluded.outcome_prices,
        resolution     = case when m.resolution <> 'pending' then m.resolution else excluded.resolution end,
        resolved_at    = case when m.resolution <> 'pending' then m.resolved_at
                              when excluded.resolution <> 'pending' then p_now end,
        last_synced_at = excluded.last_synced_at;
      n := n + 1;
    exception when others then
      insert into public.sync_log (kind, ok, detail) values ('ingest_skip', false, coalesce(v_id, '?') || ': ' || sqlerrm);
    end;
  end loop;
  return n;
end $$;

-- ───────────────────────── Network + schedules ─────────────────────────
-- The ONLY function that talks to the internet. Needs the `http` extension (see supabase/ops).
create function public.fetch_json(p_url text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  select * into r from extensions.http((
    'GET', p_url,
    array[extensions.http_header('User-Agent', 'Fade/1.0 (play-money app; github.com/DSchermer/Fade)'),
          extensions.http_header('Accept', 'application/json')],
    null, null)::extensions.http_request);
  if r.status <> 200 then
    raise exception 'http_status_%', r.status;
  end if;
  return r.content::jsonb;
end $$;

-- Discover upcoming games. Runs every 15 minutes.
create function public.sync_markets(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path = public set statement_timeout = '180s' as $$
declare
  t record; ty text; page integer; payload jsonb; v_url text;
  total integer := 0;
  v_end text := to_char((p_now + interval '8 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
begin
  for t in select league, tag_id from public.sports_tags order by league loop
    foreach ty in array array['moneyline', 'spreads', 'totals'] loop
      for page in 0..11 loop
        v_url := format('https://gamma-api.polymarket.com/markets?closed=false&limit=100&offset=%s&tag_id=%s&sports_market_types=%s&order=endDate&ascending=true&end_date_max=%s',
                        page * 100, t.tag_id, ty, v_end);
        begin
          payload := public.fetch_json(v_url);
        exception when others then
          insert into public.sync_log (kind, ok, detail)
          values ('discover', false, t.league || '/' || ty || ' page ' || page || ': ' || sqlerrm);
          exit;
        end;
        total := total + public.ingest_markets(t.league, payload, p_now);
        exit when jsonb_typeof(payload) <> 'array' or jsonb_array_length(payload) < 100;
      end loop;
    end loop;
  end loop;
  insert into public.sync_log (kind, ok, detail) values ('discover', true, total || ' markets');
  delete from public.sync_log where at < p_now - interval '14 days';
  return total;
end $$;

-- Re-check markets that matter: near/after start, or referenced by offers/bets. Runs every 5 minutes.
create function public.refresh_markets(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path = public set statement_timeout = '180s' as $$
declare r record; payload jsonb; n integer := 0;
begin
  for r in
    select id, league from public.markets
     where resolution = 'pending'
       and (tracked or (game_start > p_now - interval '14 days' and game_start < p_now + interval '2 hours'))
     order by last_synced_at
     limit 50
  loop
    begin
      payload := public.fetch_json('https://gamma-api.polymarket.com/markets/' || r.id);
      if jsonb_typeof(payload) = 'object' then payload := jsonb_build_array(payload); end if;
      perform public.ingest_markets(r.league, payload, p_now);
      n := n + 1;
    exception when others then
      insert into public.sync_log (kind, ok, detail) values ('refresh', false, r.id || ': ' || sqlerrm);
      update public.markets set last_synced_at = p_now where id = r.id;   -- go to the back of the queue
    end;
  end loop;
  return n;
end $$;

-- Nothing here is callable by app users.
revoke all on function public.market_resolution(boolean, text, numeric[]), public.try_jsonb(text),
  public.json_array_field(jsonb, text), public.ingest_markets(text, jsonb, timestamptz),
  public.fetch_json(text), public.sync_markets(timestamptz), public.refresh_markets(timestamptz)
  from public, anon, authenticated;
