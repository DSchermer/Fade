# Fade — Project Context

## About me and how to work with me
- I'm a mechanical engineer, not a professional developer. I build tools with AI, so explain decisions briefly in plain language and keep the architecture as simple as the requirements allow.
- I have a Mac with Xcode and I'm using Claude Code. I do **not** yet have an Apple Developer account or a Supabase account. Tell me exactly when each one becomes necessary and walk me through setting it up.
- **Plan before code.** Before writing any code, produce `SPEC.md` (screens, data model, user flows, coin math, settlement logic) and `MILESTONES.md`. Wait for my approval.
- Build in milestones. Each one must build and run. When a milestone is done, tell me exactly what to tap in the simulator to test it, then commit to git.
- Keep this file updated with decisions we make. If a requirement here is ambiguous or seems wrong, ask me instead of guessing.

## What Fade is
A free social betting app for friend groups. It replaces real-money sports gambling with play-money coins. Friends post their own odds on real sports outcomes, other group members take or leave those bets, and everyone competes on group leaderboards. The name comes from the betting slang "fade": taking the other side of someone's pick.

**Hard rule: no real money, ever.** Coins are free, can't be purchased, can't be cashed out, can't be transferred outside a group, and have no prizes or cash value. No in-app purchases in v1, and the app is free.

## Stack
- iOS only, **SwiftUI**, targeting a recent iOS version (recommend which one).
- **Supabase**: Postgres, Auth, Realtime, Edge Functions, scheduled jobs.
- **Sign in with Apple** as the only login method.
- APNs for push notifications.
- The server is authoritative for all coin movement (see Integrity rules).

## Events and resolution: mirror Polymarket
- Users bet on **sports markets mirrored from Polymarket**. v1 scope is the major US leagues (NFL, NBA, MLB, NHL) with basic market types only: moneyline/winner, spread, and over/under. No parlays and no player props.
- Ingest market listings, event start times, and resolution status from Polymarket's public APIs. **Before building this, research Polymarket's current public API docs and terms of use.** Confirm that our usage is allowed and identify the endpoints for listing sports markets, start times, and final resolution. Report back to me before implementing.
- Bets resolve from Polymarket's outcome. **Always wait for final resolution.** If a market is delayed or disputed, bets stay pending until Polymarket finalizes, however long that takes.
- **How Polymarket resolution works** (from https://docs.polymarket.com/concepts/resolution, so verify against the current docs):
  - A proposer submits an outcome to UMA's Optimistic Oracle, which opens a 2-hour challenge window. If nobody disputes, the market resolves in about 2 hours.
  - If the proposal is disputed, a second proposal round follows. A second dispute goes to a UMA token-holder vote after a debate period. A disputed market takes about 4–6 days to resolve, and some markets resolve days or weeks after the game.
  - Possible end states: one outcome wins (pays 1.00/0.00); **50/50** (both outcomes pay 0.50, used for cancelled or abandoned events); or "too early," which sends the market back for a new proposal.
- **Finality rule for Fade:**
  - Settle only when the market is closed **and** its UMA resolution status is resolved/settled **and** the outcome prices are terminal (1/0 or 0.5/0.5).
  - "Proposed" and "disputed" are never final. A closed market with no resolution data is not final either.
  - Before building settlement, confirm the exact field names in the current Gamma/CLOB API reference (likely `closed`, `umaResolutionStatus`, `outcomePrices`). Show me example JSON from a real resolved, disputed, and 50/50 market.
- **50/50 handling: treat it as a void.** Refund each side exactly the stake it put up, the same as a sportsbook "no action." Don't mirror Polymarket's 0.50 per-share payout. Voids don't count toward W-L or the global score.
- Show pending bets on games that have ended with a clear status, such as "Game final — awaiting official result" and "Result disputed — may take several days," so nobody thinks the app is broken.
- Polymarket prices are not used to set odds. Odds come from users (see below).
- **Realtime feeds (reference: https://docs.polymarket.com/market-data/realtime-data):**
  - Market stream `wss://ws-subscriptions-clob.polymarket.com/ws/market`. With `custom_feature_enabled: true`, it emits `new_market` and `market_resolved` (`winning_asset_id`, `winning_outcome`). It requires a `PING` every 10s.
  - Sports stream `wss://sports-api.polymarket.com/ws`. It needs no subscription and pushes every game update (`gameId`, `leagueAbbreviation`, `status`, `live`, `ended`, `score`, `finishedAt`). It replies `pong` to the server's `ping`. Polymarket labels it informational only and says it may be delayed.
  - **v1 approach:** settle from a **scheduled polling job** against Polymarket's REST APIs, which is the source of truth. Supabase Edge Functions are short-lived and can't hold a websocket open, and a dropped connection would silently miss a resolution. Treat the websockets as optional later upgrades: the market stream as a faster settlement trigger and the sports stream for live scores in the app. Either would need a small always-on worker. Polling must still back them up.
  - Before relying on `market_resolved` or any REST resolution field, confirm it means **final** resolution (past any dispute window), since we always wait for finality.

## Groups
- Anyone can create a group. People join by invite link or code (use universal links/deep links). There's no member cap.
- A user can be in multiple groups. **Balances are per group.** Each group is its own economy.
- The creator configures these at setup:
  - **Starting balance**, default 100 coins.
  - **Buyback policy**, one of: unlimited buybacks; N buybacks per week; or buyback by group vote.
  - **Buyback amount**, default equal to the starting balance.
- Seasons are **rolling** with no end date. A group resets only by vote (see Votes).

## Offers (maker/taker, share-based)
- Offers are denominated in **shares**. Each share pays **1 coin** to whoever is right. There's no platform cap on size; the maker's own balance is the only limit.
- A **maker** posts an offer on a mirrored market with three things: the side they're backing, a price (1–99¢), and a number of shares. Example: "Bills win, 60¢, 100 shares." Per share, the maker puts up 60¢ and a taker puts up 40¢, so each share is a 1-coin pot.
- **Takers** fade the maker by buying any whole number of the remaining shares, from 1 up to everything that's left. Multiple takers can fill one offer. Example: a taker buys 50 shares. The taker puts up 20 coins (50 × 40¢), the maker's 30 coins (50 × 60¢) are matched against it, and the winner collects 50 coins. The other 50 shares stay open for others.
- Escrow: when an offer is posted, the maker's full cost (shares × price) is escrowed. Each take escrows the taker's cost. Before confirming, show both sides their exact risk and potential payout.
- The maker can cancel unfilled shares at any time before event start, and the escrow for those shares is refunded. Shares already taken stand. **Unfilled shares cancel automatically at event start. There is no live betting.**
- The price is entered and displayed in the **user's choice** of format: probability/cents (60¢) or American odds (-150 / +150), set in settings. Store the price as integer cents and convert only for display. When American odds don't map exactly to a whole cent, round to the nearest cent and show the user the actual price before they confirm.
- **Coin precision:** store all balances and amounts as integer hundredths of a coin, and display coins with up to two decimals. Because prices are whole cents and shares are whole numbers, every fill is exact: the two sides' stakes always add up to exactly the shares in the pot, with no rounding. Fade never creates or destroys coins through betting. Add a check for this.
- A user can be both a maker and a taker, but never on their own offer.

## Balances, going broke, buybacks
- A member can't stake more than their available (non-escrowed) balance. Balances never go below zero.
- A member is "busted" when available balance plus escrowed coins equals zero. Only then are they eligible for a buyback under the group's policy.
- Every buyback is recorded and visible to the group.

## Global score (not a wallet)
- All betting uses **per-group balances**. There are no spendable global coins.
- Each user also has a **global lifetime score**: net profit summed across all their groups, using the same net-profit definition as the leaderboard (buyback coins count against you). The score persists through group resets and when a user leaves a group. Also show a lifetime W-L record.
- Show the global score on the user's profile and on a **friends leaderboard** that ranks the people you've added as friends.
- Friends: users send friend requests by username, and Fade suggests people they share groups with. Confirm this approach in the spec.

## Votes
- **Any member can call a vote.** Vote types: group reset, and buyback request (for groups using the vote policy).
- A vote passes by **majority of voters** within a voting window. Propose a default window length (e.g. 24h).
- **Reset**: everyone returns to the starting balance and buyback counts clear. Leaderboards start over. Keep past seasons viewable as history if it's simple to do.
  - **During a reset vote**, betting continues as normal. Show a group-wide banner warning that if the reset passes, all unsettled bets will be voided and refunded.
  - **When a reset passes**, the following happens in one transaction. First, cancel every open offer and refund the unfilled shares. Next, void every unsettled bet and refund each side's stake, including bets on games that have ended but that Polymarket hasn't finalized. Finally, snapshot the season into history and reset balances. This is intentionally simple, and we accept that someone losing a pending bet could vote for a reset to escape it.
  - Voided bets don't count toward the W-L record or the global score.

## Leaderboard
Two views with a toggle:
1. **Net profit**: balance minus starting balance minus all buyback coins received. Buybacks count against you.
2. **Raw balance**, with each member's buyback count shown next to their name.

## Social feed
- Each group has a feed of activity: offers posted, offers taken, and settled results.
- Members can add **emoji reactions and comments** on feed items.
- Because comments are user-generated content, include what Apple requires: report content, block users, mute, a basic objectionable-content filter, and a way for me as the developer to act on reports.

## Push notifications (v1)
- A new offer was posted in my group
- My offer was taken (partial or full)
- My bet settled, with the result and new balance
- Votes: a vote was called, and a vote passed or failed
Users can turn each type on or off.

## Integrity rules (non-negotiable)
- Clients never write balances directly. All coin movements happen in server-side Postgres functions/Edge Functions inside transactions: post, take, cancel, settle, buyback, and reset.
- Use an append-only **ledger** of coin movements. Balances must be derivable from the ledger. Add a check that each group's coins balance out.
- Use Row Level Security on every table. Members can see only their own groups.
- Settlement runs server-side on a schedule and is idempotent, so running it twice never pays twice.
- No API keys or secrets in the app binary.

## App Store requirements (build these in; we'll audit the rest later)
- In-app account deletion, which must also delete or anonymize the user's server data.
- A privacy policy URL and a privacy manifest.
- The comment moderation tools listed under Social feed.

## Out of scope for v1
Android, live betting, parlays, player props, any real-money purchase or prize, public/discoverable groups, and a full group chat.

## Decisions log
- 2026-10-08: iOS 17 minimum. Bundle ID `com.dschermer.fade`. App name "Fade". No domain yet: invites use `fade://join/CODE` + manual code until a domain exists.
- Polymarket public API use approved by owner; settle only on `closed` + `umaResolutionStatus == "resolved"` + terminal prices (see `POLYMARKET_RESEARCH.md`).
- Votes: 24h window; pass = yes > no with quorum `min(members, max(2, ceil(25% of members)))`; early close when yes > half of all members.
- Rejoining a group gives 0 coins. Leaving is blocked while you have unsettled bets in that group.
- Friends: username requests + shared-group suggestions. Moderation: Supabase dashboard + optional email alert.
- Specs live in `SPEC.md` and `MILESTONES.md`; the plan is approved and work proceeds milestone by milestone.
- Milestone 2 (sign-in): native Sign in with Apple via Supabase `signInWithIdToken` (no name/email requested). Username is picked once after first sign-in, stored lowercase, can be changed. A DEBUG-only email+password login exists for multi-user testing; **the Supabase Email provider must be switched OFF before TestFlight** (Apple is the only real login).
- Milestone 4 (games): ingest runs inside Postgres (`http` extension + `pg_cron`), no Edge Function needed; logic is tested against real saved Polymarket JSON in `supabase/tests/fixtures/`. All alternate spread/total lines are stored; the app shows the line nearest 50/50 first (prices are used only for that ordering). Finality rule is implemented once in `market_resolution()` and a final result never changes.
- Milestone 5 (offers): all coin movement in `post_offer` / `take_offer` / `cancel_offer` / `auto_cancel_started` (SQL). Lock order is always offer row → one member row, so concurrent users can't deadlock. Table CHECKs back the functions up (stakes sum to shares × 100, no self-bets, no negative balances). Tested with a random 4,000-operation run (thousands of posts/takes/cancels, game start, early market close) and real parallel connections (`supabase/tests/concurrency_test.sh`). `check_betting_integrity()` ties each member's escrow to their open offers + unsettled bets. Tests use a `clock_override` table to set "now" (empty in production).
- Milestone 6 (settlement): `settle_market()` pays a bet only when `market_resolution()` says final; winner takes the whole pot, 50/50 refunds each side's own stake; each bet is paid once (`for update skip locked` + status check; also verified by 12 simultaneous callers). Any offer still open on a finished market is returned first. Win-loss record counts per bet (each take is one bet) and ignores voids. `check_betting_integrity()` also verifies bet results vs. the market result, exact payouts per side, and the win-loss records. Schedule: `settle_resolved_markets()` every minute.
- Milestone 7 (leaderboard/buybacks/score): net profit = balance − `granted` − `buyback_coins` (both maintained by the ledger trigger, so the leaderboard can't drift from the ledger); every group's net profits must sum to exactly 0 (new integrity check). `claim_buyback` locks the member row (proved by a race test: without the lock 10 simultaneous claims all paid), requires available+escrow = 0, enforces the weekly limit as a rolling 7 days within the current season, and refuses vote-policy groups until Milestone 8. Global score = `lifetime_closed_profit` + live net profit over active memberships (`my_score` view). Leaving a group (and its owner rule) is still undecided/unbuilt — when built it must burn the balance and reset `granted` and `buyback_coins` to 0 so the zero-sum check holds.
- Leaving & ownership (decided 2026-10-09, built after Milestone 7): an owner can't leave while other members remain — they hand ownership over first (`transfer_ownership`); sole owner may leave (the empty group's code then stops working). Anyone else can leave unless they have unsettled bets (open offers are cancelled and refunded automatically); balance is burned (`leave_burn`), net profit moves into `profiles.lifetime_closed_profit` and is recorded on the member row as `realized_profit`, and the baseline (`granted`, buyback counters) is cleared. Rejoining = 0 coins. Integrity: every group's `net profit + realized_profit` sums to 0; leavers hold nothing; each person's closed profit equals the sum of their `realized_profit` (season resets in Milestone 8 must also record `realized_profit` the same way).
