-- Fade — Milestone 1: foundation schema.
-- Usernames are stored lowercase (enforced by a CHECK); the app lowercases before saving.
-- People, groups, members, seasons, the append-only coin ledger, integrity checks, and RLS.
-- All amounts are bigint HUNDREDTHS of a coin (100 = 1 coin).

-- ───────────────────────── People ─────────────────────────
create table public.profiles (
  id                    uuid primary key references auth.users (id),
  username              text unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name          text not null default '',
  avatar_emoji          text not null default '🙂',
  price_format          text not null default 'cents' check (price_format in ('cents', 'american')),
  lifetime_closed_profit bigint not null default 0,  -- profit from finished seasons / groups left
  lifetime_wins         integer not null default 0,
  lifetime_losses       integer not null default 0,
  banned                boolean not null default false,
  deleted_at            timestamptz,
  created_at            timestamptz not null default now()
);

-- ───────────────────────── Groups ─────────────────────────
create table public.groups (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(name) between 1 and 60),
  invite_code      text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_by       uuid not null references public.profiles (id),
  starting_balance bigint not null default 10000 check (starting_balance > 0),   -- 100 coins
  buyback_policy   text not null default 'unlimited' check (buyback_policy in ('unlimited', 'weekly', 'vote')),
  buybacks_per_week integer check (buybacks_per_week is null or buybacks_per_week > 0),
  buyback_amount   bigint not null default 10000 check (buyback_amount > 0),
  current_season_id uuid,
  created_at       timestamptz not null default now(),
  check ((buyback_policy = 'weekly') = (buybacks_per_week is not null))
);

create table public.seasons (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  number     integer not null check (number > 0),
  started_at timestamptz not null default now(),
  ended_at   timestamptz,
  unique (group_id, number)
);
alter table public.groups
  add constraint groups_current_season_fk foreign key (current_season_id) references public.seasons (id);

create table public.group_members (
  group_id      uuid not null references public.groups (id) on delete cascade,
  user_id       uuid not null references public.profiles (id),
  role          text not null default 'member' check (role in ('owner', 'member')),
  status        text not null default 'active' check (status in ('active', 'left')),
  joined_at     timestamptz not null default now(),
  -- Cached from the ledger by a trigger; clients can never write these.
  available     bigint not null default 0 check (available >= 0),
  escrow        bigint not null default 0 check (escrow >= 0),
  buyback_count integer not null default 0 check (buyback_count >= 0),
  buyback_coins bigint not null default 0 check (buyback_coins >= 0),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

create table public.season_standings (
  season_id     uuid not null references public.seasons (id) on delete cascade,
  user_id       uuid not null references public.profiles (id),
  final_balance bigint not null,
  buyback_count integer not null,
  buyback_coins bigint not null,
  net_profit    bigint not null,
  primary key (season_id, user_id)
);

-- ───────────────────────── Ledger (append-only) ─────────────────────────
-- kind classes:
--   mint  (creates coins):  grant, buyback
--   burn  (destroys coins): season_burn, leave_burn, delete_burn
--   moves (net zero per tx): escrow_lock, escrow_release, bet_win, bet_void, bet_payout, bet_stake
create table public.ledger (
  id         bigint generated always as identity primary key,
  tx_id      uuid not null,
  group_id   uuid not null references public.groups (id),
  user_id    uuid not null references public.profiles (id),
  bucket     text not null check (bucket in ('available', 'escrow')),
  delta      bigint not null check (delta <> 0),
  kind       text not null check (kind in (
               'grant', 'buyback',
               'season_burn', 'leave_burn', 'delete_burn',
               'escrow_lock', 'escrow_release', 'bet_stake', 'bet_payout', 'bet_void')),
  ref_type   text,
  ref_id     uuid,
  created_at timestamptz not null default now()
);
create index ledger_group_idx on public.ledger (group_id);
create index ledger_user_idx  on public.ledger (group_id, user_id);
create index ledger_tx_idx    on public.ledger (tx_id);

-- No UPDATE, DELETE or TRUNCATE — for every role, including the owner.
create function public.ledger_forbid_change() returns trigger
language plpgsql as $$
begin
  raise exception 'ledger is append-only (% not allowed)', tg_op;
end $$;
create trigger ledger_no_update_delete before update or delete on public.ledger
  for each row execute function public.ledger_forbid_change();
create trigger ledger_no_truncate before truncate on public.ledger
  for each statement execute function public.ledger_forbid_change();

-- Keep the cached member balances in step with the ledger — the ONLY way they change.
create function public.ledger_apply_to_member() returns trigger
language plpgsql as $$
begin
  update public.group_members
     set available     = available + case when new.bucket = 'available' then new.delta else 0 end,
         escrow        = escrow    + case when new.bucket = 'escrow'    then new.delta else 0 end,
         buyback_count = buyback_count + case when new.kind = 'buyback' then 1 else 0 end,
         buyback_coins = buyback_coins + case when new.kind = 'buyback' then new.delta else 0 end
   where group_id = new.group_id and user_id = new.user_id;
  if not found then
    raise exception 'ledger row for non-member (group %, user %)', new.group_id, new.user_id;
  end if;
  return null;
end $$;
create trigger ledger_apply after insert on public.ledger
  for each row execute function public.ledger_apply_to_member();

-- Internal helper used by every server-side coin function (never exposed to clients).
create function public.ledger_post(
  p_tx uuid, p_group uuid, p_user uuid, p_bucket text, p_delta bigint,
  p_kind text, p_ref_type text default null, p_ref_id uuid default null)
returns void language sql as $$
  insert into public.ledger (tx_id, group_id, user_id, bucket, delta, kind, ref_type, ref_id)
  values (p_tx, p_group, p_user, p_bucket, p_delta, p_kind, p_ref_type, p_ref_id);
$$;

-- ───────────────────────── Integrity checks ─────────────────────────
-- Each returns rows ONLY for violations. Zero rows everywhere = coins balance out.

create function public.check_ledger_integrity()
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
   where m.available <> coalesce(s.av, 0) or m.escrow <> coalesce(s.es, 0);
$$;

-- ───────────────────────── Row Level Security ─────────────────────────
create function public.is_group_member(p_group uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members
                  where group_id = p_group and user_id = auth.uid() and status = 'active');
$$;

create function public.shares_group_with(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members a
                   join public.group_members b on b.group_id = a.group_id
                  where a.user_id = auth.uid() and a.status = 'active'
                    and b.user_id = p_user and b.status = 'active');
$$;

alter table public.profiles         enable row level security;
alter table public.groups           enable row level security;
alter table public.seasons          enable row level security;
alter table public.group_members    enable row level security;
alter table public.season_standings enable row level security;
alter table public.ledger           enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_group_with(id));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy groups_select on public.groups for select to authenticated
  using (public.is_group_member(id));
create policy seasons_select on public.seasons for select to authenticated
  using (public.is_group_member(group_id));
create policy members_select on public.group_members for select to authenticated
  using (public.is_group_member(group_id));
create policy standings_select on public.season_standings for select to authenticated
  using (exists (select 1 from public.seasons s where s.id = season_id and public.is_group_member(s.group_id)));
-- A member sees only their own ledger rows (group-wide history comes via the feed).
create policy ledger_select_own on public.ledger for select to authenticated
  using (user_id = auth.uid());

-- Table privileges: clients may read; the only client write is editing their own display settings.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
-- Future functions are private by default; each migration grants execute explicitly where clients need it.
alter default privileges in schema public revoke all on functions from public, anon, authenticated;
grant select on public.profiles, public.groups, public.seasons, public.group_members,
                public.season_standings, public.ledger to authenticated;
grant update (display_name, avatar_emoji, price_format) on public.profiles to authenticated;
grant execute on function public.is_group_member(uuid), public.shares_group_with(uuid) to authenticated;
