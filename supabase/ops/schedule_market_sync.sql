-- Run ONCE in the Supabase SQL Editor after the Milestone 4 migration.
-- Turns on the two extensions the sync needs and schedules the jobs.
-- (If an extension line errors, enable it instead under Database → Extensions: "http" and "pg_cron".)

create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

select cron.schedule('fade-sync-markets',    '*/15 * * * *', $$select public.sync_markets()$$);
select cron.schedule('fade-refresh-markets', '*/5 * * * *',  $$select public.refresh_markets()$$);
