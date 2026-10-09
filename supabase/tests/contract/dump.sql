-- Writes, as the signed-in app would receive them, the JSON of every read the iPhone app makes. Run from the output directory (see run.sh).
\set ON_ERROR_STOP on
\t on
\pset format unaligned
\pset footer off

-- one more upcoming game (the seed's own game has already been settled), so the Games list has something to show
select ingest_markets('nhl', :'nhl_fixture'::jsonb, '2026-10-08 12:00+00');

-- as alice
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
set role authenticated;
\o feed_listing.json
select coalesce(json_agg(t), '[]') from (select * from feed_listing order by created_at) t;
\o comment_listing.json
select coalesce(json_agg(t), '[]') from (select * from comment_listing) t;
\o my_blocked_and_muted.json
select coalesce(json_agg(t), '[]') from my_blocked_and_muted() t;
\o friend_scores.json
select coalesce(json_agg(t), '[]') from friend_scores() t;
\o my_friend_requests.json
select coalesce(json_agg(t), '[]') from my_friend_requests() t;
\o friend_suggestions.json
select coalesce(json_agg(t), '[]') from friend_suggestions() t;
\o group_members.json
select coalesce(json_agg(json_build_object('role', gm.role, 'available', gm.available, 'escrow', gm.escrow,
   'groups', json_build_object('id', g.id, 'name', g.name, 'invite_code', g.invite_code, 'starting_balance', g.starting_balance,
      'buyback_policy', g.buyback_policy, 'buybacks_per_week', g.buybacks_per_week, 'buyback_amount', g.buyback_amount))), '[]')
  from group_members gm join groups g on g.id = gm.group_id where gm.user_id = '00000000-0000-0000-0000-0000000000a1'::uuid and gm.status = 'active';
\o group_leaderboard.json
select coalesce(json_agg(t), '[]') from (select * from group_leaderboard) t;
\o buyback_listing.json
select coalesce(json_agg(t), '[]') from (select * from buyback_listing) t;
\o my_score.json
select coalesce(json_agg(t), '[]') from (select * from my_score) t;
\o vote_listing.json
select coalesce(json_agg(t), '[]') from (select * from vote_listing) t;
\o season_history.json
select coalesce(json_agg(t), '[]') from (select * from season_history) t;
\o market_listing.json
select coalesce(json_agg(t), '[]') from (select id, league, market_type, question, outcomes, line, game_start, event_id, event_title, outcome_prices from market_listing) t;
\o game_lines.json
select coalesce(json_agg(t), '[]') from game_lines() t;
\o offer_listing.json
select coalesce(json_agg(t), '[]') from (select * from offer_listing) t;
\o bet_listing.json
select coalesce(json_agg(t), '[]') from (select * from bet_listing) t;
\o profiles.json
select coalesce(json_agg(t), '[]') from (select * from profiles where id = '00000000-0000-0000-0000-0000000000a1'::uuid) t;
\o my_notification_prefs_a.json
select coalesce(json_agg(t), '[]') from (select * from my_notification_prefs()) t;
\o send_friend_request.json
select to_json(send_friend_request('fred'));
\o
-- as bobby (has a buyback; a busted-in-vote-group status)
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
set role authenticated;
\o buyback_status_g2.json
select coalesce(json_agg(t), '[]') from buyback_status((select id from groups where name = 'Weekly Crew')) t;
\o buyback_status_g1.json
select coalesce(json_agg(t), '[]') from buyback_status((select id from groups where name = 'Main Crew')) t;
\o buyback_status_g3.json
select coalesce(json_agg(t), '[]') from buyback_status((select id from groups where name = 'Vote Crew')) t;
\o vote_listing_b.json
select coalesce(json_agg(t), '[]') from (select * from vote_listing) t;
\o offer_listing_b.json
select coalesce(json_agg(t), '[]') from (select * from offer_listing) t;
\o bet_listing_b.json
select coalesce(json_agg(t), '[]') from (select * from bet_listing) t;
\o friend_scores_b.json
select coalesce(json_agg(t), '[]') from friend_scores() t;
\o my_friend_requests_b.json
select coalesce(json_agg(t), '[]') from my_friend_requests() t;
\o
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
set role authenticated;
\o my_notification_prefs_obj.json
select to_json(p) from my_notification_prefs() p;
\o
