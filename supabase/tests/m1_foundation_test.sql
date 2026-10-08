-- Milestone 1 tests. Run with supabase/tests/run.sh (needs a local Postgres).
-- Any failed assertion raises an exception and the run stops with an error.
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

-- Fixtures: three users, two groups.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c');
insert into profiles (id, username) values
  ('00000000-0000-0000-0000-00000000000a', 'alice'),
  ('00000000-0000-0000-0000-00000000000b', 'bob'),
  ('00000000-0000-0000-0000-00000000000c', 'carol');
insert into groups (id, name, created_by) values
  ('10000000-0000-0000-0000-000000000001', 'G1', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000002', 'G2', '00000000-0000-0000-0000-00000000000c');
insert into group_members (group_id, user_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000c');

-- T1: a grant raises the cached balance and nothing else.
select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'available', 10000, 'grant');
select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'available', 10000, 'grant');
select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000c', 'available', 10000, 'grant');
do $$ begin
  assert (select available from group_members where user_id = '00000000-0000-0000-0000-00000000000a') = 10000, 'T1 available';
  assert (select escrow from group_members where user_id = '00000000-0000-0000-0000-00000000000a') = 0, 'T1 escrow';
end $$;

-- T2: a balanced escrow move (lock 3000) updates both buckets and passes every check.
do $$ declare t uuid := gen_random_uuid(); begin
  perform ledger_post(t, '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'available', -3000, 'escrow_lock');
  perform ledger_post(t, '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'escrow',     3000, 'escrow_lock');
end $$;
do $$ begin
  assert (select available from group_members where user_id = '00000000-0000-0000-0000-00000000000a') = 7000, 'T2 available';
  assert (select escrow from group_members where user_id = '00000000-0000-0000-0000-00000000000a') = 3000, 'T2 escrow';
  assert (select count(*) from check_ledger_integrity()) = 0, 'T2 integrity should be clean';
end $$;

-- T3: balances can never go negative (overspend is rejected).
call pg_temp.expect_error($q$
  select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'available', -10001, 'escrow_lock')
$q$, '%available%');

-- T4: ledger rows for a non-member are rejected.
call pg_temp.expect_error($q$
  select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'available', 100, 'grant')
$q$, '%non-member%');

-- T5: the ledger is append-only, even for the table owner.
call pg_temp.expect_error('update ledger set delta = 1', '%append-only%');
call pg_temp.expect_error('delete from ledger', '%append-only%');
call pg_temp.expect_error('truncate ledger', '%append-only%');

-- T6: the integrity checks actually catch faults.
savepoint s1;
  -- an unbalanced move (only one leg)
  select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'available', -100, 'escrow_lock');
  do $$ begin assert (select count(*) from check_ledger_integrity() where check_name = 'tx_not_zero_sum') = 1, 'T6a unbalanced tx not caught'; end $$;
rollback to s1;
savepoint s2;
  -- a tampered cache (bypassing the trigger as the superuser running this test)
  update group_members set available = available + 1 where user_id = '00000000-0000-0000-0000-00000000000b';
  do $$ begin assert (select count(*) from check_ledger_integrity() where check_name = 'member_cache_mismatch') = 1, 'T6b cache tamper not caught'; end $$;
rollback to s2;
do $$ begin assert (select count(*) from check_ledger_integrity()) = 0, 'T6 clean again after rollback'; end $$;

-- T7: a buyback is a mint and bumps the buyback counters.
select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'available', 10000, 'buyback');
do $$ begin
  assert (select buyback_count from group_members where user_id = '00000000-0000-0000-0000-00000000000b') = 1, 'T7 count';
  assert (select buyback_coins from group_members where user_id = '00000000-0000-0000-0000-00000000000b') = 10000, 'T7 coins';
  assert (select count(*) from check_ledger_integrity()) = 0, 'T7 integrity clean';
end $$;

-- T8: Row Level Security, as a signed-in client.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);  -- alice (member of G1 only)
do $$ begin
  assert (select count(*) from groups) = 1, 'T8 alice sees only her group';
  assert (select count(*) from group_members) = 2, 'T8 alice sees G1 members only';
  assert (select count(*) from ledger) = 3, 'T8 alice sees only her own ledger rows';
  assert (select count(*) from profiles) = 2, 'T8 alice sees herself and bob, not carol';
  assert (select count(*) from seasons) = 0, 'T8 no seasons yet';
end $$;
-- Clients cannot write balances, the ledger, or anyone's membership.
call pg_temp.expect_error($q$ update group_members set available = 999999 $q$, '%permission denied%');
call pg_temp.expect_error($q$ insert into ledger (tx_id, group_id, user_id, bucket, delta, kind) values (gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'available', 5000, 'grant') $q$, '%permission denied%');
call pg_temp.expect_error($q$ delete from ledger $q$, '%permission denied%');
call pg_temp.expect_error($q$ insert into group_members (group_id, user_id) values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a') $q$, '%permission denied%');
call pg_temp.expect_error($q$ update groups set starting_balance = 1 $q$, '%permission denied%');
call pg_temp.expect_error($q$ update profiles set lifetime_closed_profit = 999999 $q$, '%permission denied%');
call pg_temp.expect_error($q$ update profiles set username = 'hacker' $q$, '%permission denied%');
call pg_temp.expect_error($q$ select ledger_post(gen_random_uuid(), '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'available', 5000, 'grant') $q$, '%permission denied%');
call pg_temp.expect_error($q$ select * from check_ledger_integrity() $q$, '%permission denied%');
-- The one allowed write: your own display settings. Someone else's row is untouched.
update profiles set display_name = 'Alice!' where id = '00000000-0000-0000-0000-00000000000a';
update profiles set display_name = 'Hacked' where id = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  assert (select display_name from profiles where id = '00000000-0000-0000-0000-00000000000a') = 'Alice!', 'T8 own update works';
  assert (select display_name from profiles where id = '00000000-0000-0000-0000-00000000000b') = '', 'T8 other user untouched';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', true);  -- carol (G2 only)
do $$ begin
  assert (select count(*) from groups) = 1 and (select name from groups) = 'G2', 'T8 carol sees only G2';
  assert (select count(*) from ledger) = 1, 'T8 carol sees only her ledger row';
  assert (select count(*) from profiles) = 1, 'T8 carol sees only herself';
end $$;

select set_config('request.jwt.claim.sub', '', true);  -- signed in but no identity
do $$ begin
  assert (select count(*) from groups) = 0 and (select count(*) from ledger) = 0 and (select count(*) from profiles) = 0, 'T8 no identity sees nothing';
end $$;

reset role;
do $$ begin assert (select count(*) from check_ledger_integrity()) = 0, 'final integrity clean'; end $$;

rollback;
