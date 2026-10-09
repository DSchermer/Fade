# Fade — SPEC (draft for approval)

Status: **APPROVED decisions recorded 2026-10-08** (see §14). Milestone 1 in progress. Polymarket findings are in `POLYMARKET_RESEARCH.md`.

## 0. Plain-language architecture

```
 iPhone app (SwiftUI)  ──reads/subscribes──►  Supabase Postgres (RLS: members see only their groups)
        │                                              ▲
        └──calls RPC functions (post/take/cancel/…)────┤  all coin movement happens ONLY inside
                                                       │  these server functions, in one transaction
 Scheduled jobs (pg_cron → Edge Functions) ────────────┘
   • discover markets   • refresh start times   • auto-cancel at start
   • settle             • close votes           • send pushes (APNs)
        │
        └──reads──► Polymarket Gamma API (public, read-only)
```

Rules of thumb: the app never writes balances; the app never talks to Polymarket; secrets live only in Supabase.

**Recommended iOS target: iOS 17.** It gives us the modern SwiftUI data model (`@Observable`), is supported by the large majority of active iPhones, and iOS 16 and older would force older, clunkier code. **Decided: yes.**

**Accounts you will need and when:**
- **Supabase (free tier)** — needed at Milestone 1 (backend + database). I'll walk you through it.
- **Apple Developer Program ($99/yr)** — needed at Milestone 2 for Sign in with Apple on a real device, and at Milestone 11 for push (APNs key) and TestFlight. The simulator can't test Sign in with Apple or push fully, so M2 is the real trigger. Until then we can build on the simulator with a **dev-only login** (disabled in release builds).

## 1. Money rules (coin math)

All amounts are stored as **integers in hundredths of a coin** ("centicoins"). 1 coin = 100 centicoins.

- Price `p` is an integer cent, 1–99, **for the side the maker backs**. 1 share pays 1 coin = 100 centicoins to the winner.
- A fill of `n` whole shares:
  - maker stake = `n × p` centicoins
  - taker stake = `n × (100 − p)` centicoins
  - pot = `n × 100` centicoins = maker stake + taker stake **exactly**. No rounding anywhere.
- Example from CLAUDE.md: p = 60, n = 50 → maker 3000 (30.00 coins), taker 2000 (20.00 coins), pot 5000 (50.00 coins). ✔
- Posting an offer of `N` shares escrows `N × p` from the maker. Each take escrows `n × (100−p)` from the taker and moves `n × p` of the maker's escrow into the bet.
- Winner receives the whole pot. Loser receives nothing. **Void** returns each side's own stake.
- Balances: `available` (spendable) and `escrow` (locked in open offers and unsettled bets). A member can never stake more than `available`. Neither can go negative (database `CHECK` constraints).
- **American odds** convert to cents for display/entry only. `-150` → 60¢; `+150` → 40¢. Formula: negative odds `o` → `100·|o| / (|o|+100)`; positive `o` → `10000 / (o+100)`; rounded to the nearest cent and clamped to 1–99. The confirm screen always shows the **actual cents**, risk, and payout.
- Display: up to two decimals, trailing zeros trimmed (e.g. `30`, `30.5`, `30.25`).

## 2. Data model (Postgres)

Names are working names; types abbreviated. Every table has RLS on.

**People**
- `profiles(id = auth user, username unique citext, display_name, avatar_emoji, price_format 'cents'|'american', created_at, lifetime_closed_profit int, lifetime_wins int, lifetime_losses int, deleted_at)`
- `friendships(user_a, user_b, status 'pending'|'accepted', requested_by)`
- `blocks(blocker, blocked)`, `mutes(muter, muted)`
- `device_tokens(user_id, token)`, `notification_prefs(user_id, new_offer, offer_taken, bet_settled, vote_called, vote_result)`

**Groups**
- `groups(id, name, invite_code unique, created_by, starting_balance, buyback_policy 'unlimited'|'weekly'|'vote', buybacks_per_week null, buyback_amount, current_season_id)`
- `group_members(group_id, user_id, role 'owner'|'member', joined_at, available int ≥0, escrow int ≥0, buyback_count, buyback_coins, status 'active'|'left')`
- `seasons(id, group_id, number, started_at, ended_at)`; `season_standings(season_id, user_id, final_balance, buyback_count, buyback_coins, net_profit)`

**Betting**
- `markets(id = Polymarket id text, event_id, league, market_type 'moneyline'|'spreads'|'totals', question, outcomes text[2], line numeric null, game_start timestamptz, accepting bool, closed bool, uma_status text, outcome_prices text, state 'open'|'started'|'final'|'void', winning_outcome int null, last_synced_at)`
- `offers(id, group_id, season_id, maker_id, market_id, outcome int 0|1, price_cents 1..99, shares_total, shares_open, status 'open'|'filled'|'cancelled', created_at)`
- `bets(id, offer_id, group_id, season_id, market_id, maker_id, taker_id, outcome_maker int, price_cents, shares, status 'pending'|'won_maker'|'won_taker'|'void', maker_stake, taker_stake, settled_at)` — one row per fill.

**Ledger (append-only)**
- `ledger(id, tx_id, group_id, user_id, bucket 'available'|'escrow', delta int, kind, ref_type, ref_id, created_at)`
- `kind` ∈ `grant` (starting balance), `buyback`, `escrow_lock`, `escrow_release`, `bet_win`, `bet_void`, `season_burn`, `leave_burn`, etc.
- No UPDATE or DELETE allowed (revoked from every role, plus a trigger that raises).
- `group_members.available/escrow` are a cached copy updated in the same transaction. A nightly check recomputes them from the ledger and fails loudly on any mismatch.

**Integrity checks (SQL functions, run by a job and by tests):**
1. For every `tx_id`, `sum(delta) = 0` unless `kind ∈ {grant, buyback, season_burn, leave_burn}` (the only places coins are created or destroyed).
2. For every group, `sum(all ledger deltas) = Σ grants + Σ buybacks − Σ burns`.
3. For every group member, cached `available`/`escrow` equal the ledger sums.
4. For every bet, `maker_stake + taker_stake = shares × 100`.
5. For every offer, `shares_open + Σ bet shares + cancelled shares = shares_total`.

**Votes, feed, safety**
- `votes(id, group_id, kind 'reset'|'buyback', subject_user_id null, called_by, opens_at, closes_at, status 'open'|'passed'|'failed'|'cancelled')`, `vote_ballots(vote_id, user_id, yes bool)`
- `feed_items(id, group_id, kind 'offer_posted'|'offer_taken'|'bet_settled'|'buyback'|'vote'|'reset', actor_id, ref_id, payload jsonb, created_at)`
- `reactions(feed_item_id, user_id, emoji)`, `comments(id, feed_item_id, user_id, body, hidden bool, created_at)`
- `reports(id, reporter_id, target_type, target_id, reason, status 'open'|'actioned'|'dismissed', created_at)`

## 3. Server functions (the only way coins move)

All are `SECURITY DEFINER` Postgres functions that lock the rows they touch (`SELECT … FOR UPDATE`), check membership via `auth.uid()`, and write ledger rows in one transaction.

| Function | What it does |
|---|---|
| `create_group`, `join_group(code)` | Creates the group/season 1; join grants the starting balance (`grant`). **Decided:** rejoining a group you left returns you with 0 coins and no new grant (you are then busted and can use the buyback policy). |
| `post_offer(group, market, outcome, price, shares)` | Requires market `open`, `now < game_start`, `accepting`, and `available ≥ shares×price`. Locks escrow. |
| `take_offer(offer, shares)` | Requires `1 ≤ shares ≤ shares_open`, taker ≠ maker, market still open and before start, `available ≥ shares×(100−price)`. Creates a `bet`. Row-locking the offer prevents two takers over-filling it. |
| `cancel_offer(offer)` | Maker only, before start; refunds escrow for **unfilled** shares only. |
| `auto_cancel_started()` | Job: for markets past `game_start` (or closed), cancels all unfilled shares and refunds. |
| `settle_market(market)` | Idempotent (see §6). |
| `claim_buyback()` | Busted + policy allows (see §7). |
| `cast_vote`, `call_vote`, `close_votes()` | See §8. |
| `leave_group`, `delete_account` | See §11. |

Client reads go through RLS-protected views; clients have no INSERT/UPDATE/DELETE on `group_members`, `offers`, `bets`, `ledger`, or `markets`.

## 4. Screens

1. **Sign in** — Sign in with Apple; first launch asks for a username.
2. **Groups list** — your groups with balance; create / join (code or link).
3. **Group home** (tabs): **Feed**, **Markets**, **My Bets**, **Leaderboard**, **Group info**.
   - **Feed**: offers posted/taken/settled, buybacks, votes; reactions + comments; banner when a reset vote is open.
   - **Markets**: league filter → upcoming games (next 7 days) → game detail listing its moneyline / spread / total markets → open offers on each with a **Take** button, and **Make an offer**.
   - **Make offer / Take sheet**: side, price (in your format), shares; shows the actual cents, your risk, your payout, the other side's risk. Confirm.
   - **My Bets**: open offers (cancel), pending bets (with statuses such as *Game final — awaiting official result* / *Result disputed — may take several days*), settled history.
   - **Leaderboard**: toggle Net profit / Raw balance (with buyback count); past seasons.
   - **Group info**: members, invite link, rules, buyback history, call vote, leave.
4. **Votes** — vote detail with live tally and closing time.
5. **Friends** — requests, search by username, suggestions from shared groups, friends leaderboard.
6. **Profile / Settings** — global score + W-L, price format, notification toggles, blocked/muted, legal text, help resources, delete account.
7. **Report / block / mute** actions on comments and users.

## 5. Key user flows (short)

- **Join**: open link `https://<domain>/join/CODE` (universal link) or enter code → preview group → join.
- **Make → take**: maker posts (escrow locked, feed item, push to group) → taker takes n shares (both escrowed, push to maker) → remainder stays open → at game start remaining shares auto-cancel and refund.
- **Settle**: job sees final result → bets paid → ledger rows → push "You won 20 — balance 140" → feed item.
- **Broke**: member has `available + escrow = 0` → app shows *Buy back in* (per policy).

## 6. Polymarket ingest and settlement

Details and API specifics: `POLYMARKET_RESEARCH.md`.

- **Discover** (every 15 min): for each league tag and type `moneyline`/`spreads`/`totals`, list `closed=false` markets starting within 7 days; upsert into `markets`. Parse `outcomes`/`outcomePrices` (JSON in JSON).
- **Refresh** (every 2 min, only markets with open offers or unsettled bets): `GET /markets/{id}`; update start time, closed, uma status, prices.
- **A market is takeable** only if `now < game_start`, `closed = false`, and `acceptingOrders = true`.
- **Finality** (settle only when all hold): `closed = true` AND `umaResolutionStatus = "resolved"` AND `outcomePrices` is exactly `[1,0]`/`[0,1]` (winner) or `[0.5,0.5]` (void). Unknown values → stay pending and get logged.
- **`settle_market`** (idempotent): locks the market row; if `state` is already `final`/`void` it returns without doing anything; otherwise it pays every `pending` bet, flips each bet's status in the same transaction (a bet can only leave `pending` once), updates W-L/lifetime stats, writes feed items and push jobs. Running it twice is a no-op.
- **Void (50/50)**: each side gets back its own stake; no W-L or score effect.
- **Pending-state labels** shown to users: *Game not started*, *In progress / game final — awaiting official result* (game start passed, not yet final), *Result proposed* (`proposed`), *Result disputed — may take several days* (any non-resolved status after proposal), *Settled*.
- Per CLAUDE.md, **waiting is unlimited**.

## 7. Buybacks

- **Busted** = `available + escrow = 0`.
- Policies: **unlimited**; **N per week** (rolling 7 days from the member's earlier buybacks in this season); **by vote** (member requests, group votes — §8).
- Amount: group setting, default = starting balance. Each buyback is a ledger `buyback` mint plus a `feed_item`; counts and coins add to `buyback_count` / `buyback_coins`.

## 8. Votes

- Any active member can call a **reset** vote or (vote-policy groups) a **buyback** vote; a busted member requests their own buyback vote. Only one open vote of each kind per group (per subject for buyback).
- **Window: 24 hours** (**decided**). Caller's yes is counted automatically.
- **Pass rule (decided):** when the window closes, a vote passes if **yes > no among votes cast** AND a **quorum** was reached. Tie fails. Quorum = `min(active members, max(2, ceil(25% of active members)))` votes cast (so a 2-0 vote can't reset a 20-person group: it needs 5 voters; a 1-person group needs 1). It also closes **early** once yes votes exceed half of *all* active members (it can't be overturned).
- **Reset passing** (one transaction): cancel every open offer and refund unfilled shares → void all unsettled bets and refund both sides (including games already ended but not finalised) → snapshot standings to `season_standings` and add each member's season net profit and W-L to their lifetime totals → burn old balances, mint fresh starting balances, clear buyback counts → start season N+1.
- During an open reset vote betting continues, with a group-wide banner (per CLAUDE.md).
- Buyback vote passing grants the buyback to the requester immediately.

## 9. Leaderboard and global score

- **Net profit** = `available + escrow − starting_balance − buyback_coins` (escrow counts as the member's money, so open positions don't distort it).
- **Raw balance** = `available + escrow`, with buyback count next to the name.
- **Global lifetime score** = Σ over live groups of current net profit + `profiles.lifetime_closed_profit` (adds each finished season and each group left). Also lifetime W-L (void bets excluded).
- Because escrowed coins count as the member's money, a bet doesn't change anyone's net profit until it settles.

## 10. Friends

Username search → request → accept. Suggestions: people who share a group with you and aren't yet friends (shown by username/display name). Users can block anyone; a blocked user's content disappears for the blocker and they can't friend them. Friends leaderboard shows only accepted friends' global score and W-L. **Decided: yes.**

## 11. Safety, privacy, App Store

- **Moderation**: report on any comment/user; block and mute; server-side word filter on `comments.body` (blocked list in a table, rejects on insert); comments from blocked users hidden by RLS. **How you act on reports**: simplest version is a `reports` table you review in the Supabase dashboard, plus a SQL view `open_reports`; you set `hidden = true` on a comment or ban a user (`profiles.banned`). Apple expects action within 24 hours, so I'll add an email alert to you per new report (needs a free email service later; optional in v1). **Decided: yes.**
- **Leaving a group**: allowed only after your open offers are cancelled (automatic) and you have no unsettled bets in that group; your remaining balance is burned (`leave_burn`) and your net profit is added to lifetime totals. **Decided:** leaving is blocked while you have unsettled bets.
- **Account deletion** (in app): cancels offers; voids unsettled bets (refunding opponents); burns remaining balances; anonymises: `profiles` row becomes "Deleted user", name/username/tokens/friendships/blocks removed, comments replaced with `[deleted]`; ledger and bets keep an anonymous user id so every group still balances.
- **In-app legal text**: "Fade coins are free play money with no cash value. They can't be bought, sold, or redeemed." plus a problem-gambling help link (1-800-GAMBLER / ncpgambling.org). Shown at onboarding, in group creation, and in Settings.
- **Age rating**: expect the highest tier (17+/18+, simulated gambling); the app asks users to confirm they are 18 or older, which satisfies either. Privacy policy URL and privacy manifest are needed before TestFlight external testing. Full audit at the end per CLAUDE.md.
- **Sign in with Apple**: we store Apple's user id and optional private-relay email only if you want it; none required. App Store requires deletion also revoking the Apple token (Edge Function; M11).
- **Security**: RLS everywhere; secrets (APNs key, service role) only in Supabase; the app holds only the public anon key.

## 12. Push notifications

APNs via an Edge Function (token-based `.p8` key — requires the paid Apple Developer account). Types: new offer in my group, my offer taken, my bet settled (result + balance), vote called, vote passed/failed. One toggle per type. Not sent to the person who caused the event, or to users who blocked them.

## 13. Testing approach

- SQL tests (pgTAP or plain scripts) for every coin function, including: double-settle, concurrent takes of the last share, taking own offer, over-spend, cancel after partial fill, reset with pending bets.
- Randomised "fuzz" run that performs thousands of operations then runs all integrity checks.
- Swift unit tests for odds conversion and coin formatting.
- Settlement tests against saved real JSON (resolved, 50/50, proposed).

## 14. Decisions (answered 2026-10-08)

1. iOS 17 minimum — **yes**.
2. Polymarket Terms OK to read the public API — **yes** (owner confirmed). The ingest stays a swappable module.
3. Vote quorum — **yes**, formula in §8.
4. Vote window — **24 hours**.
5. Rejoining a group — **0 coins**.
6. Leaving with unsettled bets — **blocked**.
7. Friends: username requests + shared-group suggestions — **yes**.
8. Moderation via Supabase dashboard + optional email alert — **yes**.
9. App name **Fade**. No domain yet. **Bundle ID: `com.dschermer.fadeapp`** (proposed from the GitHub handle; changeable until the first TestFlight upload). Because there's no domain, v1 development uses a **custom URL scheme** `fade://join/CODE` plus manual code entry for invites. Real universal links (`https://…/join/CODE`) need a domain you own and are moved to Milestone 10/12; a free GitHub Pages site can host the privacy policy in the meantime.
