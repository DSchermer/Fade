-- Milestone 3 tests: create_group and join_group.
\set ON_ERROR_STOP on
begin;

create procedure pg_temp.expect_error(p_sql text, p_like text) language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like p_like then return; end if;
    raise exception 'wrong error for [%]: got "%", wanted like "%"', p_sql, sqlerrm, p_like;
  end;
  raise exception 'expected an error but none was raised for [%]', p_sql;
end $$;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1');
insert into profiles (id, username) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob'),
  ('00000000-0000-0000-0000-0000000000c1', 'carol');
-- d1 has no profile (never picked a username).

set local role authenticated;

-- ── Create ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
create temp table t_ids (name text primary key, id uuid);
grant all on t_ids to authenticated;
insert into t_ids select 'g1', create_group('  Friday Crew  ');       -- all defaults
insert into t_ids select 'g2', create_group('Weekly', 5000, 'weekly', 2, 2500);
insert into t_ids select 'g3', create_group('Voters', 20000, 'vote', 7);   -- stray per-week value is dropped

do $$ declare g1 uuid := (select id from t_ids where name = 'g1'); begin
  assert (select name from groups where id = g1) = 'Friday Crew', 'name trimmed';
  assert (select starting_balance from groups where id = g1) = 10000, 'default 100 coins';
  assert (select buyback_amount from groups where id = g1) = 10000, 'buyback defaults to starting balance';
  assert (select buyback_policy from groups where id = g1) = 'unlimited', 'default policy';
  assert (select count(*) from seasons where group_id = g1 and number = 1) = 1, 'season 1 exists';
  assert (select current_season_id from groups where id = g1) = (select id from seasons where group_id = g1), 'current season set';
  assert (select role from group_members where group_id = g1) = 'owner', 'creator is owner';
  assert (select available from group_members where group_id = g1) = 10000, 'creator got the starting balance';
  assert (select count(*) from ledger where group_id = g1 and kind = 'grant' and delta = 10000) = 1, 'one grant in the ledger';
end $$;
do $$ declare g2 uuid := (select id from t_ids where name = 'g2'); begin
  assert (select buybacks_per_week from groups where id = g2) = 2, 'weekly count stored';
  assert (select buyback_amount from groups where id = g2) = 2500, 'custom buyback amount';
  assert (select available from group_members where group_id = g2) = 5000, 'custom starting balance';
end $$;
do $$ begin assert (select buybacks_per_week from groups where name = 'Voters') is null, 'per-week dropped for non-weekly'; end $$;

-- ── Create: validation ──
call pg_temp.expect_error($q$ select create_group('   ') $q$, '%invalid_group_name%');
call pg_temp.expect_error($q$ select create_group(null) $q$, '%invalid_group_name%');
call pg_temp.expect_error($q$ select create_group(repeat('x', 61)) $q$, '%invalid_group_name%');
call pg_temp.expect_error($q$ select create_group('A', 0) $q$, '%invalid_starting_balance%');
call pg_temp.expect_error($q$ select create_group('A', 99) $q$, '%invalid_starting_balance%');
call pg_temp.expect_error($q$ select create_group('A', 100000001) $q$, '%invalid_starting_balance%');
call pg_temp.expect_error($q$ select create_group('A', 10000, 'unlimited', null, 5) $q$, '%invalid_buyback_amount%');
call pg_temp.expect_error($q$ select create_group('A', 10000, 'sometimes') $q$, '%invalid_buyback_policy%');
call pg_temp.expect_error($q$ select create_group('A', 10000, 'weekly') $q$, '%invalid_buybacks_per_week%');
call pg_temp.expect_error($q$ select create_group('A', 10000, 'weekly', 0) $q$, '%invalid_buybacks_per_week%');
call pg_temp.expect_error($q$ select create_group('A', 10000, 'weekly', 51) $q$, '%invalid_buybacks_per_week%');
do $$ begin assert (select count(*) from groups) = 3, 'failed creates leave nothing behind'; end $$;

-- ── Join ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
do $$ begin assert (select count(*) from groups) = 0, 'bob sees no groups before joining'; end $$;
reset role;
create temp table t_code as select invite_code as code from groups where id = (select id from t_ids where name = 'g1');
grant all on t_code to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);

do $$ declare g1 uuid := (select id from t_ids where name = 'g1'); r uuid; begin
  r := join_group(lower('  ' || (select code from t_code) || ' '));   -- lowercase + spaces still work
  assert r = g1, 'join returns the group id';
  assert (select available from group_members where group_id = g1 and user_id = '00000000-0000-0000-0000-0000000000b1') = 10000, 'joiner gets the starting balance';
  assert (select role from group_members where group_id = g1 and user_id = '00000000-0000-0000-0000-0000000000b1') = 'member', 'joiner is a member';
  assert (select count(*) from groups) = 1, 'bob now sees exactly the group he joined';
  assert (select count(*) from group_members) = 2, 'bob sees both members';
  assert (select count(*) from profiles) = 2, 'bob sees alice and himself';
  -- joining again is harmless and pays nothing
  assert join_group((select code from t_code)) = g1, 'rejoin while active returns the group';
  assert (select available from group_members where group_id = g1 and user_id = '00000000-0000-0000-0000-0000000000b1') = 10000, 'no double grant';
  assert (select count(*) from ledger where group_id = g1 and kind = 'grant') = 1, 'bob sees only his own grant row';
end $$;

-- ── Join: errors ──
call pg_temp.expect_error($q$ select join_group('NOSUCHCODE') $q$, '%group_not_found%');
call pg_temp.expect_error($q$ select join_group(null) $q$, '%group_not_found%');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', true);   -- no username yet
call pg_temp.expect_error($q$ select join_group((select code from t_code)) $q$, '%profile_required%');
call pg_temp.expect_error($q$ select create_group('Nope') $q$, '%profile_required%');
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select join_group((select code from t_code)) $q$, '%not_signed_in%');
reset role;
set local role anon;
call pg_temp.expect_error($q$ select create_group('Nope') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select join_group('X') $q$, '%permission denied%');
reset role;

-- ── Outsiders see nothing; clients still cannot write ──
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
do $$ begin
  assert (select count(*) from groups) = 0 and (select count(*) from group_members) = 0
     and (select count(*) from seasons) = 0 and (select count(*) from ledger) = 0, 'carol (in no group) sees nothing';
end $$;
call pg_temp.expect_error($q$ insert into groups (name, created_by) values ('x', '00000000-0000-0000-0000-0000000000c1') $q$, '%permission denied%');
call pg_temp.expect_error($q$ insert into group_members (group_id, user_id) select id, '00000000-0000-0000-0000-0000000000c1' from groups $q$, '%permission denied%');
reset role;

-- ── Returning after leaving: back in with 0 coins and NO new grant ──
-- (simulate the future leave_group: burn the balance and mark left)
select ledger_post(gen_random_uuid(), (select id from t_ids where name = 'g1'), '00000000-0000-0000-0000-0000000000b1', 'available', -10000, 'leave_burn');
update group_members set status = 'left', granted = 0 where user_id = '00000000-0000-0000-0000-0000000000b1';   -- (what the real leave will do: balance burned, profit baseline cleared)
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
do $$ begin assert (select count(*) from groups) = 0, 'a member who left no longer sees the group'; end $$;
do $$ begin
  perform join_group((select code from t_code));
  assert (select status from group_members where user_id = '00000000-0000-0000-0000-0000000000b1') = 'active', 'reactivated';
  assert (select available + escrow from group_members where user_id = '00000000-0000-0000-0000-0000000000b1') = 0, 'returns with 0 coins';
  assert (select count(*) from ledger where kind = 'grant' and user_id = '00000000-0000-0000-0000-0000000000b1') = 1, 'no second grant';
end $$;
reset role;

-- ── The books balance ──
do $$ begin assert (select count(*) from check_ledger_integrity()) = 0, 'integrity clean after groups'; end $$;

rollback;
