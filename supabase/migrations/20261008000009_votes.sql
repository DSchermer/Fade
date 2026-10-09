-- Fade — Milestone 8: votes (group reset, buyback-by-vote) and season history.
--
-- Rules (from the spec + decisions log):
--   • Any active member can call a RESET vote. In groups whose buyback policy is "vote", a BUSTED member can call a
--     BUYBACK vote for themselves.
--   • Window: 24 hours. Passes if yes > no among current members' ballots AND quorum is reached, where
--       quorum = min(members, max(2, ceil(25% of members))).
--     It closes EARLY once the result can no longer change: yes more than half of all members (pass), or no at least
--     half of all members (fail — yes can't beat no any more).
--   • A passing RESET, in one transaction: cancels every open offer (refund), voids every unsettled bet (refund both
--     stakes, no win/loss), snapshots the season into history, gives everyone the starting balance again, clears
--     buyback counters, starts the next season.
--   • A passing BUYBACK vote pays the buyback amount (if the member is still busted and still in the group).

create table public.votes (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.groups (id),
  season_id    uuid not null references public.seasons (id),
  kind         text not null check (kind in ('reset', 'buyback')),
  subject_id   uuid references public.profiles (id),            -- buyback votes: who is asking
  called_by    uuid not null references public.profiles (id),
  opens_at     timestamptz not null,
  closes_at    timestamptz not null,
  status       text not null default 'open' check (status in ('open', 'passed', 'failed', 'cancelled')),
  yes_count    integer,                                         -- final tallies, recorded when the vote ends
  no_count     integer,
  electorate   integer,                                         -- members at the time it ended
  quorum       integer,
  decided_at   timestamptz,
  decision_note text,
  created_at   timestamptz not null default now(),
  check ((kind = 'buyback') = (subject_id is not null)),
  check ((status = 'open') = (decided_at is null))
);
create unique index one_open_reset_vote_per_group on public.votes (group_id) where kind = 'reset' and status = 'open';
create unique index one_open_buyback_vote_per_member on public.votes (group_id, subject_id) where kind = 'buyback' and status = 'open';
create index votes_open_idx on public.votes (closes_at) where status = 'open';
create index votes_group_idx on public.votes (group_id, created_at desc);

create table public.vote_ballots (
  vote_id    uuid not null references public.votes (id) on delete cascade,
  user_id    uuid not null references public.profiles (id),
  yes        boolean not null,
  created_at timestamptz not null default now(),
  primary key (vote_id, user_id)
);

alter table public.votes        enable row level security;
alter table public.vote_ballots enable row level security;
create policy votes_select   on public.votes        for select to authenticated using (public.is_group_member(group_id));
create policy ballots_select on public.vote_ballots for select to authenticated
  using (exists (select 1 from public.votes v where v.id = vote_id and public.is_group_member(v.group_id)));
grant select on public.votes, public.vote_ballots to authenticated;

-- Live tallies for the app.
create view public.vote_listing with (security_invoker = true) as
  select v.id, v.group_id, v.kind, v.subject_id, sp.username as subject_username,
         v.called_by, cp.username as called_by_username,
         v.opens_at, v.closes_at, v.status, v.decided_at, v.decision_note,
         case when v.status = 'open'
              then (select count(*) from public.vote_ballots b join public.group_members m
                     on m.group_id = v.group_id and m.user_id = b.user_id and m.status = 'active'
                    where b.vote_id = v.id and b.yes)
              else v.yes_count end::integer as yes_count,
         case when v.status = 'open'
              then (select count(*) from public.vote_ballots b join public.group_members m
                     on m.group_id = v.group_id and m.user_id = b.user_id and m.status = 'active'
                    where b.vote_id = v.id and not b.yes)
              else v.no_count end::integer as no_count,
         case when v.status = 'open'
              then (select count(*) from public.group_members m where m.group_id = v.group_id and m.status = 'active')
              else v.electorate end::integer as electorate,
         (select b.yes from public.vote_ballots b where b.vote_id = v.id and b.user_id = auth.uid()) as my_vote,
         v.created_at
    from public.votes v
    left join public.profiles sp on sp.id = v.subject_id
    join public.profiles cp on cp.id = v.called_by;
grant select on public.vote_listing to authenticated;

-- Past seasons (history).
create view public.season_history with (security_invoker = true) as
  select s.id as season_id, s.group_id, s.number, s.started_at, s.ended_at,
         st.user_id, p.username, st.final_balance, st.buyback_count, st.buyback_coins, st.net_profit
    from public.seasons s
    join public.season_standings st on st.season_id = s.id
    join public.profiles p on p.id = st.user_id
   where s.ended_at is not null;
grant select on public.season_history to authenticated;

create function public.vote_quorum(p_members integer) returns integer
language sql immutable as $$ select least(p_members, greatest(2, ceil(p_members * 0.25)::integer)); $$;

-- ───────────────────────── the group reset ─────────────────────────
-- Lock order is always: offers → bets → member balance rows (so it can't deadlock with post/take/settle/leave).
create function public.apply_group_reset(p_vote public.votes) returns void
language plpgsql security definer set search_path = public as $$
declare
  g  public.groups%rowtype;
  o  record;
  b  record;
  m  record;
  v_tx uuid;
  v_net bigint;
  v_season uuid;
  v_number integer;
begin
  select * into g from public.groups where id = p_vote.group_id;

  perform 1 from public.offers where group_id = g.id and status = 'open' order by id for update;
  perform 1 from public.bets   where group_id = g.id and status = 'pending' order by id for update;
  perform 1 from public.group_members where group_id = g.id order by user_id for update;

  -- 1. open offers: unfilled shares go back
  for o in select id, maker_id, shares_open, price_cents from public.offers
            where group_id = g.id and status = 'open' and shares_open > 0
  loop
    v_tx := gen_random_uuid();
    perform public.ledger_post(v_tx, g.id, o.maker_id, 'escrow',    -(o.shares_open::bigint * o.price_cents), 'escrow_release', 'offer', o.id);
    perform public.ledger_post(v_tx, g.id, o.maker_id, 'available',   o.shares_open::bigint * o.price_cents,  'escrow_release', 'offer', o.id);
    update public.offers
       set shares_cancelled = shares_cancelled + shares_open, shares_open = 0,
           status = 'cancelled', cancel_reason = 'reset'
     where id = o.id;
  end loop;

  -- 2. unsettled bets are voided: each side gets its own stake back; no win or loss is recorded
  for b in select * from public.bets where group_id = g.id and status = 'pending' loop
    v_tx := gen_random_uuid();
    perform public.ledger_post(v_tx, g.id, b.maker_id, 'escrow',    -b.maker_stake, 'bet_void', 'bet', b.id);
    perform public.ledger_post(v_tx, g.id, b.maker_id, 'available',  b.maker_stake, 'bet_void', 'bet', b.id);
    perform public.ledger_post(v_tx, g.id, b.taker_id, 'escrow',    -b.taker_stake, 'bet_void', 'bet', b.id);
    perform public.ledger_post(v_tx, g.id, b.taker_id, 'available',  b.taker_stake, 'bet_void', 'bet', b.id);
    update public.bets set status = 'void', settled_at = public.app_now() where id = b.id;
  end loop;

  -- 3. snapshot the season, keep each member's net profit for good, burn and re-grant
  for m in select * from public.group_members where group_id = g.id and status = 'active' order by user_id loop
    select available + escrow - granted - buyback_coins into v_net from public.group_members
     where group_id = g.id and user_id = m.user_id;
    insert into public.season_standings (season_id, user_id, final_balance, buyback_count, buyback_coins, net_profit)
    select g.current_season_id, gm.user_id, gm.available + gm.escrow, gm.buyback_count, gm.buyback_coins, v_net
      from public.group_members gm where gm.group_id = g.id and gm.user_id = m.user_id;
    update public.profiles set lifetime_closed_profit = lifetime_closed_profit + v_net where id = m.user_id;
    update public.group_members set realized_profit = realized_profit + v_net where group_id = g.id and user_id = m.user_id;
    select available into v_net from public.group_members where group_id = g.id and user_id = m.user_id;   -- (reuse: amount to burn)
    if v_net > 0 then
      perform public.ledger_post(gen_random_uuid(), g.id, m.user_id, 'available', -v_net, 'season_burn', 'season', g.current_season_id);
    end if;
    update public.group_members set granted = 0, buyback_count = 0, buyback_coins = 0
     where group_id = g.id and user_id = m.user_id;
    perform public.ledger_post(gen_random_uuid(), g.id, m.user_id, 'available', g.starting_balance, 'grant', 'season', g.current_season_id);
  end loop;

  -- 4. close this season, open the next
  update public.seasons set ended_at = public.app_now() where id = g.current_season_id;
  select coalesce(max(number), 0) + 1 into v_number from public.seasons where group_id = g.id;
  insert into public.seasons (group_id, number, started_at) values (g.id, v_number, public.app_now()) returning id into v_season;
  update public.groups set current_season_id = v_season where id = g.id;

  -- 5. any other vote still open (buyback requests) is moot now
  update public.votes set status = 'cancelled', decided_at = public.app_now(), decision_note = 'group was reset'
   where group_id = g.id and status = 'open' and id <> p_vote.id;
end $$;

-- ───────────────────────── decide a vote ─────────────────────────
-- p_expired = true when the 24h window has run out. Otherwise decides only if the result can no longer change.
create function public.evaluate_vote(p_vote uuid, p_expired boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  v public.votes%rowtype;
  g public.groups%rowtype;
  v_members integer; v_yes integer; v_no integer; v_quorum integer;
  v_result text; v_note text;
  sm public.group_members%rowtype;
  v_bb uuid;
begin
  select * into v from public.votes where id = p_vote for update;
  if not found or v.status <> 'open' then return 'skipped'; end if;           -- someone else already decided it
  select * into g from public.groups where id = v.group_id;

  select count(*) into v_members from public.group_members where group_id = v.group_id and status = 'active';
  select count(*) filter (where b.yes), count(*) filter (where not b.yes) into v_yes, v_no
    from public.vote_ballots b join public.group_members m
      on m.group_id = v.group_id and m.user_id = b.user_id and m.status = 'active'
   where b.vote_id = v.id;
  v_quorum := public.vote_quorum(v_members);

  if v_yes * 2 > v_members then
    v_result := 'passed'; v_note := 'more than half of all members voted yes';
  elsif v_no * 2 >= v_members then
    v_result := 'failed'; v_note := 'yes can no longer win';
  elsif p_expired then
    if v_yes + v_no < v_quorum then v_result := 'failed'; v_note := 'quorum not reached';
    elsif v_yes > v_no         then v_result := 'passed'; v_note := 'more yes than no when time ran out';
    else                            v_result := 'failed'; v_note := 'not more yes than no';
    end if;
  else
    return 'open';
  end if;

  if v_result = 'passed' then
    if v.kind = 'reset' then
      perform public.apply_group_reset(v);
    else
      -- buyback by vote: only if they are still in the group and still broke
      select * into sm from public.group_members where group_id = v.group_id and user_id = v.subject_id and status = 'active' for update;
      if not found or sm.available + sm.escrow <> 0 then
        v_result := 'cancelled'; v_note := 'member is no longer broke or has left';
      else
        insert into public.buybacks (group_id, season_id, user_id, amount, via, created_at)
        values (v.group_id, g.current_season_id, v.subject_id, g.buyback_amount, 'vote', public.app_now())
        returning id into v_bb;
        perform public.ledger_post(gen_random_uuid(), v.group_id, v.subject_id, 'available', g.buyback_amount, 'buyback', 'buyback', v_bb);
      end if;
    end if;
  end if;

  update public.votes
     set status = v_result, yes_count = v_yes, no_count = v_no, electorate = v_members, quorum = v_quorum,
         decided_at = public.app_now(), decision_note = v_note
   where id = v.id;
  return v_result;
end $$;

-- ───────────────────────── what members call ─────────────────────────
create function public.call_vote(p_group uuid, p_kind text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  g public.groups%rowtype;
  m public.group_members%rowtype;
  v_id uuid;
  v_now timestamptz := public.app_now();
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_kind is null or p_kind not in ('reset', 'buyback') then raise exception 'invalid_vote_kind'; end if;
  select * into m from public.group_members where group_id = p_group and user_id = v_uid and status = 'active' for update;
  if not found then raise exception 'not_a_member'; end if;
  select * into g from public.groups where id = p_group;

  if p_kind = 'buyback' then
    if g.buyback_policy <> 'vote' then raise exception 'buyback_vote_not_allowed'; end if;
    if m.available + m.escrow <> 0 then raise exception 'not_busted'; end if;
  end if;

  begin
    insert into public.votes (group_id, season_id, kind, subject_id, called_by, opens_at, closes_at)
    values (p_group, g.current_season_id, p_kind, case when p_kind = 'buyback' then v_uid end, v_uid, v_now, v_now + interval '24 hours')
    returning id into v_id;
  exception when unique_violation then
    raise exception 'vote_already_open';
  end;
  insert into public.vote_ballots (vote_id, user_id, yes) values (v_id, v_uid, true);     -- the caller votes yes
  perform public.evaluate_vote(v_id, false);                                                -- e.g. a group of one decides at once
  return v_id;
end $$;

create function public.cast_vote(p_vote uuid, p_yes boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v public.votes%rowtype;
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_yes is null then raise exception 'invalid_ballot'; end if;
  select * into v from public.votes where id = p_vote for update;
  if not found then raise exception 'vote_not_found'; end if;
  if not exists (select 1 from public.group_members where group_id = v.group_id and user_id = v_uid and status = 'active') then
    raise exception 'vote_not_found';
  end if;
  if v.status <> 'open' or public.app_now() >= v.closes_at then raise exception 'vote_closed'; end if;

  insert into public.vote_ballots (vote_id, user_id, yes) values (p_vote, v_uid, p_yes)
  on conflict (vote_id, user_id) do update set yes = excluded.yes;                         -- you may change your mind until it closes
  return public.evaluate_vote(p_vote, false);
end $$;

-- Scheduled every minute: close every vote whose 24 hours are up.
create function public.close_votes() returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0; v_res text;
begin
  for r in select id from public.votes where status = 'open' and closes_at <= public.app_now() order by closes_at loop
    begin
      v_res := public.evaluate_vote(r.id, true);
      if v_res not in ('open', 'skipped') then n := n + 1; end if;
    exception when others then
      insert into public.sync_log (kind, ok, detail) values ('close_vote', false, r.id || ': ' || sqlerrm);
    end;
  end loop;
  return n;
end $$;

revoke all on function public.vote_quorum(integer), public.apply_group_reset(public.votes), public.evaluate_vote(uuid, boolean),
  public.call_vote(uuid, text), public.cast_vote(uuid, boolean), public.close_votes() from public, anon, authenticated;
grant execute on function public.call_vote(uuid, text), public.cast_vote(uuid, boolean) to authenticated;

-- ───────────────────────── Stronger books: seasons and votes ─────────────────────────
create function public.check_season_integrity()
returns table (check_name text, group_id uuid, detail text)
language sql stable as $$
  -- every group has exactly one running season and it is the group's current one
  select 'season_not_current'::text, g.id, 'group ' || g.id
    from public.groups g
   where (select count(*) from public.seasons s where s.group_id = g.id and s.ended_at is null) <> 1
      or not exists (select 1 from public.seasons s where s.id = g.current_season_id and s.ended_at is null)
  union all
  -- a finished vote has a result and a time; a running one has neither
  select 'vote_state_mismatch', v.group_id, 'vote ' || v.id
    from public.votes v
   where (v.status = 'open') <> (v.decided_at is null)
  union all
  -- no group may have unsettled bets or open offers older than its running season's start (a reset clears them)
  select 'reset_left_leftovers', o.group_id, 'offer ' || o.id
    from public.offers o join public.groups g on g.id = o.group_id
    join public.seasons s on s.id = g.current_season_id
   where o.status = 'open' and o.season_id <> g.current_season_id
  union all
  select 'reset_left_leftovers', b.group_id, 'bet ' || b.id
    from public.bets b join public.groups g on g.id = b.group_id
   where b.status = 'pending' and b.season_id <> g.current_season_id;
$$;
revoke all on function public.check_season_integrity() from public, anon, authenticated;

-- A group reset voids bets whose game has not finished, so "void" must not require a void market.
create or replace function public.check_betting_integrity()
returns table (check_name text, group_id uuid, detail text)
language sql stable as $$
  -- every share of every offer is open, cancelled, or taken — none lost or invented
  select 'offer_shares_mismatch'::text, o.group_id, 'offer ' || o.id
    from public.offers o
    left join (select offer_id, sum(shares) as s from public.bets group by offer_id) b on b.offer_id = o.id
   where o.shares_open + o.shares_cancelled + coalesce(b.s, 0) <> o.shares_total
  union all
  select 'offer_status_mismatch', o.group_id, 'offer ' || o.id
    from public.offers o
   where (o.status = 'open') <> (o.shares_open > 0)
      or (o.status = 'filled' and o.shares_cancelled > 0)
      or (o.status = 'cancelled' and o.shares_cancelled = 0)
  union all
  -- the two stakes of every bet add up to exactly the pot
  select 'bet_pot_mismatch', b.group_id, 'bet ' || b.id
    from public.bets b where b.maker_stake + b.taker_stake <> b.shares::bigint * 100
  union all
  -- coins in escrow = cost of open offers + stakes of unsettled bets, for every member
  select 'escrow_mismatch', m.group_id,
         'user ' || m.user_id || ' escrow ' || m.escrow || ' vs expected ' || coalesce(e.expected, 0)
    from public.group_members m
    left join (
      select x.group_id, x.uid, sum(x.amt) as expected
        from (select group_id, maker_id as uid, shares_open::bigint * price_cents as amt from public.offers where status = 'open'
              union all select group_id, maker_id, maker_stake from public.bets where status = 'pending'
              union all select group_id, taker_id, taker_stake from public.bets where status = 'pending') x
       group by x.group_id, x.uid) e
      on e.group_id = m.group_id and e.uid = m.user_id
   where m.escrow <> coalesce(e.expected, 0)
  union all
  -- a decided bet's winner must match the market's final result (a VOID bet is always fine: it may come from a
  -- 50/50 market or from a group reset that voided it before the game finished)
  select 'bet_result_mismatch', b.group_id, 'bet ' || b.id || ' is ' || b.status || ' but market is ' || m.resolution
    from public.bets b join public.markets m on m.id = b.market_id
   where b.status in ('won_maker', 'won_taker')
     and not ((b.status = 'won_maker' and m.resolution = 'outcome_' || b.maker_outcome)
           or (b.status = 'won_taker' and m.resolution = 'outcome_' || (1 - b.maker_outcome)))
  union all
  -- ...and each side must have been paid exactly what the result says (winner: whole pot, void: own stake back)
  select 'bet_payout_mismatch', b.group_id, 'bet ' || b.id || ' maker got ' || p.maker_got || ' taker got ' || p.taker_got
    from public.bets b
    cross join lateral (
      select coalesce(sum(l.delta) filter (where l.user_id = b.maker_id), 0) as maker_got,
             coalesce(sum(l.delta) filter (where l.user_id = b.taker_id), 0) as taker_got
        from public.ledger l
       where l.ref_type = 'bet' and l.ref_id = b.id and l.bucket = 'available' and l.kind in ('bet_payout', 'bet_void')) p
   where (p.maker_got, p.taker_got) is distinct from (
           case b.status when 'won_maker' then b.maker_stake + b.taker_stake when 'void' then b.maker_stake else 0 end,
           case b.status when 'won_taker' then b.maker_stake + b.taker_stake when 'void' then b.taker_stake else 0 end)
  union all
  -- win/loss records equal the count of settled bets
  select 'record_mismatch', null::uuid, 'user ' || pr.id || ' record ' || pr.lifetime_wins || '-' || pr.lifetime_losses
    from public.profiles pr
   where pr.lifetime_wins <> (select count(*) from public.bets b
                               where (b.status = 'won_maker' and b.maker_id = pr.id) or (b.status = 'won_taker' and b.taker_id = pr.id))
      or pr.lifetime_losses <> (select count(*) from public.bets b
                               where (b.status = 'won_maker' and b.taker_id = pr.id) or (b.status = 'won_taker' and b.maker_id = pr.id));
$$;
