-- Fade — Milestone 6: settlement.
-- A market is "final" only through market_resolution() (Milestone 4): closed + status 'resolved' + terminal prices.
-- settle_market() then pays every PENDING bet on it, exactly once:
--   winner  : escrow  −(own stake)   and available +(whole pot)
--   loser   : escrow  −(own stake)
--   void    : each side gets its own stake back (Polymarket 50/50 = "no action")
-- Safe to run any number of times, and from several places at once.

create function public.settle_market(p_market text) returns integer
language plpgsql security definer set search_path = public as $$
declare
  mk  public.markets%rowtype;
  b   record;
  o   record;
  v_tx uuid;
  v_maker_wins boolean;
  v_winner uuid; v_loser uuid; v_win_stake bigint; v_lose_stake bigint;
  n   integer := 0;
begin
  select * into mk from public.markets where id = p_market;
  if not found or mk.resolution = 'pending' then
    return 0;                                        -- not final: nothing is ever paid early
  end if;

  -- 1. An offer still open on a finished market gets its unfilled shares back first.
  for o in select id, group_id, maker_id, shares_open, price_cents from public.offers
            where market_id = p_market and status = 'open' and shares_open > 0
              for update skip locked
  loop
    v_tx := gen_random_uuid();
    perform 1 from public.group_members where group_id = o.group_id and user_id = o.maker_id for update;
    perform public.ledger_post(v_tx, o.group_id, o.maker_id, 'escrow',    -(o.shares_open::bigint * o.price_cents), 'escrow_release', 'offer', o.id);
    perform public.ledger_post(v_tx, o.group_id, o.maker_id, 'available',   o.shares_open::bigint * o.price_cents,  'escrow_release', 'offer', o.id);
    update public.offers
       set shares_cancelled = shares_cancelled + shares_open, shares_open = 0,
           status = 'cancelled', cancel_reason = 'market_closed'
     where id = o.id;
  end loop;

  -- 2. Pay each pending bet. "for update skip locked" + the status filter means a bet can only be paid once.
  for b in select * from public.bets
            where market_id = p_market and status = 'pending'
            order by created_at
              for update skip locked
  loop
    -- lock both people's balance rows in a fixed order (no deadlocks)
    perform 1 from public.group_members
      where group_id = b.group_id and user_id in (b.maker_id, b.taker_id) order by user_id for update;
    v_tx := gen_random_uuid();

    if mk.resolution = 'void' then
      perform public.ledger_post(v_tx, b.group_id, b.maker_id, 'escrow',    -b.maker_stake, 'bet_void', 'bet', b.id);
      perform public.ledger_post(v_tx, b.group_id, b.maker_id, 'available',  b.maker_stake, 'bet_void', 'bet', b.id);
      perform public.ledger_post(v_tx, b.group_id, b.taker_id, 'escrow',    -b.taker_stake, 'bet_void', 'bet', b.id);
      perform public.ledger_post(v_tx, b.group_id, b.taker_id, 'available',  b.taker_stake, 'bet_void', 'bet', b.id);
      update public.bets set status = 'void', settled_at = public.app_now() where id = b.id;
    else
      v_maker_wins := (mk.resolution = 'outcome_0' and b.maker_outcome = 0)
                   or (mk.resolution = 'outcome_1' and b.maker_outcome = 1);
      if v_maker_wins then
        v_winner := b.maker_id; v_win_stake := b.maker_stake; v_loser := b.taker_id; v_lose_stake := b.taker_stake;
      else
        v_winner := b.taker_id; v_win_stake := b.taker_stake; v_loser := b.maker_id; v_lose_stake := b.maker_stake;
      end if;
      perform public.ledger_post(v_tx, b.group_id, v_winner, 'escrow',    -v_win_stake,                 'bet_payout', 'bet', b.id);
      perform public.ledger_post(v_tx, b.group_id, v_winner, 'available',  v_win_stake + v_lose_stake,  'bet_payout', 'bet', b.id);
      perform public.ledger_post(v_tx, b.group_id, v_loser,  'escrow',    -v_lose_stake,                'bet_stake',  'bet', b.id);
      update public.bets
         set status = case when v_maker_wins then 'won_maker' else 'won_taker' end,
             settled_at = public.app_now()
       where id = b.id;
      update public.profiles set lifetime_wins   = lifetime_wins   + 1 where id = v_winner;
      update public.profiles set lifetime_losses = lifetime_losses + 1 where id = v_loser;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Scheduled every minute: settle every market that is final but still has unpaid bets.
create function public.settle_resolved_markets() returns integer
language plpgsql security definer set search_path = public as $$
declare m record; n integer := 0;
begin
  for m in select distinct b.market_id
             from public.bets b join public.markets mk on mk.id = b.market_id
            where b.status = 'pending' and mk.resolution <> 'pending'
  loop
    begin
      n := n + public.settle_market(m.market_id);
    exception when others then
      insert into public.sync_log (kind, ok, detail) values ('settle', false, m.market_id || ': ' || sqlerrm);
    end;
  end loop;
  return n;
end $$;

-- Stronger books: also verify settlement itself.
create or replace function public.check_betting_integrity()
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
   where m.escrow <> coalesce(e.expected, 0)
  union all
  -- a settled bet's result must match the market's final result
  select 'bet_result_mismatch', b.group_id, 'bet ' || b.id || ' is ' || b.status || ' but market is ' || m.resolution
    from public.bets b join public.markets m on m.id = b.market_id
   where b.status <> 'pending'
     and not ((b.status = 'void' and m.resolution = 'void')
           or (b.status = 'won_maker' and m.resolution = 'outcome_' || b.maker_outcome)
           or (b.status = 'won_taker' and m.resolution = 'outcome_' || (1 - b.maker_outcome)))
  union all
  -- ...and each side must have been paid exactly what the result says (winner: whole pot, void: own stake back)
  select 'bet_payout_mismatch', b.group_id, 'bet ' || b.id || ' maker got ' || p.maker_got || ' taker got ' || p.taker_got
    from public.bets b
    cross join lateral (
      select coalesce(sum(l.delta) filter (where l.user_id = b.maker_id), 0) as maker_got,
             coalesce(sum(l.delta) filter (where l.user_id = b.taker_id), 0) as taker_got
        from public.ledger l
       where l.ref_type = 'bet' and l.ref_id = b.id and l.bucket = 'available' and l.kind in ('bet_payout', 'bet_void')) p
   where (p.maker_got, p.taker_got) is distinct from (
           case b.status when 'won_maker' then b.maker_stake + b.taker_stake when 'void' then b.maker_stake else 0 end,
           case b.status when 'won_taker' then b.maker_stake + b.taker_stake when 'void' then b.taker_stake else 0 end)
  union all
  -- win/loss records equal the count of settled bets
  select 'record_mismatch', null::uuid, 'user ' || pr.id || ' record ' || pr.lifetime_wins || '-' || pr.lifetime_losses
    from public.profiles pr
   where pr.lifetime_wins <> (select count(*) from public.bets b
                               where (b.status = 'won_maker' and b.maker_id = pr.id) or (b.status = 'won_taker' and b.taker_id = pr.id))
      or pr.lifetime_losses <> (select count(*) from public.bets b
                               where (b.status = 'won_maker' and b.taker_id = pr.id) or (b.status = 'won_taker' and b.maker_id = pr.id));
$$;

revoke all on function public.settle_market(text), public.settle_resolved_markets() from public, anon, authenticated;
