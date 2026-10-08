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
- Polymarket prices are not used to set odds. Odds come from users (see below).

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
- **Reset**: everyone returns to the starting balance and buyback counts clear. Leaderboards start over. Keep past seasons viewable as history if it's simple to do. Open question for the spec: what happens to open offers and pending bets at reset time. Propose options.

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

## App Store readiness (plan for it from milestone 1)
- Review App Store Review Guidelines for simulated gambling and social casino-style apps. Determine the correct age rating through the App Store Connect questionnaire, and expect 17+ for simulated gambling. Make sure the app clearly reads as free play money with no real-money value.
- Include a statement in the app that coins have no monetary value and can't be redeemed, plus a link to problem-gambling help resources.
- In-app account deletion, which must also delete or anonymize server data.
- Privacy policy URL, App Privacy answers, and a privacy manifest.
- UGC moderation tools (see Social feed).
- App icon, launch screen, screenshots, and description.
- TestFlight beta with my friend group before submission.
- At the end, audit the project as an App Store reviewer would: list likely rejection reasons and fix them.

## Out of scope for v1
Android, live betting, parlays, player props, any real-money purchase or prize, public/discoverable groups, and a full group chat.
