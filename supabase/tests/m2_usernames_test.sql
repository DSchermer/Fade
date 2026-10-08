-- Milestone 2 tests: usernames and profile creation.
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
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1');

-- Not signed in: refused. Anonymous role: cannot even call it.
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
call pg_temp.expect_error($q$ select set_username('someone') $q$, '%not_signed_in%');
reset role;
set local role anon;
call pg_temp.expect_error($q$ select set_username('someone') $q$, '%permission denied%');
reset role;

-- Alice picks a name (mixed case and spaces are normalised).
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
do $$ begin
  assert set_username('  Alice_1 ') = 'alice_1', 'normalised name returned';
  assert (select username from profiles) = 'alice_1', 'profile created with name';
  assert (select price_format from profiles) = 'cents', 'default price format';
  assert username_available('alice_1') = true, 'own name counts as available to herself';
  assert username_available('zed_zed') = true, 'free name available';
  assert username_available('ab') = false, 'too short is not available';
end $$;

-- Bob cannot take Alice's name in any casing; bad names are rejected.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
do $$ begin assert username_available('ALICE_1') = false, 'taken name shown as unavailable'; end $$;
call pg_temp.expect_error($q$ select set_username('ALICE_1') $q$, '%username_taken%');
call pg_temp.expect_error($q$ select set_username('ab') $q$, '%username_invalid%');
call pg_temp.expect_error($q$ select set_username('has space') $q$, '%username_invalid%');
call pg_temp.expect_error($q$ select set_username('bad-char') $q$, '%username_invalid%');
call pg_temp.expect_error($q$ select set_username('abcdefghijklmnopqrstu') $q$, '%username_invalid%');
call pg_temp.expect_error($q$ select set_username(null) $q$, '%username_invalid%');
call pg_temp.expect_error($q$ select set_username('Admin') $q$, '%username_reserved%');
do $$ begin assert (select count(*) from profiles where id = '00000000-0000-0000-0000-0000000000b1') = 0, 'failed attempts create no profile'; end $$;

-- Bob succeeds with a free name, then renames; his old name becomes free again.
select set_username('bobby');
select set_username('bob_the_great');
do $$ begin
  assert username_available('bobby') = true, 'old name freed after rename';
  assert (select username from profiles where id = '00000000-0000-0000-0000-0000000000b1') = 'bob_the_great', 'renamed';
end $$;

-- Price format: allowed values only, own row only.
update profiles set price_format = 'american' where id = '00000000-0000-0000-0000-0000000000b1';
do $$ begin assert (select price_format from profiles where id = '00000000-0000-0000-0000-0000000000b1') = 'american', 'format updated'; end $$;
call pg_temp.expect_error($q$ update profiles set price_format = 'decimal' where id = '00000000-0000-0000-0000-0000000000b1' $q$, '%price_format%');

-- A banned user cannot change their name.
reset role;
update profiles set banned = true where username = 'bob_the_great';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', true);
call pg_temp.expect_error($q$ select set_username('newname') $q$, '%account_disabled%');

reset role;
rollback;
