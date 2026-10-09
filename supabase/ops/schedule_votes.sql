-- Run ONCE in the Supabase SQL Editor after the Milestone 8 migration.
-- Every minute: close every vote whose 24-hour window is up (pass or fail, and apply a passed reset / buyback).
select cron.schedule('fade-close-votes', '* * * * *', $$select public.close_votes()$$);
