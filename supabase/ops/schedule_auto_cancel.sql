-- Run ONCE in the Supabase SQL Editor after the Milestone 5 migration.
-- Every minute: cancel unfilled offer shares for games that have started (no live betting).
select cron.schedule('fade-auto-cancel', '* * * * *', $$select public.auto_cancel_started()$$);
