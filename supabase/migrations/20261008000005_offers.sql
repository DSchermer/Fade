-- Fade — Milestone 5: offers and takes (maker/taker, share-based).
-- Money rules (all amounts are hundredths of a coin; 1 share pays 100):
--   maker backs outcome X at price p (cents, 1..99) for N shares  → escrows N × p
--   a taker takes n shares of the other side                      → escrows n × (100 − p)
--   the two stakes always add up to exactly n × 100: no rounding, no coins created or destroyed.
-- Every coin movement goes through public.ledger_post() inside these functions.
-- Lock order is always: offer row → one member row. Only ONE member row is changed per call,
-- so two people acting at once can never deadlock.

-- A clock the tests can set. Empty in production; clients cannot read or write it.
create table public.clock_override (
  id int primary key default 1 check (id = 1),
  at timestamptz not null
);
alter table public.clock_override enable row level security;
create function public.app_now() returns timestamptz
language sql stable security definer set search_path = public as $$
  select coalesce((select at from public.clock_override), now());
$$;

create table public.offers (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null references public.groups (id),
  season_id       uuid not null references public.seasons (id),
  maker_id        uuid not null references public.profiles (id),
  market_id       text not null references public.markets (id),
  outcome         smallint not null check (outcome in (0, 1)),     -- the side the maker backs
  price_cents     smallint not null check (price_cents between 1 and 99),
  shares_total    integer not null check (shares_total > 0),
  shares_open     integer not null check (shares_open >= 0),
  shares_cancelled integer not null default 0 check (shares_cancelled >= 0),
  status          text not null default 'open' check (status in ('open', 'filled', 'cancelled')),
  cancel_reason   text check (cancel_reason in ('maker', 'started', 'market_closed', 'reset')),
  created_at      timestamptz not null default now(),
  check (shares_open + shares_cancelled <= shares_total)
);
create index offers_open_idx   on public.offers (group_id, market_id) where status = 'open';
create index offers_maker_idx  on public.offers (maker_id);
create index offers_market_idx on public.offers (market_id) where status = 'open';

create table public.bets (
  id            uuid primary key default gen_random_uuid(),
  offer_id      uuid not null references public.offers (id),
  group_id      uuid not null references public.groups (id),
  season_id     uuid not null references public.seasons (id),
  market_id     text not null references public.markets (id),
  maker_id      uuid not null references public.profiles (id),
  taker_id      uuid not null references public.profiles (id),
  maker_outcome smallint not null check (maker_outcome in (0, 1)),
  price_cents   smallint not null check (price_cents between 1 and 99),
  shares        integer not null check (shares > 0),
  maker_stake   bigint not null,
  taker_stake   bigint not null,
  status        text not null default 'pending' check (status in ('pending', 'won_maker', 'won_taker', 'void')),
  settled_at    timestamptz,
  created_at    timestamptz not null default now(),
  check (maker_id <> taker_id),                                       -- never on your own offer
  check (maker_stake = shares::bigint * price_cents),
  check (taker_stake = shares::bigint * (100 - price_cents)),         -- so stakes sum to exactly shares × 100
  check ((status = 'pending') = (settled_at is null))
);
create index bets_group_idx   on public.bets (group_id);
create index bets_maker_idx   on public.bets (maker_id);
create index bets_taker_idx   on public.bets (taker_id);
create index bets_pending_idx on public.bets (market_id) where status = 'pending';
create index bets_offer_idx   on public.bets (offer_id);

alter table public.offers enable row level security;
alter table public.bets   enable row level security;
create policy offers_select on public.offers for select to authenticated using (public.is_group_member(group_id));
create policy bets_select   on public.bets   for select to authenticated using (public.is_group_member(group_id));
grant select on public.offers, public.bets to authenticated;

-- Readable lists for the app (RLS of the underlying tables still applies).
create view public.offer_listing with (security_invoker = true) as
  select o.id, o.group_id, o.maker_id, p.username as maker_username, o.market_id, o.outcome, o.price_cents,
         o.shares_total, o.shares_open, o.shares_cancelled, o.status, o.cancel_reason, o.created_at,
         m.question, m.outcomes, m.market_type, m.line, m.game_start, m.event_id, m.event_title, m.league
    from public.offers o
    join public.markets m on m.id = o.market_id
    join public.profiles p on p.id = o.maker_id;

create view public.bet_listing with (security_invoker = true) as
  select b.id, b.offer_id, b.group_id, b.market_id, b.maker_id, mp.username as maker_username,
         b.taker_id, tp.username as taker_username, b.maker_outcome, b.price_cents, b.shares,
         b.maker_stake, b.taker_stake, b.status, b.created_at, b.settled_at,
         m.question, m.outcomes, m.market_type, m.line, m.game_start, m.event_title, m.league,
         public.market_phase(m) as phase
    from public.bets b
    join public.markets m on m.id = b.market_id
    join public.profiles mp on mp.id = b.maker_id
    join public.profiles tp on tp.id = b.taker_id;
grant select on public.offer_listing, public.bet_listing to authenticated;

-- From now on "now" for phases comes from app_now() (identical to now() in production; the tests can set it).
create or replace function public.market_phase(m public.markets, p_now timestamptz default public.app_now())
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

-- Can anyone still bet on this market right now?
create function public.market_is_open(m public.markets) returns boolean
language sql stable as $$
  select not m.closed and m.accepting and m.resolution = 'pending' and public.app_now() < m.game_start;
$$;

-- ───────────────────────── post ─────────────────────────
create function public.post_offer(p_group uuid, p_market text, p_outcome integer, p_price integer, p_shares integer)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  gm     public.group_members%rowtype;
  g      public.groups%rowtype;
  mk     public.markets%rowtype;
  v_cost bigint;
  v_offer uuid;
  v_tx   uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_outcome is null or p_outcome not in (0, 1)        then raise exception 'invalid_outcome'; end if;
  if p_price   is null or p_price not between 1 and 99   then raise exception 'invalid_price'; end if;
  if p_shares  is null or p_shares not between 1 and 100000000 then raise exception 'invalid_shares'; end if;

  select * into gm from public.group_members
   where group_id = p_group and user_id = v_uid and status = 'active' for update;
  if not found then raise exception 'not_a_member'; end if;
  select * into g from public.groups where id = p_group;

  select * into mk from public.markets where id = p_market;
  if not found then raise exception 'market_not_found'; end if;
  if not public.market_is_open(mk) then raise exception 'market_not_open'; end if;

  v_cost := p_shares::bigint * p_price;
  if gm.available < v_cost then raise exception 'insufficient_balance'; end if;

  insert into public.offers (group_id, season_id, maker_id, market_id, outcome, price_cents, shares_total, shares_open)
  values (p_group, g.current_season_id, v_uid, p_market, p_outcome, p_price, p_shares, p_shares)
  returning id into v_offer;

  perform public.ledger_post(v_tx, p_group, v_uid, 'available', -v_cost, 'escrow_lock', 'offer', v_offer);
  perform public.ledger_post(v_tx, p_group, v_uid, 'escrow',     v_cost, 'escrow_lock', 'offer', v_offer);

  update public.markets set tracked = true where id = p_market and not tracked;
  return v_offer;
end $$;

-- ───────────────────────── take ─────────────────────────
create function public.take_offer(p_offer uuid, p_shares integer) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid := auth.uid();
  o      public.offers%rowtype;
  gm     public.group_members%rowtype;
  mk     public.markets%rowtype;
  v_cost bigint;
  v_bet  uuid;
  v_tx   uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;

  select * into o from public.offers where id = p_offer for update;      -- serialises everyone taking this offer
  if not found then raise exception 'offer_not_found'; end if;

  select * into gm from public.group_members
   where group_id = o.group_id and user_id = v_uid and status = 'active' for update;
  if not found then raise exception 'offer_not_found'; end if;           -- outsiders learn nothing

  if o.maker_id = v_uid then raise exception 'cannot_take_own_offer'; end if;
  if p_shares is null or p_shares < 1 then raise exception 'invalid_shares'; end if;
  if o.status <> 'open' or o.shares_open = 0 then raise exception 'offer_not_open'; end if;
  if p_shares > o.shares_open then raise exception 'not_enough_shares'; end if;

  select * into mk from public.markets where id = o.market_id;
  if not public.market_is_open(mk) then raise exception 'market_not_open'; end if;

  v_cost := p_shares::bigint * (100 - o.price_cents);
  if gm.available < v_cost then raise exception 'insufficient_balance'; end if;

  insert into public.bets (offer_id, group_id, season_id, market_id, maker_id, taker_id,
                           maker_outcome, price_cents, shares, maker_stake, taker_stake)
  values (o.id, o.group_id, o.season_id, o.market_id, o.maker_id, v_uid,
          o.outcome, o.price_cents, p_shares,
          p_shares::bigint * o.price_cents, v_cost)
  returning id into v_bet;

  update public.offers
     set shares_open = shares_open - p_shares,
         status = case when shares_open - p_shares = 0 then 'filled' else 'open' end
   where id = o.id;

  -- The maker's stake is already in escrow from posting; only the taker's coins move now.
  perform public.ledger_post(v_tx, o.group_id, v_uid, 'available', -v_cost, 'escrow_lock', 'bet', v_bet);
  perform public.ledger_post(v_tx, o.group_id, v_uid, 'escrow',     v_cost, 'escrow_lock', 'bet', v_bet);
  return v_bet;
end $$;

-- ───────────────────────── cancel ─────────────────────────
-- Refunds the UNFILLED shares only; shares already taken stand.
create function public.cancel_offer(p_offer uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  o        public.offers%rowtype;
  mk       public.markets%rowtype;
  v_refund bigint;
  v_tx     uuid := gen_random_uuid();
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;

  select * into o from public.offers where id = p_offer for update;
  if not found then raise exception 'offer_not_found'; end if;
  if not exists (select 1 from public.group_members
                  where group_id = o.group_id and user_id = v_uid and status = 'active') then
    raise exception 'offer_not_found';
  end if;
  if o.maker_id <> v_uid then raise exception 'not_offer_maker'; end if;
  if o.status <> 'open' or o.shares_open = 0 then raise exception 'offer_not_open'; end if;

  select * into mk from public.markets where id = o.market_id;
  if public.app_now() >= mk.game_start then raise exception 'market_started'; end if;

  perform 1 from public.group_members where group_id = o.group_id and user_id = v_uid for update;
  v_refund := o.shares_open::bigint * o.price_cents;
  perform public.ledger_post(v_tx, o.group_id, v_uid, 'escrow',    -v_refund, 'escrow_release', 'offer', o.id);
  perform public.ledger_post(v_tx, o.group_id, v_uid, 'available',  v_refund, 'escrow_release', 'offer', o.id);

  update public.offers
     set shares_cancelled = shares_cancelled + shares_open, shares_open = 0,
         status = 'cancelled', cancel_reason = 'maker'
   where id = o.id;
  return v_refund;
end $$;

-- ───────────────────────── automatic cancel at event start ─────────────────────────
-- Scheduled every minute. Cancels unfilled shares once the game has started (no live betting),
-- or if the market closed/resolved early (e.g. a postponement). Safe to run repeatedly.
create function public.auto_cancel_started() returns integer
language plpgsql security definer set search_path = public as $$
declare
  o        record;
  v_refund bigint;
  v_tx     uuid;
  n        integer := 0;
begin
  for o in
    select ofr.id, ofr.group_id, ofr.maker_id, ofr.shares_open, ofr.price_cents,
           (public.app_now() >= m.game_start) as started
      from public.offers ofr
      join public.markets m on m.id = ofr.market_id
     where ofr.status = 'open' and ofr.shares_open > 0
       and (public.app_now() >= m.game_start or m.closed or m.resolution <> 'pending')
     order by ofr.created_at
       for update of ofr skip locked
  loop
    v_tx := gen_random_uuid();
    perform 1 from public.group_members where group_id = o.group_id and user_id = o.maker_id for update;
    v_refund := o.shares_open::bigint * o.price_cents;
    perform public.ledger_post(v_tx, o.group_id, o.maker_id, 'escrow',    -v_refund, 'escrow_release', 'offer', o.id);
    perform public.ledger_post(v_tx, o.group_id, o.maker_id, 'available',  v_refund, 'escrow_release', 'offer', o.id);
    update public.offers
       set shares_cancelled = shares_cancelled + shares_open, shares_open = 0,
           status = 'cancelled', cancel_reason = case when o.started then 'started' else 'market_closed' end
     where id = o.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ───────────────────────── integrity checks for betting ─────────────────────────
-- Zero rows = healthy. Run together with check_ledger_integrity().
create function public.check_betting_integrity()
returns table (check_name text, group_id uuid, detail text)
language sql stable as $$
  -- every share of every offer is open, cancelled, or taken — none lost or invented
  select 'offer_shares_mismatch'::text, o.group_id, 'offer ' || o.id
    from public.offers o
    left join (select offer_id, sum(shares) as s from public.bets group by offer_id) b on b.offer_id = o.id
   where o.shares_open + o.shares_cancelled + coalesce(b.s, 0) <> o.shares_total
  union all
  select 'offer_status_mismatch', o.group_id, 'offer ' || o.id
    from public.offers o
   where (o.status = 'open') <> (o.shares_open > 0)
      or (o.status = 'filled' and o.shares_cancelled > 0)
      or (o.status = 'cancelled' and o.shares_cancelled = 0)
  union all
  -- the two stakes of every bet add up to exactly the pot
  select 'bet_pot_mismatch', b.group_id, 'bet ' || b.id
    from public.bets b where b.maker_stake + b.taker_stake <> b.shares::bigint * 100
  union all
  -- coins in escrow = cost of open offers + stakes of unsettled bets, for every member
  select 'escrow_mismatch', m.group_id,
         'user ' || m.user_id || ' escrow ' || m.escrow || ' vs expected ' || coalesce(e.expected, 0)
    from public.group_members m
    left join (
      select x.group_id, x.uid, sum(x.amt) as expected
        from (select group_id, maker_id as uid, shares_open::bigint * price_cents as amt from public.offers where status = 'open'
              union all select group_id, maker_id, maker_stake from public.bets where status = 'pending'
              union all select group_id, taker_id, taker_stake from public.bets where status = 'pending') x
       group by x.group_id, x.uid) e
      on e.group_id = m.group_id and e.uid = m.user_id
   where m.escrow <> coalesce(e.expected, 0);
$$;

-- Clients may post / take / cancel and read the clock-free helpers; nothing else.
revoke all on function public.post_offer(uuid, text, integer, integer, integer),
  public.take_offer(uuid, integer), public.cancel_offer(uuid), public.auto_cancel_started(),
  public.check_betting_integrity(), public.app_now(), public.market_is_open(public.markets)
  from public, anon, authenticated;
grant execute on function public.post_offer(uuid, text, integer, integer, integer),
  public.take_offer(uuid, integer), public.cancel_offer(uuid) to authenticated;
-- the views call these on the caller's behalf:
grant execute on function public.app_now(), public.market_is_open(public.markets) to authenticated;
