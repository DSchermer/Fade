-- Fade — Milestone 10: friends.
--   • Send a request by exact username; the other person accepts or declines.
--   • Fade suggests people you share a group with.
--   • The friends leaderboard ranks you and your accepted friends by GLOBAL lifetime score.
-- Privacy: nobody can browse users. You can only look someone up by typing their exact username, and a person who has
-- blocked you (or whom you blocked) looks exactly like a username that doesn't exist.

create table public.friendships (
  requester    uuid not null references public.profiles (id),
  addressee    uuid not null references public.profiles (id),
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  primary key (requester, addressee),
  check (requester <> addressee)
);
-- one relationship per pair of people, whichever way round it was requested
create unique index friendships_pair_idx on public.friendships (least(requester, addressee), greatest(requester, addressee));
create index friendships_addressee_idx on public.friendships (addressee);
alter table public.friendships enable row level security;
create policy friendships_own on public.friendships for select to authenticated using (requester = auth.uid() or addressee = auth.uid());
grant select on public.friendships to authenticated;

-- A person who can't be found or requested: missing, deleted, banned, or in a block with me.
create function public.requestable_user(p_username text) returns uuid
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p
   where p.username = lower(btrim(coalesce(p_username, ''))) and not p.banned and p.deleted_at is null and p.id <> auth.uid()
     and not exists (select 1 from public.blocks b where (b.blocker = auth.uid() and b.blocked = p.id) or (b.blocker = p.id and b.blocked = auth.uid()));
$$;

create function public.send_friend_request(p_username text) returns text
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_target uuid; r public.friendships%rowtype; v_pending integer;
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if exists (select 1 from public.profiles where id = v_uid and (banned or deleted_at is not null)) then raise exception 'account_disabled'; end if;
  if lower(btrim(coalesce(p_username, ''))) = (select username from public.profiles where id = v_uid) then raise exception 'invalid_target'; end if;
  v_target := public.requestable_user(p_username);
  if v_target is null then raise exception 'user_not_found'; end if;

  select * into r from public.friendships
   where (requester = v_uid and addressee = v_target) or (requester = v_target and addressee = v_uid) for update;
  if found then
    if r.status = 'accepted' then raise exception 'already_friends'; end if;
    if r.requester = v_uid then raise exception 'request_pending'; end if;
    -- they had already asked me: asking back means yes
    update public.friendships set status = 'accepted', responded_at = now() where requester = r.requester and addressee = r.addressee;
    return 'accepted';
  end if;

  select count(*) into v_pending from public.friendships where requester = v_uid and status = 'pending';
  if v_pending >= 50 then raise exception 'too_many_requests'; end if;
  insert into public.friendships (requester, addressee) values (v_uid, v_target);
  return 'sent';
end $$;

create function public.respond_friend_request(p_requester uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_accept is null then raise exception 'invalid_target'; end if;
  if not exists (select 1 from public.friendships where requester = p_requester and addressee = auth.uid() and status = 'pending') then
    raise exception 'request_not_found';
  end if;
  if p_accept then
    update public.friendships set status = 'accepted', responded_at = now() where requester = p_requester and addressee = auth.uid();
  else
    delete from public.friendships where requester = p_requester and addressee = auth.uid();
  end if;
end $$;

create function public.cancel_friend_request(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from public.friendships where requester = auth.uid() and addressee = p_user and status = 'pending';
end $$;

create function public.remove_friend(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from public.friendships
   where status = 'accepted' and ((requester = auth.uid() and addressee = p_user) or (requester = p_user and addressee = auth.uid()));
end $$;

-- Blocking someone also ends any friendship or request between you.
create or replace function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_user is null or p_user = auth.uid() then raise exception 'invalid_target'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'invalid_target'; end if;
  insert into public.blocks (blocker, blocked) values (auth.uid(), p_user) on conflict do nothing;
  delete from public.friendships
   where (requester = auth.uid() and addressee = p_user) or (requester = p_user and addressee = auth.uid());
end $$;

-- Requests waiting on me (incoming) and requests I sent (outgoing), with names.
create function public.my_friend_requests() returns table (user_id uuid, username text, direction text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select f.requester, p.username, 'incoming', f.created_at
    from public.friendships f join public.profiles p on p.id = f.requester
   where f.addressee = auth.uid() and f.status = 'pending' and not p.banned and p.deleted_at is null
     and public.content_visible_to_me(f.requester)
  union all
  select f.addressee, p.username, 'outgoing', f.created_at
    from public.friendships f join public.profiles p on p.id = f.addressee
   where f.requester = auth.uid() and f.status = 'pending' and p.deleted_at is null
  order by 4 desc;
$$;

-- Me + my accepted friends, ranked by global lifetime score.
-- Score = profit from finished seasons and groups left + live profit in every current group (buybacks count against you).
create function public.friend_scores() returns table (user_id uuid, username text, score bigint, wins integer, losses integer, is_me boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.username,
         (p.lifetime_closed_profit + coalesce((select sum(m.available + m.escrow - m.granted - m.buyback_coins)
                                                 from public.group_members m where m.user_id = p.id and m.status = 'active'), 0))::bigint,
         p.lifetime_wins, p.lifetime_losses, p.id = auth.uid()
    from public.profiles p
   where auth.uid() is not null and p.deleted_at is null and not p.banned
     and (p.id = auth.uid() or exists (select 1 from public.friendships f where f.status = 'accepted'
                                          and ((f.requester = auth.uid() and f.addressee = p.id) or (f.requester = p.id and f.addressee = auth.uid()))))
   order by 3 desc, 2;
$$;

-- People I share at least one current group with, who aren't already friends, pending, blocked or banned.
create function public.friend_suggestions() returns table (user_id uuid, username text, shared_groups integer)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, count(*)::integer
    from public.group_members mine
    join public.group_members theirs on theirs.group_id = mine.group_id and theirs.status = 'active' and theirs.user_id <> mine.user_id
    join public.profiles p on p.id = theirs.user_id
   where mine.user_id = auth.uid() and mine.status = 'active' and p.deleted_at is null and not p.banned and p.username is not null
     and not exists (select 1 from public.friendships f where (f.requester = auth.uid() and f.addressee = p.id) or (f.requester = p.id and f.addressee = auth.uid()))
     and public.content_visible_to_me(p.id)
     and not exists (select 1 from public.blocks b where b.blocker = auth.uid() and b.blocked = p.id)
   group by p.id, p.username
   order by 3 desc, 2
   limit 30;
$$;

revoke all on function public.requestable_user(text), public.send_friend_request(text), public.respond_friend_request(uuid, boolean),
  public.cancel_friend_request(uuid), public.remove_friend(uuid), public.my_friend_requests(), public.friend_scores(), public.friend_suggestions(),
  public.block_user(uuid) from public, anon, authenticated;
grant execute on function public.send_friend_request(text), public.respond_friend_request(uuid, boolean), public.cancel_friend_request(uuid),
  public.remove_friend(uuid), public.my_friend_requests(), public.friend_scores(), public.friend_suggestions(), public.block_user(uuid) to authenticated;
