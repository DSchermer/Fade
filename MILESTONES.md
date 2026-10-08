# Fade — MILESTONES (draft for approval)

Each milestone builds and runs, ends with exact steps for you to test in the simulator, then a git commit. Nothing starts until you approve `SPEC.md` and this file.

| # | Milestone | You'll need | You'll test |
|---|---|---|---|
| 0 | **Approve plan.** Answer the [DECIDE] list in SPEC §14; confirm Polymarket terms. Repo scaffolding: `.gitignore`, folder layout. | — | — |
| 1 | **Backend foundation.** Supabase project; schema + RLS for profiles, groups, members, seasons, ledger; integrity-check functions; SQL tests. Xcode project skeleton with the in-app legal "no real money" screen and dev-only login. | **Supabase account (free)** | App launches; dev login; legal text and help link visible |
| 2 | **Real sign-in + profile.** Sign in with Apple, username, price-format setting. | **Apple Developer account ($99/yr)** + real device for Apple sign-in | Sign in, pick username, switch ¢/American |
| 3 | **Groups.** Create (balance/buyback settings), join by code, member list, starting-balance grant, per-group balance. | — | Create a group, join from a second dev user |
| 4 | **Polymarket ingest.** Discover/refresh jobs, `markets` table, Markets browser with league filter and game detail. Saved-JSON tests. | Polymarket terms OK | See real upcoming NBA/NFL/MLB/NHL games |
| 5 | **Offers & takes.** `post_offer`, `take_offer`, `cancel_offer`, auto-cancel at start, confirm sheets with risk/payout, odds-format conversion, My Bets. Concurrency + fuzz tests. | — | Post an offer, take part of it as another user, cancel the rest, balances change |
| 6 | **Settlement.** Finality rule, idempotent `settle_market`, void handling, status labels, W-L. Tests with resolved/50-50/proposed JSON. | — | A finished game settles; balances and W-L update |
| 7 | **Leaderboard, buybacks, global score.** Net-profit and raw-balance views, unlimited/weekly buybacks, profile score. | — | Go broke, buy back, see ranking |
| 8 | **Votes.** Reset and buyback votes, tally, banner, reset transaction, season history. | — | Call and pass a reset; see history |
| 9 | **Feed & UGC safety.** Feed, reactions, comments, report/block/mute, word filter, moderation view for you. | — | Comment, react, report, block |
| 10 | **Friends.** Requests, suggestions, friends leaderboard. Invite links as universal links. | Domain (≈$12/yr) for universal links | Add a friend; open an invite link |
| 11 | **Push notifications + account deletion.** APNs, per-type toggles, Sign-in-with-Apple token revoke, in-app deletion. | APNs key from your Apple account | Receive pushes on device; delete an account |
| 12 | **App Store prep & TestFlight.** Privacy policy, privacy manifest, icon, launch screen, age rating, screenshots, description; TestFlight beta with your friends. | App Store Connect | Install via TestFlight |
| 13 | **App Review audit.** I review as an App Store reviewer, list likely rejections, fix them, then submit. | — | — |

**Why this order:** the money logic (M1, M5, M6) comes first and is heavily tested before features sit on top. The simulator-only path works through M5; only M2 and M11 need real Apple services.

**Not planned for v1:** Android, live betting, parlays, player props, real-money anything, public groups, full group chat, websocket streams (possible later upgrade).
