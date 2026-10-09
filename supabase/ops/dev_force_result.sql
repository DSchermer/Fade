-- DEV/TESTING ONLY. Pretends Polymarket has finalised ONE market, then settles its bets,
-- so you can see payouts without waiting for a real game. Run in the Supabase SQL Editor.
--
-- 1) Find the market id of a bet you made (run this first, copy the id):
--      select m.id, m.event_title, m.question, count(*) as pending_bets
--        from public.bets b join public.markets m on m.id = b.market_id
--       where b.status = 'pending' group by 1, 2, 3;
-- 2) Put the id below, choose the result, run this whole file.
--    outcome_0 = the FIRST side listed in the market wins, outcome_1 = the second side wins, void = 50/50 refund.
do $$
declare
  v_market text := 'PASTE-MARKET-ID-HERE';
  v_result text := 'outcome_0';
  v_prices numeric[];
begin
  v_prices := case v_result
                when 'outcome_0' then '{1,0}'::numeric[]
                when 'outcome_1' then '{0,1}'::numeric[]
                when 'void'      then '{0.5,0.5}'::numeric[] end;
  if v_prices is null then raise exception 'v_result must be outcome_0, outcome_1 or void'; end if;
  update public.markets
     set closed = true, uma_status = 'resolved', outcome_prices = v_prices,
         resolution = v_result, resolved_at = now()
   where id = v_market;
  if not found then raise exception 'no market with id %', v_market; end if;
  perform public.settle_resolved_markets();
end $$;

-- Healthy = no rows:
select * from public.check_ledger_integrity();
select * from public.check_betting_integrity();
