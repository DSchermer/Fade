-- Fade — Milestone 11: push notifications (queue + preferences) and in-app account deletion.
--
-- PUSH: the database decides WHO should be told WHAT and puts it in `notification_outbox`. A small Edge Function
-- (supabase/functions/send-push) picks rows up and delivers them through Apple's push service. Delivery needs the paid
-- Apple Developer account; everything up to the queue is tested without it.
--
-- DELETION: `delete_my_account()` removes or anonymises everything about you while keeping every group's books balanced.

-- ───────────────────────── Text helpers (mirror the app's) ─────────────────────────
create function public.american_text(p_cents integer) returns text
language sql immutable as $$
  select case when p_cents = 50 then '+100'
              when p_cents > 50 then '-' || round(100.0 * p_cents / (100 - p_cents))::integer
              else '+' || round(100.0 * (100 - p_cents) / p_cents)::integer end;
$$;
create function public.price_text(p_cents integer) returns text
language sql immutable as $$ select p_cents || '¢ (' || public.american_text(p_cents) || ')'; $$;

-- 10000 → "100", 3050 → "30.5", 3025 → "30.25", 123456700 → "1,234,567"
create function public.coins_text(p_amount bigint) returns text
language sql immutable as $$
  select case when p_amount < 0 then '-' else '' end
      || to_char(abs(p_amount) / 100, 'FM999G999G999G990')
      || case when abs(p_amount) % 100 = 0 then ''
              when abs(p_amount) % 10 = 0 then '.' || (abs(p_amount) % 100 / 10)
              else '.' || lpad((abs(p_amount) % 100)::text, 2, '0') end;
$$;

-- ───────────────────────── Devices and preferences ─────────────────────────
create table public.device_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id),
  token        text not null unique,
  environment  text not null default 'production' check (environment in ('sandbox', 'production')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.notification_prefs (
  user_id      uuid primary key references public.profiles (id),
  new_offer    boolean not null default true,
  offer_taken  boolean not null default true,
  bet_settled  boolean not null default true,
  vote_called  boolean not null default true,
  vote_result  boolean not null default true
);

create table public.notification_outbox (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id),
  kind       text not null check (kind in ('new_offer', 'offer_taken', 'bet_settled', 'vote_called', 'vote_result')),
  title      text not null,
  body       text not null,
  data       jsonb not null default '{}',
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  sent_at    timestamptz,
  attempts   integer not null default 0,
  last_error text
);
create index outbox_pending_idx on public.notification_outbox (id) where sent_at is null;

alter table public.device_tokens        enable row level security;     -- the app never reads these: only the sender does
alter table public.notification_outbox  enable row level security;
alter table public.notification_prefs   enable row level security;
create policy prefs_own on public.notification_prefs for select to authenticated using (user_id = auth.uid());
grant select on public.notification_prefs to authenticated;

create function public.register_device_token(p_token text, p_environment text default 'production') returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_token is null or char_length(p_token) not between 16 and 200 or p_token !~ '^[0-9a-fA-F]+$' then raise exception 'invalid_token'; end if;
  if p_environment not in ('sandbox', 'production') then raise exception 'invalid_token'; end if;
  insert into public.device_tokens (user_id, token, environment) values (auth.uid(), lower(p_token), p_environment)
  on conflict (token) do update set user_id = auth.uid(), environment = excluded.environment, last_seen_at = now();   -- a phone changed hands
  insert into public.notification_prefs (user_id) values (auth.uid()) on conflict do nothing;
end $$;

create function public.unregister_device_token(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from public.device_tokens where token = lower(coalesce(p_token, '')) and user_id = auth.uid();
end $$;

create function public.my_notification_prefs() returns public.notification_prefs
language plpgsql security definer set search_path = public as $$
declare r public.notification_prefs%rowtype;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  insert into public.notification_prefs (user_id) values (auth.uid()) on conflict do nothing;
  select * into r from public.notification_prefs where user_id = auth.uid();
  return r;
end $$;

create function public.set_notification_pref(p_kind text, p_enabled boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if p_kind not in ('new_offer', 'offer_taken', 'bet_settled', 'vote_called', 'vote_result') or p_enabled is null then raise exception 'invalid_pref'; end if;
  insert into public.notification_prefs (user_id) values (auth.uid()) on conflict do nothing;
  execute format('update public.notification_prefs set %I = $1 where user_id = $2', p_kind) using p_enabled, auth.uid();
end $$;

-- ───────────────────────── Who gets told what ─────────────────────────
create function public.enqueue_notification(p_user uuid, p_kind text, p_title text, p_body text, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_on boolean;
begin
  if not exists (select 1 from public.device_tokens where user_id = p_user) then return; end if;           -- no phone, nothing to send
  if exists (select 1 from public.profiles where id = p_user and (banned or deleted_at is not null)) then return; end if;
  execute format('select coalesce((select %I from public.notification_prefs where user_id = $1), true)', p_kind) into v_on using p_user;
  if not v_on then return; end if;
  insert into public.notification_outbox (user_id, kind, title, body, data) values (p_user, p_kind, p_title, p_body, p_data);
end $$;

-- Anyone who has blocked the author, been blocked by them, or muted them is not told about their activity.
create function public.notify_allowed(p_recipient uuid, p_author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_author is null or (
    not exists (select 1 from public.blocks b where (b.blocker = p_recipient and b.blocked = p_author) or (b.blocker = p_author and b.blocked = p_recipient))
    and not exists (select 1 from public.mutes m where m.muter = p_recipient and m.muted = p_author));
$$;

create function public.notify_from_feed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g public.groups%rowtype; p jsonb := new.payload; m record; b public.bets%rowtype;
  v_title text; v_body text; v_bal bigint; v_won boolean; v_gain bigint;
begin
  select * into g from public.groups where id = new.group_id;

  if new.kind = 'offer_posted' then
    for m in select user_id from public.group_members where group_id = new.group_id and status = 'active' and user_id <> new.actor_id loop
      if public.notify_allowed(m.user_id, new.actor_id) then
        perform public.enqueue_notification(m.user_id, 'new_offer', 'New offer in ' || g.name,
          '@' || (p ->> 'maker') || ' is backing ' || (p ->> 'side') || ' at ' || public.price_text((p ->> 'price_cents')::int) || ' — ' || (p ->> 'shares') || ' shares',
          jsonb_build_object('group_id', new.group_id, 'feed_item_id', new.id));
      end if;
    end loop;

  elsif new.kind = 'offer_taken' then
    select * into b from public.bets where id = new.ref_id;
    if public.notify_allowed(b.maker_id, b.taker_id) then
      perform public.enqueue_notification(b.maker_id, 'offer_taken', 'Your offer was taken',
        '@' || (p ->> 'taker') || ' took ' || (p ->> 'shares') || ' shares, backing ' || (p ->> 'taker_side') || ' at ' || public.price_text(100 - (p ->> 'price_cents')::int) || ' · ' || g.name,
        jsonb_build_object('group_id', new.group_id, 'feed_item_id', new.id));
    end if;

  elsif new.kind = 'bet_settled' then
    select * into b from public.bets where id = new.ref_id;
    for m in select b.maker_id as uid union all select b.taker_id loop
      select available + escrow into v_bal from public.group_members where group_id = new.group_id and user_id = m.uid;
      if b.status = 'void' then
        v_title := 'Bet voided — stakes refunded';
      else
        v_won := (b.status = 'won_maker') = (m.uid = b.maker_id);
        v_gain := case when m.uid = b.maker_id then b.taker_stake else b.maker_stake end;       -- what the winner gains / the loser's own stake
        v_title := case when v_won then 'You won ' else 'You lost ' end
                   || public.coins_text(case when v_won then v_gain else (case when m.uid = b.maker_id then b.maker_stake else b.taker_stake end) end) || ' coins';
      end if;
      perform public.enqueue_notification(m.uid, 'bet_settled', v_title,
        coalesce(p ->> 'event_title', 'Your bet') || ' · new balance ' || public.coins_text(coalesce(v_bal, 0)) || ' coins · ' || g.name,
        jsonb_build_object('group_id', new.group_id, 'feed_item_id', new.id));
    end loop;

  elsif new.kind = 'vote_called' then
    for m in select user_id from public.group_members where group_id = new.group_id and status = 'active' and user_id <> new.actor_id loop
      if public.notify_allowed(m.user_id, new.actor_id) then
        v_title := case when p ->> 'vote_kind' = 'reset' then 'Reset vote in ' || g.name else 'Buyback vote in ' || g.name end;
        v_body := case when p ->> 'vote_kind' = 'reset'
                       then '@' || (p ->> 'caller') || ' called a vote to reset the group. Unsettled bets would be voided and refunded.'
                       else '@' || (p ->> 'caller') || ' is asking for a buyback. Cast your vote.' end;
        perform public.enqueue_notification(m.user_id, 'vote_called', v_title, v_body, jsonb_build_object('group_id', new.group_id, 'feed_item_id', new.id));
      end if;
    end loop;

  elsif new.kind = 'vote_result' then
    for m in select user_id from public.group_members where group_id = new.group_id and status = 'active' loop
      perform public.enqueue_notification(m.user_id, 'vote_result',
        case when p ->> 'vote_kind' = 'reset' then 'Reset vote ' || (p ->> 'status') else 'Buyback vote ' || (p ->> 'status') end,
        g.name || ' · ' || coalesce(p ->> 'yes', '0') || ' yes, ' || coalesce(p ->> 'no', '0') || ' no',
        jsonb_build_object('group_id', new.group_id, 'feed_item_id', new.id));
    end loop;
  end if;
  return null;
end $$;
create trigger feed_notify after insert on public.feed_items for each row execute function public.notify_from_feed();

-- ───────────────────────── Delivery (called only by the send-push function with the service key) ─────────────────────────
create function public.claim_notifications(p_limit integer default 50)
returns table (id bigint, token text, environment text, title text, body text, data jsonb)
language plpgsql security definer set search_path = public as $$
begin
  delete from public.notification_outbox where (sent_at is not null and sent_at < now() - interval '7 days') or created_at < now() - interval '14 days';
  return query
    with picked as (
      select o.id from public.notification_outbox o
       where o.sent_at is null and o.attempts < 5 and (o.claimed_at is null or o.claimed_at < now() - interval '2 minutes')
       order by o.id limit greatest(1, least(p_limit, 200))
         for update skip locked),
    marked as (
      update public.notification_outbox o set claimed_at = now(), attempts = o.attempts + 1
        from picked where o.id = picked.id returning o.id, o.user_id, o.title, o.body, o.data)
    select m.id, d.token, d.environment, m.title, m.body, m.data
      from marked m join public.device_tokens d on d.user_id = m.user_id;
end $$;

create function public.finish_notification(p_id bigint, p_ok boolean, p_error text default null, p_dead_tokens text[] default '{}') returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_ok then update public.notification_outbox set sent_at = now(), last_error = null where id = p_id;
  else update public.notification_outbox set last_error = left(p_error, 300) where id = p_id; end if;
  delete from public.device_tokens where token = any (p_dead_tokens);          -- Apple said these phones are gone
end $$;

-- ───────────────────────── Account deletion ─────────────────────────
-- The profile row stays (history needs a person to point at) but becomes "Deleted user" with no name, no sign-in and no
-- data; the sign-in account itself is deleted. Nothing is left in anyone's books that doesn't balance.
alter table public.profiles drop constraint profiles_id_fkey;

create function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  g record; o record; b record; m public.group_members%rowtype;
  v_tx uuid; v_realized bigint; v_heir uuid;
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  -- FOR NO KEY UPDATE (not FOR UPDATE): other functions take a lighter lock on this row when they reference it, and the stronger lock deadlocked with them
  select username into v_name from public.profiles where id = v_uid and deleted_at is null for no key update;
  if not found then raise exception 'not_signed_in' using errcode = '28000'; end if;

  for g in select group_id from public.group_members where user_id = v_uid and status = 'active' order by group_id loop
    -- 1. Lock in the usual order (offers → bets → balances) BEFORE touching anything else. (Doing the ownership change first
    --    locked another member's balance row too early and deadlocked with someone taking one of my offers.)
    perform 1 from public.offers where group_id = g.group_id and maker_id = v_uid and status = 'open' order by id for update;
    perform 1 from public.bets where group_id = g.group_id and status = 'pending' and (maker_id = v_uid or taker_id = v_uid) order by id for update;
    perform 1 from public.group_members where group_id = g.group_id order by user_id for update;

    -- 2. If I own the group and others remain, the member who has been there longest becomes the owner.
    if exists (select 1 from public.group_members where group_id = g.group_id and user_id = v_uid and role = 'owner' and status = 'active') then
      select user_id into v_heir from public.group_members
       where group_id = g.group_id and status = 'active' and user_id <> v_uid order by joined_at, user_id limit 1;
      if v_heir is not null then
        update public.group_members set role = 'member' where group_id = g.group_id and user_id = v_uid;
        update public.group_members set role = 'owner'  where group_id = g.group_id and user_id = v_heir;
      end if;
    end if;

    for o in select id, shares_open, price_cents from public.offers where group_id = g.group_id and maker_id = v_uid and status = 'open' and shares_open > 0 loop
      v_tx := gen_random_uuid();
      perform public.ledger_post(v_tx, g.group_id, v_uid, 'escrow',    -(o.shares_open::bigint * o.price_cents), 'escrow_release', 'offer', o.id);
      perform public.ledger_post(v_tx, g.group_id, v_uid, 'available',   o.shares_open::bigint * o.price_cents,  'escrow_release', 'offer', o.id);
      update public.offers set shares_cancelled = shares_cancelled + shares_open, shares_open = 0, status = 'cancelled', cancel_reason = 'left' where id = o.id;
    end loop;

    -- my unsettled bets are voided: the OTHER person gets their stake back in full, no win or loss for anyone
    for b in select * from public.bets where group_id = g.group_id and status = 'pending' and (maker_id = v_uid or taker_id = v_uid) loop
      v_tx := gen_random_uuid();
      perform public.ledger_post(v_tx, g.group_id, b.maker_id, 'escrow',    -b.maker_stake, 'bet_void', 'bet', b.id);
      perform public.ledger_post(v_tx, g.group_id, b.maker_id, 'available',  b.maker_stake, 'bet_void', 'bet', b.id);
      perform public.ledger_post(v_tx, g.group_id, b.taker_id, 'escrow',    -b.taker_stake, 'bet_void', 'bet', b.id);
      perform public.ledger_post(v_tx, g.group_id, b.taker_id, 'available',  b.taker_stake, 'bet_void', 'bet', b.id);
      update public.bets set status = 'void', settled_at = public.app_now() where id = b.id;
    end loop;

    -- 3. leave: keep the profit/loss in the (anonymous) lifetime score, burn the rest, clear the baseline
    select * into m from public.group_members where group_id = g.group_id and user_id = v_uid;
    v_realized := m.available + m.escrow - m.granted - m.buyback_coins;
    if m.available > 0 then
      perform public.ledger_post(gen_random_uuid(), g.group_id, v_uid, 'available', -m.available, 'leave_burn', 'group', g.group_id);
    end if;
    update public.group_members set status = 'left', role = 'member', granted = 0, buyback_count = 0, buyback_coins = 0,
           realized_profit = realized_profit + v_realized where group_id = g.group_id and user_id = v_uid;
    update public.profiles set lifetime_closed_profit = lifetime_closed_profit + v_realized where id = v_uid;
  end loop;

  -- 4. everything else that is about me
  delete from public.device_tokens where user_id = v_uid;
  delete from public.notification_prefs where user_id = v_uid;
  delete from public.notification_outbox where user_id = v_uid;
  delete from public.friendships where requester = v_uid or addressee = v_uid;
  delete from public.blocks where blocker = v_uid or blocked = v_uid;
  delete from public.mutes where muter = v_uid or muted = v_uid;
  delete from public.reactions where user_id = v_uid;
  delete from public.comments where user_id = v_uid;
  delete from public.vote_ballots vb using public.votes v where vb.vote_id = v.id and vb.user_id = v_uid and v.status = 'open';
  -- my name inside saved feed text becomes "deleted user"
  if v_name is not null then
    update public.feed_items set payload = replace(payload::text, '"' || v_name || '"', '"deleted user"')::jsonb
     where payload::text like '%"' || v_name || '"%';
  end if;

  -- 5. the profile becomes an anonymous placeholder; the sign-in account is deleted
  update public.profiles set username = null, display_name = 'Deleted user', avatar_emoji = '🙂', price_format = 'cents', deleted_at = now()
   where id = v_uid;
  delete from auth.users where id = v_uid;
end $$;

-- ───────────────────────── Permissions ─────────────────────────
revoke all on function public.american_text(integer), public.price_text(integer), public.coins_text(bigint),
  public.register_device_token(text, text), public.unregister_device_token(text), public.my_notification_prefs(), public.set_notification_pref(text, boolean),
  public.enqueue_notification(uuid, text, text, text, jsonb), public.notify_allowed(uuid, uuid), public.notify_from_feed(),
  public.claim_notifications(integer), public.finish_notification(bigint, boolean, text, text[]), public.delete_my_account()
  from public, anon, authenticated;
grant execute on function public.register_device_token(text, text), public.unregister_device_token(text), public.my_notification_prefs(),
  public.set_notification_pref(text, boolean), public.delete_my_account() to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.claim_notifications(integer), public.finish_notification(bigint, boolean, text, text[]) to service_role;
  end if;
end $$;
