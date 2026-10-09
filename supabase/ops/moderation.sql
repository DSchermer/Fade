-- Fade — owner moderation tools. Run these in the Supabase SQL editor (Dashboard → SQL Editor).
-- None of this is reachable from the app: only you, signed in to the dashboard, can run it.
-- Run ONE block at a time (select the lines you want, then press Run).
--
-- Apple requires that reported content is acted on quickly (the usual expectation is within 24 hours).
-- Suggested routine: check "1. What is waiting?" once a day.

-- ───────────────────────── 1. What is waiting? ─────────────────────────
select * from public.open_reports;
-- columns: report_id, created_at, reason, details, target_type (comment / user / feed_item), target_id,
--          reporter, group_name, content (the text that was reported), author, times_reported

-- ───────────────────────── 2. Act on a report ─────────────────────────
-- Hide a comment (it disappears for everyone; the open reports about it are marked "actioned"):
-- select public.mod_hide_comment('PASTE-target_id-HERE', 'hidden: harassment');

-- Hide a feed item (offer / take / result post):
-- select public.mod_hide_feed_item('PASTE-target_id-HERE', 'hidden: spam');

-- Ban a user. A banned account can no longer post offers, take offers, comment, react or join groups.
-- Their existing bets still settle normally, so nobody else is cheated. (Use the author's id, see section 4.)
-- select public.mod_ban_user('PASTE-USER-ID-HERE', 'banned: repeated harassment');

-- Undo a ban:
-- select public.mod_unban_user('PASTE-USER-ID-HERE');

-- Close a report without doing anything to the content ("dismissed") or after handling it another way ("actioned"):
-- select public.mod_resolve_report('PASTE-report_id-HERE', 'dismissed', 'not a violation');

-- ───────────────────────── 3. Everything reported in the last 7 days (including closed ones) ─────────────────────────
-- select r.created_at, r.status, r.reason, r.target_type, r.reviewer_note, r.reviewed_at
--   from public.reports r where r.created_at > now() - interval '7 days' order by r.created_at desc;

-- ───────────────────────── 4. Find a user by username ─────────────────────────
-- select id, username, banned, created_at from public.profiles where username = 'somename';

-- ───────────────────────── 5. The word filter ─────────────────────────
-- The filter blocks usernames, group names and comments that contain a listed word (whole words only; it also catches
-- look-alike symbols such as "sh1t" and stretched letters such as "shiiit"). The starter list covers common profanity and
-- threats. It deliberately contains no slurs: add the ones you want to block here, one lowercase word or phrase per row.
--
-- see the current list:
-- select term from public.banned_terms order by term;
-- add words:
-- insert into public.banned_terms (term) values ('word one'), ('word two') on conflict do nothing;
-- remove one:
-- delete from public.banned_terms where term = 'word';
-- quick test of what the filter would do with a piece of text:
-- select public.contains_banned_term('some text to try');

-- ───────────────────────── 6. Who blocked / reported the most? (spot abuse of the report button) ─────────────────────────
-- select rp.username as reporter, count(*) as reports_sent
--   from public.reports r join public.profiles rp on rp.id = r.reporter_id
--  group by rp.username order by reports_sent desc limit 20;
