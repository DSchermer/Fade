-- DEV/TESTING ONLY. Voids every PENDING bet and refunds both sides' stakes through the ledger,
-- exactly like a Polymarket 50/50 "no action". Run in the Supabase SQL Editor.
-- (Milestone 6 adds the real settlement; this is a stand-in so you can reset test bets.)
do $$
declare b record; v_tx uuid;
begin
  for b in select * from public.bets where status = 'pending' for update loop
    v_tx := gen_random_uuid();
    perform public.ledger_post(v_tx, b.group_id, b.maker_id, 'escrow',    -b.maker_stake, 'bet_void', 'bet', b.id);
    perform public.ledger_post(v_tx, b.group_id, b.maker_id, 'available',  b.maker_stake, 'bet_void', 'bet', b.id);
    perform public.ledger_post(v_tx, b.group_id, b.taker_id, 'escrow',    -b.taker_stake, 'bet_void', 'bet', b.id);
    perform public.ledger_post(v_tx, b.group_id, b.taker_id, 'available',  b.taker_stake, 'bet_void', 'bet', b.id);
    update public.bets set status = 'void', settled_at = now() where id = b.id;
  end loop;
end $$;

-- Healthy = these two return no rows:
select * from public.check_ledger_integrity();
select * from public.check_betting_integrity();
