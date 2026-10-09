-- Fade — Milestone 7: leaderboards, buybacks, global score.
--
-- NET PROFIT (leaderboard + global score) = balance − coins granted − buyback coins.
--   balance        = available + escrow
--   granted        = starting-balance coins given to this member (tracked by the ledger trigger)
--   buyback_coins  = coins received from buybacks (tracked by the ledger trigger)
-- Buybacks therefore count AGAINST you, exactly as the rules say.
-- Because betting is zero-sum, every group's net profits add up to exactly 0 (checked below).

alter table public.group_members add column granted bigint not null default 0 check (granted >= 0);
update public.group_members m
   set granted = coalesce((select sum(l.delta) from public.ledger l
                            where l.group_id = m.group_id and l.user_id = m.user_id and l.kind = 'grant'), 0);

create or replace function public.ledger_apply_to_member() returns trigger
language plpgsql as $$
begin
  update public.group_members
     set available     = available + case when new.bucket = 'available' then new.delta else 0 end,
         escrow        = escrow    + case when new.bucket = 'escrow'    then new.delta else 0 end,
         granted       = granted   + case when new.kind = 'grant'   then new.delta else 0 end,
         buyback_count = buyback_count + case when new.kind = 'buyback' then 1 else 0 end,
         buyback_coins = buyback_coins + case when new.kind = 'buyback' then new.delta else 0 end
   where group_id = new.group_id and user_id = new.user_id;
  if not found then
    raise exception 'ledger row for non-member (group %, user %)', new.group_id, new.user_id;
  end if;
  return null;
end $$;

-- ───────────────────────── Buyback records (visible to the whole group) ─────────────────────────
create table public.buybacks (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id),
  season_id  uuid not null references public.seasons (id),
  user_id    uuid not null references public.profiles (id),
  amount     bigint not null check (amount > 0),
  via        text not null default 'policy' check (via in ('policy', 'vote')),
  created_at timestamptz not null default now()
);
create index buybacks_group_idx on public.buybacks (group_id, created_at desc);
create index buybacks_user_idx  on public.buybacks (group_id, user_id, created_at);
alter table public.buybacks enable row level security;
create policy buybacks_select on public.buybacks for select to authenticated using (public.is_group_member(group_id));
grant select on public.buybacks to authenticated;

create view public.buyback_listing with (security_invoker = true) as
  select b.id, b.group_id, b.user_id, p.username, b.amount, b.via, b.created_at
    from public.buybacks b join public.profiles p on p.id = b.user_id;
grant select on public.buyback_listing to authenticated;

-- ───────────────────────── Leaderboard + my score ─────────────────────────
create view public.group_leaderboard with (security_invoker = true) as
  select m.group_id, m.user_id, p.username, m.role,
         m.available, m.escrow, m.available + m.escrow as balance,
         m.buyback_count, m.buyback_coins,
         m.available + m.escrow - m.granted - m.buyback_coins as net_profit
    from public.group_members m
    join public.profiles p on p.id = m.user_id
   where m.status = 'active';
grant select on public.group_leaderboard to authenticated;

-- The signed-in user's global lifetime score: finished seasons / groups left, plus the live profit in every current group.
create view public.my_score with (security_invoker = true) as
  select p.id as user_id, p.lifetime_wins as wins, p.lifetime_losses as losses,
         p.lifetime_closed_profit as closed_profit,
         live.profit as live_profit,
         p.lifetime_closed_profit + live.profit as score
    from public.profiles p
    cross join lateral (
      select coalesce(sum(m.available + m.escrow - m.granted - m.buyback_coins), 0)::bigint as profit
        from public.group_members m
       where m.user_id = p.id and m.status = 'active') live
   where p.id = auth.uid();
grant select on public.my_score to authenticated;

-- ───────────────────────── Buyback rules ─────────────────────────
-- One place decides who may buy back, used by both the status screen and the claim itself.
create function public.buyback_eligibility(p_group uuid, p_user uuid, p_now timestamptz)
returns table (busted boolean, policy text, amount bigint, used integer, allowed integer,
               next_available timestamptz, can_claim boolean, reason text)
language plpgsql stable security definer set search_path = public as $$
declare
  m public.group_members%rowtype;
  g public.groups%rowtype;
  v_used integer := 0;
begin
  select * into m from public.group_members where group_id = p_group and user_id = p_user and status = 'active';
  if not found then raise exception 'not_a_member'; end if;
  select * into g from public.groups where id = p_group;

  busted := (m.available + m.escrow = 0);     -- zero including coins tied up in offers and bets
  policy := g.buyback_policy;
  amount := g.buyback_amount;
  allowed := g.buybacks_per_week;
  next_available := null;

  if g.buyback_policy = 'weekly' then
    select count(*) into v_used from public.buybacks b
     where b.group_id = p_group and b.user_id = p_user and b.season_id = g.current_season_id
       and b.created_at > p_now - interval '7 days';
    if v_used >= g.buybacks_per_week then
      -- when enough of the oldest buybacks in the window have aged out
      select b.created_at + interval '7 days' into next_available from public.buybacks b
       where b.group_id = p_group and b.user_id = p_user and b.season_id = g.current_season_id
         and b.created_at > p_now - interval '7 days'
       order by b.created_at asc offset (v_used - g.buybacks_per_week) limit 1;
    end if;
  end if;
  used := v_used;

  if not busted then
    can_claim := false; reason := 'not_busted';
  elsif g.buyback_policy = 'vote' then
    can_claim := false; reason := 'needs_vote';
  elsif g.buyback_policy = 'weekly' and v_used >= g.buybacks_per_week then
    can_claim := false; reason := 'weekly_limit';
  else
    can_claim := true; reason := null;
  end if;
  return next;
end $$;

create function public.buyback_status(p_group uuid)
returns table (busted boolean, policy text, amount bigint, used integer, allowed integer,
               next_available timestamptz, can_claim boolean, reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  return query select * from public.buyback_eligibility(p_group, auth.uid(), public.app_now());
end $$;

create function public.claim_buyback(p_group uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  g public.groups%rowtype;
  e record;
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  -- lock this member's balance row so two simultaneous claims cannot both pass the "busted" check
  perform 1 from public.group_members where group_id = p_group and user_id = v_uid and status = 'active' for update;
  if not found then raise exception 'not_a_member'; end if;

  select * into e from public.buyback_eligibility(p_group, v_uid, public.app_now());
  if not e.can_claim then
    raise exception '%', case e.reason when 'needs_vote' then 'buyback_requires_vote'
                                       when 'weekly_limit' then 'buyback_limit_reached'
                                       else e.reason end;
  end if;

  select * into g from public.groups where id = p_group;
  insert into public.buybacks (group_id, season_id, user_id, amount, via, created_at)
  values (p_group, g.current_season_id, v_uid, g.buyback_amount, 'policy', public.app_now())
  returning id into v_id;
  -- a "buyback" ledger entry is the only way these coins come into being; it also bumps the member's buyback counters
  perform public.ledger_post(gen_random_uuid(), p_group, v_uid, 'available', g.buyback_amount, 'buyback', 'buyback', v_id);
  return v_id;
end $$;

revoke all on function public.buyback_eligibility(uuid, uuid, timestamptz), public.buyback_status(uuid), public.claim_buyback(uuid)
  from public, anon, authenticated;
grant execute on function public.buyback_status(uuid), public.claim_buyback(uuid) to authenticated;

-- ───────────────────────── Stronger books: profits are zero-sum ─────────────────────────
create or replace function public.check_ledger_integrity()
returns table (check_name text, group_id uuid, detail text)
language sql stable as $$
  -- 1. Every transaction nets to zero, ignoring the only coin-creating / coin-destroying kinds.
  select 'tx_not_zero_sum'::text, (array_agg(l.group_id))[1], 'tx ' || l.tx_id || ' sums to ' || sum(l.delta)
    from public.ledger l
   where l.kind not in ('grant', 'buyback', 'season_burn', 'leave_burn', 'delete_burn')
   group by l.tx_id
  having sum(l.delta) <> 0
  union all
  -- 2. A transaction may not mix groups.
  select 'tx_spans_groups', (array_agg(l.group_id))[1], 'tx ' || l.tx_id
    from public.ledger l group by l.tx_id having count(distinct l.group_id) > 1
  union all
  -- 3. Group total in the ledger = minted − burned.
  select 'group_total_mismatch', t.group_id,
         'ledger total ' || t.total || ' vs mint-burn ' || t.minted_net
    from (select l.group_id,
                 sum(l.delta) as total,
                 sum(l.delta) filter (where l.kind in ('grant','buyback','season_burn','leave_burn','delete_burn')) as minted_net
            from public.ledger l group by l.group_id) t
   where t.total <> coalesce(t.minted_net, 0)
  union all
  -- 4. Cached member balances equal what the ledger says.
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
  -- 5. Play money is zero-sum: in every group, everyone's net profits add up to exactly 0.
  select 'group_profit_not_zero_sum', m.group_id, 'net profits add up to ' || sum(m.available + m.escrow - m.granted - m.buyback_coins)
    from public.group_members m
   group by m.group_id
  having sum(m.available + m.escrow - m.granted - m.buyback_coins) <> 0;
$$;
revoke all on function public.check_ledger_integrity() from public, anon, authenticated;
