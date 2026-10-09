-- Security audit: who may read, write or run what. Compares the REAL permissions in the database with a written allow-list,
-- so adding a table or function and forgetting to lock it down fails here instead of becoming a hole.
-- (00_local_auth_stub.sql gives new objects Supabase's default grants, so this test sees the same situation as the real project.)
\set ON_ERROR_STOP on
begin;

-- 1. Row Level Security is on for every table.
do $$
declare t text;
begin
  select string_agg(c.relname, ', ') into t
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if t is not null then raise exception 'RLS is OFF for: %', t; end if;
end $$;

-- 2. Not signed in (anon): nothing at all.
do $$
declare t text;
begin
  select string_agg(c.relname, ', ') into t
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm')
     and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
          or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete')
          or has_table_privilege('anon', c.oid, 'truncate'));
  if t is not null then raise exception 'anon can touch: %', t; end if;

  select string_agg(p.oid::regprocedure::text, ', ') into t
    from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute');
  if t is not null then raise exception 'anon can run: %', t; end if;
end $$;

-- 3. Signed-in users never write to a table or view directly, except the 3 profile columns they may edit.
do $$
declare t text;
begin
  select string_agg(c.relname, ', ') into t
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm')
     and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'delete')
          or has_table_privilege('authenticated', c.oid, 'truncate') or has_table_privilege('authenticated', c.oid, 'update'));
  if t is not null then raise exception 'signed-in users have table-wide write rights on: %', t; end if;      -- (profiles has column-level rights only: checked next)

  select string_agg(a.attname, ', ' order by a.attname) into t
    from pg_attribute a
   where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and not a.attisdropped
     and has_column_privilege('authenticated', 'public.profiles'::regclass, a.attnum, 'update');
  if t is distinct from 'avatar_emoji, display_name, price_format' then raise exception 'editable profile columns are: %', t; end if;
  -- and nobody can touch a sequence
  select string_agg(sequencename, ', ') into t from pg_sequences
   where schemaname = 'public' and has_sequence_privilege('authenticated', format('%I.%I', schemaname, sequencename), 'usage,select,update');
  if t is not null then raise exception 'signed-in users can use sequences: %', t; end if;
end $$;

-- 4. The tables and views signed-in users can READ must be exactly this list (RLS decides which rows).
--    Everything else (reports, banned_terms, device tokens, the push queue, Apple tokens, sync log, clock override, ...) is private.
do $$
declare actual text[]; expected text[] := array[
  'bet_listing', 'bets', 'blocks', 'buyback_listing', 'buybacks', 'comment_listing', 'comments', 'feed_items', 'feed_listing',
  'friendships', 'group_leaderboard', 'group_members', 'groups', 'ledger', 'market_listing', 'markets', 'mutes',
  'my_score', 'notification_prefs', 'offer_listing', 'offers', 'profiles', 'reactions', 'season_history', 'season_standings',
  'seasons', 'vote_ballots', 'vote_listing', 'votes'];
begin
  select array_agg(c.relname::text order by c.relname) into actual
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm') and has_table_privilege('authenticated', c.oid, 'select');
  if actual is distinct from expected then
    raise exception 'readable tables changed. extra: %, missing: %',
      (select array_agg(x) from unnest(actual) x where x <> all (expected)),
      (select array_agg(x) from unnest(expected) x where x <> all (actual));
  end if;
end $$;

-- 5. Every view that clients read respects the reader's own permissions (security_invoker), so it can't leak rows.
do $$
declare t text;
begin
  select string_agg(c.relname, ', ') into t
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'v' and has_table_privilege('authenticated', c.oid, 'select')
     and not coalesce((select 'security_invoker=true' = any (c.reloptions)), false);
  if t is not null then raise exception 'views without security_invoker: %', t; end if;
end $$;

-- 6. Functions signed-in users may run: exactly this list. Money-moving internals (ledger_post, settle_*, apply_group_reset,
--    evaluate_vote, claim_notifications, mod_* ...) must NOT be here.
do $$
declare actual text[]; expected text[] := array[
  'add_comment', 'app_now', 'block_user', 'buyback_status', 'call_vote', 'cancel_friend_request', 'cancel_offer', 'cast_vote',
  'claim_buyback', 'content_visible_to_me', 'create_group', 'delete_my_account', 'delete_my_comment', 'friend_scores',
  'friend_suggestions', 'game_lines', 'is_group_member', 'join_group', 'leave_group', 'market_is_open', 'market_phase', 'mute_user',
  'my_blocked_and_muted', 'my_friend_requests', 'my_notification_prefs', 'post_offer', 'register_device_token', 'remove_friend',
  'report_content', 'respond_friend_request', 'send_friend_request', 'set_notification_pref', 'set_username', 'shares_group_with',
  'take_offer', 'toggle_reaction', 'transfer_ownership', 'unblock_user', 'unmute_user', 'unregister_device_token', 'username_available'];
begin
  select array_agg(distinct p.proname::text order by p.proname::text) into actual
    from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute');
  if actual is distinct from expected then
    raise exception 'callable functions changed. extra: %, missing: %',
      (select array_agg(x) from unnest(actual) x where x <> all (expected)),
      (select array_agg(x) from unnest(expected) x where x <> all (actual));
  end if;
end $$;

-- 7. Every client-callable function that changes data is SECURITY DEFINER with a pinned search_path (so nobody can shadow
--    a table or function name), except the pure read helpers.
do $$
declare t text;
begin
  select string_agg(p.proname, ', ') into t
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and has_function_privilege('authenticated', p.oid, 'execute')
     and p.provolatile = 'v'                                  -- may write
     and not (p.prosecdef and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'));
  if t is not null then raise exception 'writer functions without security definer + fixed search_path: %', t; end if;

  select string_agg(p.proname, ', ') into t
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  if t is not null then raise exception 'security definer functions without a fixed search_path: %', t; end if;
end $$;

-- 8. The server-only delivery functions are for the service role alone.
do $$
begin
  if has_function_privilege('authenticated', 'public.claim_notifications(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.finish_notification(bigint, boolean, text, text[])', 'execute') then
    raise exception 'signed-in users must not run the push delivery functions';
  end if;
  if not has_function_privilege('service_role', 'public.claim_notifications(integer)', 'execute') then
    raise exception 'the push sender (service role) needs claim_notifications';
  end if;
end $$;

rollback;
select 'm13 audit ok' as result;
