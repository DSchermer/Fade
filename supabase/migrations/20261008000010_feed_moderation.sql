-- Fade — Milestone 9: the group feed, reactions, comments, and the safety tools Apple requires for user-generated content:
--   • a basic objectionable-content filter (comments, usernames, group names)
--   • report content / users, block users, mute users
--   • a way for the OWNER (you, in the Supabase dashboard) to act on reports: hide content, ban users, resolve reports.
--
-- Feed items are written automatically by triggers when things happen (offer posted, offer taken, bet settled, buyback,
-- vote called / decided), so no existing money function had to change.

-- ───────────────────────── Objectionable-content filter ─────────────────────────
-- STARTER list. It deliberately contains common profanity and threats only; add slurs and anything else your group
-- shouldn't see in Supabase → Table Editor → banned_terms (one lowercase word or phrase per row). Matching is on whole
-- words, after lower-casing, swapping look-alike symbols (@ $ 0 1 3 5 7 !), and squeezing stretched letters.
create table public.banned_terms (term text primary key check (term = lower(term) and char_length(term) >= 2));
alter table public.banned_terms enable row level security;          -- no policy, no grant: clients can't read the list
insert into public.banned_terms (term) values
  ('fuck'), ('fucker'), ('fucking'), ('motherfucker'), ('shit'), ('bullshit'), ('bitch'), ('bastard'), ('asshole'),
  ('dickhead'), ('cunt'), ('whore'), ('slut'), ('twat'), ('wanker'), ('prick'),
  ('kill yourself'), ('kys'), ('go die'), ('hang yourself'), ('rapist'), ('rape you'), ('nazi'), ('heil hitler'),
  ('i will kill you'), ('im going to kill you'), ('porn'), ('nudes');

create function public.normalize_text(p_text text) returns text
language sql immutable as $$
  select regexp_replace(                                          -- stretched letters: "fuuuck" → "fuck"
           translate(lower(coalesce(p_text, '')), '@$0134578!|', 'asoieastbil'),
           '(.)\1{2,}', '\1', 'g');
$$;

create function public.contains_banned_term(p_text text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.banned_terms t
     where public.normalize_text(p_text) ~ ('(^|[^a-z0-9])' || regexp_replace(t.term, '([^a-z0-9 ])', '\\\1', 'g') || '([^a-z0-9]|$)'));
$$;

create function public.reject_banned_profile_text() returns trigger
language plpgsql as $$
begin
  if public.contains_banned_term(new.username) or public.contains_banned_term(new.display_name) then
    raise exception 'content_not_allowed';
  end if;
  return new;
end $$;
create function public.reject_banned_group_text() returns trigger
language plpgsql as $$
begin
  if public.contains_banned_term(new.name) then
    raise exception 'content_not_allowed';
  end if;
  return new;
end $$;
create trigger profiles_no_banned_text before insert or update of username, display_name on public.profiles
  for each row execute function public.reject_banned_profile_text();
create trigger groups_no_banned_text before insert or update of name on public.groups
  for each row execute function public.reject_banned_group_text();

-- ───────────────────────── Blocks and mutes ─────────────────────────
-- BLOCK: you and that person no longer see each other's comments or feed activity (and, in Milestone 10, can't friend).
-- MUTE:  you stop seeing THEIR comments and feed activity; they still see yours.
-- Neither changes the betting economy: to avoid someone's offers entirely, leave the group.
create table public.blocks (
  blocker uuid not null references public.profiles (id),
  blocked uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (blocker, blocked), check (blocker <> blocked));
create table public.mutes (
  muter uuid not null references public.profiles (id),
  muted uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (muter, muted), check (muter <> muted));
alter table public.blocks enable row level security;
alter table public.mutes  enable row level security;
create policy blocks_own on public.blocks for select to authenticated using (blocker = auth.uid());
create policy mutes_own  on public.mutes  for select to authenticated using (muter = auth.uid());
grant select on public.blocks, public.mutes to authenticated;

-- "can I see content by this person?" — one place for the rule.
create function public.content_visible_to_me(p_author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_author is null or (
    not exists (select 1 from public.blocks b where (b.blocker = auth.uid() and b.blocked = p_author) or (b.blocker = p_author and b.blocked = auth.uid()))
    and not exists (select 1 from public.mutes m where m.muter = auth.uid() and m.muted = p_author));
$$;

create function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_user is null or p_user = auth.uid() then raise exception 'invalid_target'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'invalid_target'; end if;
  insert into public.blocks (blocker, blocked) values (auth.uid(), p_user) on conflict do nothing;
end $$;
create function public.unblock_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from public.blocks where blocker = auth.uid() and blocked = p_user;
end $$;
create function public.mute_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_user is null or p_user = auth.uid() then raise exception 'invalid_target'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'invalid_target'; end if;
  insert into public.mutes (muter, muted) values (auth.uid(), p_user) on conflict do nothing;
end $$;
create function public.unmute_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from public.mutes where muter = auth.uid() and muted = p_user;
end $$;

-- Names for the "Blocked & muted" settings screen (works even after you no longer share a group).
create function public.my_blocked_and_muted() returns table (user_id uuid, username text, kind text)
language sql stable security definer set search_path = public as $$
  select b.blocked, p.username, 'blocked' from public.blocks b join public.profiles p on p.id = b.blocked where b.blocker = auth.uid()
  union all
  select m.muted, p.username, 'muted' from public.mutes m join public.profiles p on p.id = m.muted where m.muter = auth.uid();
$$;

-- ───────────────────────── Feed ─────────────────────────
create table public.feed_items (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id),
  kind       text not null check (kind in ('offer_posted', 'offer_taken', 'bet_settled', 'buyback', 'vote_called', 'vote_result')),
  actor_id   uuid references public.profiles (id),
  ref_type   text,
  ref_id     uuid,
  payload    jsonb not null default '{}',
  hidden     boolean not null default false,                      -- set by the owner's moderation tools
  created_at timestamptz not null default now()
);
create index feed_group_idx on public.feed_items (group_id, created_at desc);
create index feed_ref_idx   on public.feed_items (ref_type, ref_id);

create table public.reactions (
  feed_item_id uuid not null references public.feed_items (id) on delete cascade,
  user_id      uuid not null references public.profiles (id),
  emoji        text not null check (emoji in ('🔥', '😂', '👍', '👎', '😮', '💀', '🎯', '💰')),
  created_at   timestamptz not null default now(),
  primary key (feed_item_id, user_id, emoji)
);

create table public.comments (
  id           uuid primary key default gen_random_uuid(),
  feed_item_id uuid not null references public.feed_items (id) on delete cascade,
  group_id     uuid not null references public.groups (id),
  user_id      uuid not null references public.profiles (id),
  body         text not null check (char_length(body) between 1 and 500),
  hidden       boolean not null default false,
  created_at   timestamptz not null default now()
);
create index comments_item_idx on public.comments (feed_item_id, created_at);
create index comments_user_idx on public.comments (user_id, created_at desc);

alter table public.feed_items enable row level security;
alter table public.reactions  enable row level security;
alter table public.comments   enable row level security;
create policy feed_select on public.feed_items for select to authenticated using (public.is_group_member(group_id) and not hidden);
create policy reactions_select on public.reactions for select to authenticated
  using (exists (select 1 from public.feed_items f where f.id = feed_item_id and not f.hidden and public.is_group_member(f.group_id)));
create policy comments_select on public.comments for select to authenticated using (public.is_group_member(group_id) and not hidden);
grant select on public.feed_items, public.reactions, public.comments to authenticated;

-- A readable name for a side of a market ("Celtics to win", "Cavaliers -1.5", "Over 220.5").
create function public.market_side_label(m public.markets, p_index integer) returns text
language sql immutable as $$
  select case
    when m.market_type = 'spreads' and m.line is not null
      then m.outcomes[p_index + 1] || ' ' || to_char(case when p_index = 0 then m.line else -m.line end, 'FMS999990.0')
    when m.market_type = 'totals' and m.line is not null
      then m.outcomes[p_index + 1] || ' ' || trim(trailing '.' from trim(trailing '0' from to_char(m.line, 'FM999990.0')))
    else m.outcomes[p_index + 1] || ' to win'
  end;
$$;

create function public.uname(p_user uuid) returns text
language sql stable security definer set search_path = public as $$ select username from public.profiles where id = p_user $$;

create function public.feed_on_offer() returns trigger
language plpgsql security definer set search_path = public as $$
declare mk public.markets%rowtype;
begin
  select * into mk from public.markets where id = new.market_id;
  insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
  values (new.group_id, 'offer_posted', new.maker_id, 'offer', new.id,
          jsonb_build_object('maker', public.uname(new.maker_id), 'event_title', mk.event_title, 'league', mk.league,
                             'side', public.market_side_label(mk, new.outcome), 'price_cents', new.price_cents,
                             'shares', new.shares_total, 'game_start', mk.game_start), public.app_now());
  return null;
end $$;
create trigger feed_offer after insert on public.offers for each row execute function public.feed_on_offer();

create function public.feed_on_bet() returns trigger
language plpgsql security definer set search_path = public as $$
declare mk public.markets%rowtype;
begin
  select * into mk from public.markets where id = new.market_id;
  insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
  values (new.group_id, 'offer_taken', new.taker_id, 'bet', new.id,
          jsonb_build_object('maker', public.uname(new.maker_id), 'taker', public.uname(new.taker_id),
                             'event_title', mk.event_title, 'league', mk.league,
                             'maker_side', public.market_side_label(mk, new.maker_outcome),
                             'taker_side', public.market_side_label(mk, 1 - new.maker_outcome),
                             'price_cents', new.price_cents, 'shares', new.shares,
                             'maker_stake', new.maker_stake, 'taker_stake', new.taker_stake), public.app_now());
  return null;
end $$;
create trigger feed_bet after insert on public.bets for each row execute function public.feed_on_bet();

create function public.feed_on_bet_settled() returns trigger
language plpgsql security definer set search_path = public as $$
declare mk public.markets%rowtype; v_winner uuid; v_loser uuid; v_win bigint;
begin
  select * into mk from public.markets where id = new.market_id;
  if new.status = 'void' then
    insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
    values (new.group_id, 'bet_settled', null, 'bet', new.id,
            jsonb_build_object('result', 'void', 'maker', public.uname(new.maker_id), 'taker', public.uname(new.taker_id),
                               'event_title', mk.event_title, 'shares', new.shares), public.app_now());
  else
    v_winner := case new.status when 'won_maker' then new.maker_id else new.taker_id end;
    v_loser  := case new.status when 'won_maker' then new.taker_id else new.maker_id end;
    v_win    := case new.status when 'won_maker' then new.taker_stake else new.maker_stake end;     -- what the winner gains
    insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
    values (new.group_id, 'bet_settled', v_winner, 'bet', new.id,
            jsonb_build_object('result', 'decided', 'winner', public.uname(v_winner), 'loser', public.uname(v_loser),
                               'winner_side', public.market_side_label(mk, case new.status when 'won_maker' then new.maker_outcome else 1 - new.maker_outcome end),
                               'event_title', mk.event_title, 'shares', new.shares, 'gain', v_win), public.app_now());
  end if;
  return null;
end $$;
create trigger feed_bet_settled after update of status on public.bets
  for each row when (old.status = 'pending' and new.status <> 'pending') execute function public.feed_on_bet_settled();

create function public.feed_on_buyback() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
  values (new.group_id, 'buyback', new.user_id, 'buyback', new.id,
          jsonb_build_object('who', public.uname(new.user_id), 'amount', new.amount, 'via', new.via), public.app_now());
  return null;
end $$;
create trigger feed_buyback after insert on public.buybacks for each row execute function public.feed_on_buyback();

create function public.feed_on_vote() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
    values (new.group_id, 'vote_called', new.called_by, 'vote', new.id,
            jsonb_build_object('vote_kind', new.kind, 'caller', public.uname(new.called_by), 'subject', public.uname(new.subject_id),
                               'closes_at', new.closes_at), public.app_now());
  else
    insert into public.feed_items (group_id, kind, actor_id, ref_type, ref_id, payload, created_at)
    values (new.group_id, 'vote_result', null, 'vote', new.id,
            jsonb_build_object('vote_kind', new.kind, 'subject', public.uname(new.subject_id), 'status', new.status,
                               'yes', new.yes_count, 'no', new.no_count, 'note', new.decision_note), public.app_now());
  end if;
  return null;
end $$;
create trigger feed_vote_called after insert on public.votes for each row execute function public.feed_on_vote();
create trigger feed_vote_result after update of status on public.votes
  for each row when (old.status = 'open' and new.status <> 'open') execute function public.feed_on_vote();

-- The feed as the app reads it: hides anything from people I've blocked / muted (or who blocked me) and moderated items.
create view public.feed_listing with (security_invoker = true) as
  select f.id, f.group_id, f.kind, f.actor_id, p.username as actor_username, f.ref_type, f.ref_id, f.payload, f.created_at,
         (select count(*) from public.comments c where c.feed_item_id = f.id and not c.hidden and public.content_visible_to_me(c.user_id))::integer as comment_count,
         coalesce((select jsonb_object_agg(r.emoji, r.n) from
                    (select emoji, count(*) as n from public.reactions where feed_item_id = f.id group by emoji) r), '{}'::jsonb) as reactions,
         coalesce((select array_agg(emoji order by emoji) from public.reactions where feed_item_id = f.id and user_id = auth.uid()), '{}'::text[]) as my_reactions
    from public.feed_items f
    left join public.profiles p on p.id = f.actor_id
   where public.content_visible_to_me(f.actor_id);
grant select on public.feed_listing to authenticated;

create view public.comment_listing with (security_invoker = true) as
  select c.id, c.feed_item_id, c.group_id, c.user_id, p.username, c.body, c.created_at
    from public.comments c join public.profiles p on p.id = c.user_id
   where public.content_visible_to_me(c.user_id);
grant select on public.comment_listing to authenticated;

-- ───────────────────────── Reacting and commenting ─────────────────────────
create function public.assert_active_member_of_item(p_item uuid) returns public.feed_items
language plpgsql security definer set search_path = public as $$
declare f public.feed_items%rowtype;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  select * into f from public.feed_items where id = p_item and not hidden;
  if not found or not exists (select 1 from public.group_members where group_id = f.group_id and user_id = auth.uid() and status = 'active') then
    raise exception 'item_not_found';
  end if;
  if exists (select 1 from public.profiles where id = auth.uid() and (banned or deleted_at is not null)) then raise exception 'account_disabled'; end if;
  return f;
end $$;

-- Tap an emoji once to add it, tap again to remove it. Returns true if it is now on.
create function public.toggle_reaction(p_item uuid, p_emoji text) returns boolean
language plpgsql security definer set search_path = public as $$
declare f public.feed_items%rowtype;
begin
  f := public.assert_active_member_of_item(p_item);
  if p_emoji is null or p_emoji not in ('🔥', '😂', '👍', '👎', '😮', '💀', '🎯', '💰') then raise exception 'invalid_emoji'; end if;
  if exists (select 1 from public.reactions where feed_item_id = p_item and user_id = auth.uid() and emoji = p_emoji) then
    delete from public.reactions where feed_item_id = p_item and user_id = auth.uid() and emoji = p_emoji;
    return false;
  end if;
  insert into public.reactions (feed_item_id, user_id, emoji) values (p_item, auth.uid(), p_emoji) on conflict do nothing;
  return true;
end $$;

create function public.add_comment(p_item uuid, p_body text) returns uuid
language plpgsql security definer set search_path = public as $$
declare f public.feed_items%rowtype; v_body text := btrim(coalesce(p_body, '')); v_id uuid;
begin
  f := public.assert_active_member_of_item(p_item);
  if char_length(v_body) not between 1 and 500 then raise exception 'invalid_comment'; end if;
  if public.contains_banned_term(v_body) then raise exception 'content_not_allowed'; end if;
  if (select count(*) from public.comments where user_id = auth.uid() and created_at > now() - interval '1 minute') >= 10 then
    raise exception 'slow_down';
  end if;
  insert into public.comments (feed_item_id, group_id, user_id, body) values (p_item, f.group_id, auth.uid(), v_body) returning id into v_id;
  return v_id;
end $$;

create function public.delete_my_comment(p_comment uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from public.comments where id = p_comment and user_id = auth.uid();
end $$;

-- ───────────────────────── Reports ─────────────────────────
create table public.reports (
  id            uuid primary key default gen_random_uuid(),
  reporter_id   uuid not null references public.profiles (id),
  target_type   text not null check (target_type in ('comment', 'user', 'feed_item')),
  target_id     uuid not null,
  group_id      uuid references public.groups (id),
  reason        text not null check (reason in ('spam', 'harassment', 'hate', 'sexual', 'violence', 'self_harm', 'other')),
  details       text check (char_length(details) <= 500),
  status        text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewer_note text,
  unique (reporter_id, target_type, target_id)
);
create index reports_open_idx on public.reports (created_at) where status = 'open';
alter table public.reports enable row level security;         -- no policy, no grant: only you (dashboard) can read reports

create function public.report_content(p_type text, p_id uuid, p_reason text, p_details text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_group uuid; v_target_user uuid; v_id uuid;
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_type not in ('comment', 'user', 'feed_item') then raise exception 'invalid_report'; end if;
  if p_reason is null or p_reason not in ('spam', 'harassment', 'hate', 'sexual', 'violence', 'self_harm', 'other') then raise exception 'invalid_report'; end if;

  if p_type = 'comment' then
    select group_id, user_id into v_group, v_target_user from public.comments where id = p_id and not hidden;
  elsif p_type = 'feed_item' then
    select group_id, actor_id into v_group, v_target_user from public.feed_items where id = p_id and not hidden;
  else
    v_target_user := p_id;
    select gm1.group_id into v_group from public.group_members gm1 join public.group_members gm2 on gm2.group_id = gm1.group_id
     where gm1.user_id = v_uid and gm1.status = 'active' and gm2.user_id = p_id and gm2.status = 'active' limit 1;
  end if;
  if v_group is null or not exists (select 1 from public.group_members where group_id = v_group and user_id = v_uid and status = 'active') then
    raise exception 'report_target_not_found';
  end if;
  if v_target_user = v_uid then raise exception 'invalid_report'; end if;

  insert into public.reports (reporter_id, target_type, target_id, group_id, reason, details)
  values (v_uid, p_type, p_id, v_group, p_reason, left(p_details, 500))
  on conflict (reporter_id, target_type, target_id) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.reports where reporter_id = v_uid and target_type = p_type and target_id = p_id;
  end if;
  return v_id;
end $$;

-- ───────────────────────── The owner's moderation tools (SQL editor only) ─────────────────────────
-- See supabase/ops/moderation.sql for copy-paste examples.
create view public.open_reports as
  select r.id as report_id, r.created_at, r.reason, r.details, r.target_type, r.target_id,
         rp.username as reporter, g.name as group_name,
         case r.target_type
           when 'comment'   then (select c.body from public.comments c where c.id = r.target_id)
           when 'user'      then (select p.username from public.profiles p where p.id = r.target_id)
           else (select f.kind || ': ' || f.payload::text from public.feed_items f where f.id = r.target_id) end as content,
         case r.target_type
           when 'comment'   then (select p.username from public.comments c join public.profiles p on p.id = c.user_id where c.id = r.target_id)
           when 'user'      then (select p.username from public.profiles p where p.id = r.target_id)
           else (select p.username from public.feed_items f join public.profiles p on p.id = f.actor_id where f.id = r.target_id) end as author,
         (select count(*) from public.reports r2 where r2.target_type = r.target_type and r2.target_id = r.target_id) as times_reported
    from public.reports r
    join public.profiles rp on rp.id = r.reporter_id
    left join public.groups g on g.id = r.group_id
   where r.status = 'open'
   order by r.created_at;

create function public.mod_resolve_report(p_report uuid, p_status text, p_note text default null) returns void
language sql security definer set search_path = public as $$
  update public.reports set status = p_status, reviewed_at = now(), reviewer_note = p_note
   where id = p_report and p_status in ('actioned', 'dismissed');
$$;
create function public.mod_hide_comment(p_comment uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.comments set hidden = true where id = p_comment;
  update public.reports set status = 'actioned', reviewed_at = now(), reviewer_note = coalesce(p_note, 'comment hidden')
   where target_type = 'comment' and target_id = p_comment and status = 'open';
end $$;
create function public.mod_hide_feed_item(p_item uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.feed_items set hidden = true where id = p_item;
  update public.reports set status = 'actioned', reviewed_at = now(), reviewer_note = coalesce(p_note, 'feed item hidden')
   where target_type = 'feed_item' and target_id = p_item and status = 'open';
end $$;
-- Banning blocks the account from posting offers, taking offers, commenting, reacting, and joining groups.
-- Existing bets still settle normally so nobody else is cheated.
create function public.mod_ban_user(p_user uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set banned = true where id = p_user;
  update public.reports set status = 'actioned', reviewed_at = now(), reviewer_note = coalesce(p_note, 'user banned')
   where target_type = 'user' and target_id = p_user and status = 'open';
end $$;
create function public.mod_unban_user(p_user uuid) returns void
language sql security definer set search_path = public as $$ update public.profiles set banned = false where id = p_user; $$;

-- Banned accounts can't create new activity (functions and triggers both enforce it).
create function public.reject_banned_maker() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.profiles where id = new.maker_id and banned) then raise exception 'account_disabled'; end if;
  return new;
end $$;
create function public.reject_banned_taker() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.profiles where id = new.taker_id and banned) then raise exception 'account_disabled'; end if;
  return new;
end $$;
create function public.reject_banned_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.profiles where id = new.user_id and banned) then raise exception 'account_disabled'; end if;
  return new;
end $$;
create trigger offers_no_banned    before insert on public.offers    for each row execute function public.reject_banned_maker();
create trigger bets_no_banned      before insert on public.bets      for each row execute function public.reject_banned_taker();
create trigger comments_no_banned  before insert on public.comments  for each row execute function public.reject_banned_user();
create trigger reactions_no_banned before insert on public.reactions for each row execute function public.reject_banned_user();

-- ───────────────────────── Permissions ─────────────────────────
revoke all on function public.normalize_text(text), public.contains_banned_term(text), public.reject_banned_profile_text(), public.reject_banned_group_text(),
  public.content_visible_to_me(uuid), public.block_user(uuid), public.unblock_user(uuid), public.mute_user(uuid), public.unmute_user(uuid),
  public.my_blocked_and_muted(), public.market_side_label(public.markets, integer), public.uname(uuid),
  public.assert_active_member_of_item(uuid), public.toggle_reaction(uuid, text), public.add_comment(uuid, text), public.delete_my_comment(uuid),
  public.report_content(text, uuid, text, text),
  public.mod_resolve_report(uuid, text, text), public.mod_hide_comment(uuid, text), public.mod_hide_feed_item(uuid, text),
  public.mod_ban_user(uuid, text), public.mod_unban_user(uuid), public.reject_banned_maker(), public.reject_banned_taker(), public.reject_banned_user()
  from public, anon, authenticated;
revoke all on public.open_reports from public, anon, authenticated;
grant execute on function public.block_user(uuid), public.unblock_user(uuid), public.mute_user(uuid), public.unmute_user(uuid),
  public.my_blocked_and_muted(), public.toggle_reaction(uuid, text), public.add_comment(uuid, text), public.delete_my_comment(uuid),
  public.report_content(text, uuid, text, text) to authenticated;
-- the views call these on the caller's behalf
grant execute on function public.content_visible_to_me(uuid) to authenticated;
