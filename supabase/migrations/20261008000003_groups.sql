-- Fade — Milestone 3: creating and joining groups.
-- Both functions run as the database owner (SECURITY DEFINER) because clients cannot write
-- to groups, members or the ledger directly. Starting balances are minted through the ledger.

create function public.create_group(
  p_name              text,
  p_starting_balance  bigint  default 10000,   -- hundredths of a coin: 10000 = 100 coins
  p_buyback_policy    text    default 'unlimited',
  p_buybacks_per_week integer default null,
  p_buyback_amount    bigint  default null     -- null = same as the starting balance
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_name     text := btrim(coalesce(p_name, ''));
  v_buyback  bigint := coalesce(p_buyback_amount, p_starting_balance);
  v_per_week integer := p_buybacks_per_week;
  v_group    uuid;
  v_season   uuid;
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles
                  where id = v_uid and username is not null and not banned and deleted_at is null) then
    raise exception 'profile_required' using errcode = '42501';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'invalid_group_name' using errcode = '22023';
  end if;
  if p_starting_balance is null or p_starting_balance not between 100 and 100000000 then
    raise exception 'invalid_starting_balance' using errcode = '22023';
  end if;
  if v_buyback not between 100 and 100000000 then
    raise exception 'invalid_buyback_amount' using errcode = '22023';
  end if;
  if p_buyback_policy is null or p_buyback_policy not in ('unlimited', 'weekly', 'vote') then
    raise exception 'invalid_buyback_policy' using errcode = '22023';
  end if;
  if p_buyback_policy = 'weekly' then
    if v_per_week is null or v_per_week not between 1 and 50 then
      raise exception 'invalid_buybacks_per_week' using errcode = '22023';
    end if;
  else
    v_per_week := null;
  end if;

  insert into public.groups (name, created_by, starting_balance, buyback_policy, buybacks_per_week, buyback_amount)
  values (v_name, v_uid, p_starting_balance, p_buyback_policy, v_per_week, v_buyback)
  returning id into v_group;

  insert into public.seasons (group_id, number) values (v_group, 1) returning id into v_season;
  update public.groups set current_season_id = v_season where id = v_group;

  insert into public.group_members (group_id, user_id, role) values (v_group, v_uid, 'owner');
  perform public.ledger_post(gen_random_uuid(), v_group, v_uid, 'available', p_starting_balance, 'grant', 'group_create', v_group);

  return v_group;
end $$;

create function public.join_group(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  g       public.groups%rowtype;
  m       public.group_members%rowtype;
  v_added integer;
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles
                  where id = v_uid and username is not null and not banned and deleted_at is null) then
    raise exception 'profile_required' using errcode = '42501';
  end if;

  select * into g from public.groups where invite_code = upper(btrim(coalesce(p_code, '')));
  if not found then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;

  select * into m from public.group_members where group_id = g.id and user_id = v_uid for update;
  if found then
    -- Already a member: nothing to do. Returning after leaving: back in with whatever balance
    -- they have (0 after leaving) and NO new starting grant.
    if m.status = 'left' then
      update public.group_members set status = 'active', joined_at = now()
       where group_id = g.id and user_id = v_uid;
    end if;
    return g.id;
  end if;

  insert into public.group_members (group_id, user_id) values (g.id, v_uid)
  on conflict do nothing;
  get diagnostics v_added = row_count;
  if v_added = 1 then
    perform public.ledger_post(gen_random_uuid(), g.id, v_uid, 'available', g.starting_balance, 'grant', 'group_join', g.id);
  end if;
  return g.id;
end $$;

revoke all on function public.create_group(text, bigint, text, integer, bigint), public.join_group(text) from public, anon;
grant execute on function public.create_group(text, bigint, text, integer, bigint), public.join_group(text) to authenticated;
