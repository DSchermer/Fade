-- Fade — leaving a group, and handing over ownership (agreed rules):
--   • An owner cannot leave while other members remain: they must first make someone else the owner.
--   • Anyone else can leave once they have NO unsettled bets in the group.
--   • Their open offers are cancelled and refunded automatically; leftover coins are burned.
--   • Their net profit in the group moves into their lifetime score ("closed profit") and is kept for good.
--   • Coming back later = 0 coins (existing rule); the weekly-buyback window still remembers earlier buybacks.
--
-- Zero-sum bookkeeping: when someone leaves with profit p, those coins leave the group's books but the group's
-- OTHER members are down p. We record p on the member row (`realized_profit`) so every group still sums to 0.

alter table public.group_members add column realized_profit bigint not null default 0;

-- only one active owner per group
create unique index one_active_owner_per_group on public.group_members (group_id)
  where role = 'owner' and status = 'active';

alter table public.offers drop constraint offers_cancel_reason_check;
alter table public.offers add constraint offers_cancel_reason_check
  check (cancel_reason in ('maker', 'started', 'market_closed', 'reset', 'left'));

-- ───────────────────────── leave ─────────────────────────
create function public.leave_group(p_group uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  m     public.group_members%rowtype;
  o     record;
  v_tx  uuid;
  v_realized bigint;
  v_rounds integer := 0;
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  select * into m from public.group_members where group_id = p_group and user_id = v_uid and status = 'active';
  if not found then raise exception 'not_a_member'; end if;

  if m.role = 'owner' and exists (select 1 from public.group_members
                                   where group_id = p_group and status = 'active' and user_id <> v_uid) then
    raise exception 'owner_must_transfer';
  end if;

  -- 1. Cancel and refund my open offers. Lock order matches the rest of the app: offer row first, then my balance row.
  loop
    select id, shares_open, price_cents into o from public.offers
     where group_id = p_group and maker_id = v_uid and status = 'open' and shares_open > 0
     order by id limit 1 for update;
    exit when not found;
    perform 1 from public.group_members where group_id = p_group and user_id = v_uid for update;
    v_tx := gen_random_uuid();
    perform public.ledger_post(v_tx, p_group, v_uid, 'escrow',    -(o.shares_open::bigint * o.price_cents), 'escrow_release', 'offer', o.id);
    perform public.ledger_post(v_tx, p_group, v_uid, 'available',   o.shares_open::bigint * o.price_cents,  'escrow_release', 'offer', o.id);
    update public.offers
       set shares_cancelled = shares_cancelled + shares_open, shares_open = 0,
           status = 'cancelled', cancel_reason = 'left'
     where id = o.id;
    v_rounds := v_rounds + 1;
    exit when v_rounds > 10000;
  end loop;

  -- 2. Now lock my balance row for good: nothing can post, take or settle for me until this finishes.
  select * into m from public.group_members where group_id = p_group and user_id = v_uid and status = 'active' for update;
  if not found then raise exception 'not_a_member'; end if;

  -- 3. Unsettled bets block leaving (raising undoes the offer cancellations above — all or nothing).
  if exists (select 1 from public.bets where group_id = p_group and status = 'pending'
                and (maker_id = v_uid or taker_id = v_uid)) then
    raise exception 'has_unsettled_bets';
  end if;
  -- an offer slipped in between step 1 and step 2? refuse rather than strand coins.
  if exists (select 1 from public.offers where group_id = p_group and maker_id = v_uid and status = 'open') then
    raise exception 'has_unsettled_bets';
  end if;

  -- 4. Realise the profit, burn what is left, and clear the profit baseline.
  v_realized := m.available + m.escrow - m.granted - m.buyback_coins;
  if m.available > 0 then
    perform public.ledger_post(gen_random_uuid(), p_group, v_uid, 'available', -m.available, 'leave_burn', 'group', p_group);
  end if;
  update public.group_members
     set status = 'left', role = 'member', granted = 0, buyback_count = 0, buyback_coins = 0,
         realized_profit = realized_profit + v_realized
   where group_id = p_group and user_id = v_uid;
  update public.profiles set lifetime_closed_profit = lifetime_closed_profit + v_realized where id = v_uid;
  return v_realized;
end $$;

-- ───────────────────────── hand over ownership ─────────────────────────
create function public.transfer_ownership(p_group uuid, p_new_owner uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_new_owner is null or p_new_owner = v_uid then raise exception 'invalid_transfer'; end if;

  perform 1 from public.group_members
    where group_id = p_group and user_id in (v_uid, p_new_owner) order by user_id for update;
  if not exists (select 1 from public.group_members
                  where group_id = p_group and user_id = v_uid and status = 'active' and role = 'owner') then
    raise exception 'not_group_owner';
  end if;
  if not exists (select 1 from public.group_members
                  where group_id = p_group and user_id = p_new_owner and status = 'active') then
    raise exception 'target_not_member';
  end if;

  update public.group_members set role = 'member' where group_id = p_group and user_id = v_uid;
  update public.group_members set role = 'owner'  where group_id = p_group and user_id = p_new_owner;
end $$;

-- A group nobody is in any more (its last owner left) can't be joined with its old code.
create or replace function public.join_group(p_code text) returns uuid
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
  if not found or not exists (select 1 from public.group_members where group_id = g.id and status = 'active') then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;

  select * into m from public.group_members where group_id = g.id and user_id = v_uid for update;
  if found then
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

revoke all on function public.leave_group(uuid), public.transfer_ownership(uuid, uuid), public.join_group(text) from public, anon;
grant execute on function public.leave_group(uuid), public.transfer_ownership(uuid, uuid), public.join_group(text) to authenticated;

-- ───────────────────────── Stronger books ─────────────────────────
-- (1) profits still sum to zero once leavers' realised profit is counted;
-- (2) somebody who left holds nothing and has a clean baseline;
-- (3) each person's lifetime closed profit equals what they realised on leaving (and, later, at resets).
create or replace function public.check_ledger_integrity()
returns table (check_name text, group_id uuid, detail text)
language sql stable as $$
  select 'tx_not_zero_sum'::text, (array_agg(l.group_id))[1], 'tx ' || l.tx_id || ' sums to ' || sum(l.delta)
    from public.ledger l
   where l.kind not in ('grant', 'buyback', 'season_burn', 'leave_burn', 'delete_burn')
   group by l.tx_id
  having sum(l.delta) <> 0
  union all
  select 'tx_spans_groups', (array_agg(l.group_id))[1], 'tx ' || l.tx_id
    from public.ledger l group by l.tx_id having count(distinct l.group_id) > 1
  union all
  select 'group_total_mismatch', t.group_id,
         'ledger total ' || t.total || ' vs mint-burn ' || t.minted_net
    from (select l.group_id,
                 sum(l.delta) as total,
                 sum(l.delta) filter (where l.kind in ('grant','buyback','season_burn','leave_burn','delete_burn')) as minted_net
            from public.ledger l group by l.group_id) t
   where t.total <> coalesce(t.minted_net, 0)
  union all
  select 'member_cache_mismatch', m.group_id,
         'user ' || m.user_id || ' cache ' || m.available || '/' || m.escrow
         || ' ledger ' || coalesce(s.av, 0) || '/' || coalesce(s.es, 0)
    from public.group_members m
    left join (select l.group_id, l.user_id,
                      sum(l.delta) filter (where l.bucket = 'available') as av,
                      sum(l.delta) filter (where l.bucket = 'escrow')    as es
                 from public.ledger l group by l.group_id, l.user_id) s
      on s.group_id = m.group_id and s.user_id = m.user_id
   where m.available <> coalesce(s.av, 0) or m.escrow <> coalesce(s.es, 0)
  union all
  select 'group_profit_not_zero_sum', m.group_id,
         'net profits add up to ' || sum(m.available + m.escrow - m.granted - m.buyback_coins + m.realized_profit)
    from public.group_members m
   group by m.group_id
  having sum(m.available + m.escrow - m.granted - m.buyback_coins + m.realized_profit) <> 0
  union all
  select 'left_member_not_clean', m.group_id, 'user ' || m.user_id
    from public.group_members m
   where m.status = 'left' and (m.available <> 0 or m.escrow <> 0 or m.granted <> 0 or m.buyback_coins <> 0 or m.buyback_count <> 0)
  union all
  select 'closed_profit_mismatch', null::uuid, 'user ' || p.id || ' closed ' || p.lifetime_closed_profit
    from public.profiles p
   where p.lifetime_closed_profit <> coalesce((select sum(m.realized_profit) from public.group_members m where m.user_id = p.id), 0);
$$;
revoke all on function public.check_ledger_integrity() from public, anon, authenticated;
