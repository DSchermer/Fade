-- DEV/TESTING ONLY. Votes run for 24 hours; this pretends the time is up for every OPEN vote in one group and closes them now,
-- so you can see "time ran out" outcomes (pass by majority at the deadline, fail for too few voters, etc.) without waiting.
-- Run in the Supabase SQL Editor.
--
-- 1) Put the group's name below (exactly as shown in the app).
-- 2) Run this whole file. The last query shows how each vote ended.
do $$
declare
  v_group_name text := 'PASTE GROUP NAME HERE';
  v_group uuid;
begin
  select id into v_group from public.groups where name = v_group_name order by created_at desc limit 1;
  if v_group is null then raise exception 'no group named %', v_group_name; end if;
  update public.votes set closes_at = public.app_now() - interval '1 minute' where group_id = v_group and status = 'open';
  perform public.close_votes();
end $$;

select v.kind, v.status, v.yes_count, v.no_count, v.electorate, v.quorum, v.decision_note, v.decided_at
  from public.votes v join public.groups g on g.id = v.group_id
 where g.name = 'PASTE GROUP NAME HERE'
 order by v.created_at desc limit 5;

-- Healthy = no rows from any of these:
select * from public.check_ledger_integrity();
select * from public.check_betting_integrity();
select * from public.check_season_integrity();
