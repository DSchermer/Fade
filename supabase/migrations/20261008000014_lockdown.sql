-- Fade — Milestone 13 (security audit): belt and braces for who can touch what.
--
-- Supabase automatically gives the `anon` (not signed in) and `authenticated` (signed in) roles full table rights on every
-- new table, and PostgreSQL gives every role EXECUTE on every new function. Until now Fade relied on Row Level Security (every
-- table has it, with SELECT-only policies) plus explicit REVOKEs per function. That is safe, but a single forgotten REVOKE or a
-- policy added by mistake later would silently open something up. This migration closes the door at the permission level too:
--
--   • anon gets nothing at all.
--   • signed-in users get SELECT on exactly the tables/views the app reads (plus the 3 profile columns they may edit).
--     They can never INSERT / UPDATE / DELETE / TRUNCATE anything directly: all changes go through the server functions.
--   • no function is callable by anyone unless a migration says so explicitly (the explicit GRANTs are untouched).
--   • tables created in the future start out locked (functions: see the note in step 3).
--
-- tests/m13_audit_test.sql keeps this honest by comparing the real permissions with a written allow-list.

-- 1. Tables, views, sequences: take everything back, then give back the reads the app needs.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select on
  public.profiles, public.groups, public.seasons, public.group_members, public.season_standings, public.ledger,
  public.markets, public.market_listing,
  public.offers, public.bets, public.offer_listing, public.bet_listing,
  public.buybacks, public.buyback_listing, public.group_leaderboard, public.my_score,
  public.votes, public.vote_ballots, public.vote_listing, public.season_history,
  public.blocks, public.mutes, public.feed_items, public.reactions, public.comments, public.feed_listing, public.comment_listing,
  public.friendships, public.notification_prefs
  to authenticated;
grant update (display_name, avatar_emoji, price_format) on public.profiles to authenticated;

-- 2. Functions: nobody (including "everyone") may run a function unless a migration granted it to them by name.
--    Only our own functions are touched (extension functions are left alone). `authenticated`'s explicit grants stay as they are.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proowner = (select oid from pg_roles where rolname = current_user)
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
  end loop;
end $$;

-- 3. Future tables and sequences start locked. (Applies to objects created by the role that runs this file: `postgres` in the SQL editor.)
--    PostgreSQL always lets PUBLIC run a new function and a schema-level setting cannot undo that, so for functions the rule stays
--    "every migration revokes explicitly" -- and tests/m13_audit_test.sql fails if one ever forgets.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
