-- Run ONCE in the Supabase SQL Editor after the Milestone 6 migration.
-- Every minute: pay out every bet whose market Polymarket has finalised.
select cron.schedule('fade-settle', '* * * * *', $$select public.settle_resolved_markets()$$);
