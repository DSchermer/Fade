-- Migration 0015 (UI redesign): the feed can now show items from ALL of a person's groups in one list, so each item says which
-- group it belongs to. It also carries what the cards need: how the offer behind an item stands right now (still open? how many
-- shares left?), what became of a taken bet (pending, settled, void), what kind of market it was and when the game starts, and the latest visible comment as a preview.
-- Columns are only ADDED at the end, so everything that reads this view today keeps working. Permissions are unchanged
-- (the view still runs as the person asking, so row-level security still applies to every table it reads).
create or replace view public.feed_listing with (security_invoker = true) as
  select f.id, f.group_id, f.kind, f.actor_id, p.username as actor_username, f.ref_type, f.ref_id, f.payload, f.created_at,
         (select count(*) from public.comments c where c.feed_item_id = f.id and not c.hidden and public.content_visible_to_me(c.user_id))::integer as comment_count,
         coalesce((select jsonb_object_agg(r.emoji, r.n) from
                    (select emoji, count(*) as n from public.reactions where feed_item_id = f.id group by emoji) r), '{}'::jsonb) as reactions,
         coalesce((select array_agg(emoji order by emoji) from public.reactions where feed_item_id = f.id and user_id = auth.uid()), '{}'::text[]) as my_reactions,
         g.name as group_name,
         o.status as offer_status,
         o.shares_open as offer_shares_open,
         m.market_type,
         m.game_start,
         b.status as bet_status,
         (select jsonb_build_object('username', cp.username, 'body', c.body)
            from public.comments c join public.profiles cp on cp.id = c.user_id
           where c.feed_item_id = f.id and not c.hidden and public.content_visible_to_me(c.user_id)
           order by c.created_at desc, c.id desc limit 1) as latest_comment
    from public.feed_items f
    join public.groups g on g.id = f.group_id
    left join public.profiles p on p.id = f.actor_id
    left join public.offers o on f.ref_type = 'offer' and o.id = f.ref_id
    left join public.bets b on f.ref_type = 'bet' and b.id = f.ref_id
    left join public.markets m on m.id = coalesce(o.market_id, b.market_id)
   where public.content_visible_to_me(f.actor_id);
