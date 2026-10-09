# Fade — MILESTONES

Each milestone builds and runs, ends with exact steps for you to test in the simulator, then a git commit. The plan was approved; work proceeds milestone by milestone.

| # | Milestone | You'll need | You'll test |
|---|---|---|---|
| 0 | **Approve plan.** Answer the [DECIDE] list in SPEC §14; confirm Polymarket terms. Repo scaffolding: `.gitignore`, folder layout. | — | — |
| 1 ✅ | **Backend foundation.** Supabase project; schema + RLS for profiles, groups, members, seasons, ledger; integrity-check functions; SQL tests. Xcode project skeleton with the in-app legal "no real money" screen and dev-only login. | **Supabase account (free)** | App launches; dev login; legal text and help link visible |
| 2 ✅* | **(Debug email login tested; the Apple button is untested until the paid account is active)** **Real sign-in + profile.** Sign in with Apple, username, price-format setting. | **Apple Developer account ($99/yr)** + real device for Apple sign-in | Sign in, pick username, switch ¢/American |
| 3 ✅ | **Groups.** Create (balance/buyback settings), join by code, member list, starting-balance grant, per-group balance. | — | Create a group, join from a second dev user. (Invite links that open the app directly arrive in M10; M3 uses the code.) |
| 4 ✅ | **Polymarket ingest.** Discover/refresh jobs, `markets` table, Markets browser with league filter and game detail. Saved-JSON tests. | Polymarket terms OK | See real upcoming NBA/NFL/MLB/NHL games |
| 5 ✅ | **Offers & takes.** `post_offer`, `take_offer`, `cancel_offer`, auto-cancel at start, confirm sheets with risk/payout, odds-format conversion, My Bets. Concurrency + fuzz tests. | — | Post an offer, take part of it as another user, cancel the rest, balances change |
| 6 ✅ | **Settlement.** Finality rule, idempotent `settle_market`, void handling, status labels, W-L. Tests with resolved/50-50/proposed JSON. | — | A finished game settles; balances and W-L update |
| 7 ✅* | **Leaderboard, buybacks, global score.** Net-profit and raw-balance views, unlimited/weekly buybacks, profile score. **Also added here (agreed with you):** leaving a group and handing over ownership. | — | Go broke, buy back, see ranking; leave a group |
| 8 🚧 | **Votes.** Reset and buyback votes, tally, banner, reset transaction, season history. *(Built and tested in SQL, including race tests; Swift screens not yet compiled — see TESTING.md §3.)* | — | Call and pass a reset; see history |
| 9 🚧 | **Feed & UGC safety.** Feed, reactions, comments, report/block/mute, word filter, moderation tools for you (SQL editor: `supabase/ops/moderation.sql`). *(TESTING.md §4–5.)* | — | Comment, react, report, block |
| 10 🚧 | **Friends.** Requests by username, suggestions from shared groups, friends leaderboard. *(Invite links: the app understands `fade://join/CODE`, but a tappable universal link needs a domain you don't have yet — see docs/APPLE_ACCOUNT_STEPS.md §10.)* (TESTING.md §6.) | Domain (≈$12/yr) only for universal links, optional | Add a friend |
| 11 🚧 | **Push notifications + account deletion.** Notification queue and per-type toggles (tested without Apple), in-app account deletion, Edge Functions for sending pushes and for Sign-in-with-Apple token revocation. *(Delivery and revocation are written but unproven until the paid account exists — TESTING.md §7–8, §12.)* | APNs key from your paid Apple account (for delivery only) | Toggle notifications; delete an account |
| 12 🚧 | **App Store prep.** Privacy manifest, app icon, launch screen, support/privacy/terms pages (`docs/`, GitHub Pages), listing text, age-rating and privacy answers, reviewer notes, step-by-step Apple-account guide. *(You still: fill the page placeholders, switch Email login OFF before TestFlight, TestFlight upload.)* | App Store Connect, **paid account** | Read the docs; install via TestFlight later |
| 13 🚧 | **App Review audit.** `docs/APP_REVIEW_AUDIT.md`: guideline-by-guideline review, fixes made, and your "before you submit" list. Includes a **permission lockdown** (migration 0014) with an automated test that compares real permissions against an allow-list. | — | Read the audit; run TESTING.md §9 |

\* Migrations 0007 and 0008 are applied on your Supabase, but you haven't reported the results of the buyback / leave-group taps; the steps are still in SETUP.md (top two sections) if you want to run them.

**Status key:** ✅ built, tested, and you ran it · 🚧 built and automatically tested, **waiting for your hands-on test** (everything in TESTING.md).

**Tomorrow's checklist is `TESTING.md`.**

**Why this order:** the money logic (M1, M5, M6) comes first and is heavily tested before features sit on top. The simulator-only path works through M5; only M2 and M11 need real Apple services.

## UI redesign (after Milestone 13)

The design lives in the "Fade App Design" canvas (31 boards, link in CLAUDE.md). It is built in steps; each step builds and runs, ends with what to tap, then a commit. Screens not yet converted keep working in their old look.

| # | Step | What changes | Server change |
|---|---|---|---|
| R1 🚧 | **Look + shell + Feed.** Colors/fonts/components, the 5-tab floating bar, the combined Feed with group chips, post screen with comments, the new report sheet. | Feed tab is new; the other tabs still open the old screens (Groups tab = old home). | Migration 0015 (group name etc. on the feed view) |
| R2 🚧 | **Games.** Games tab with Spread / Total / Win best-price cells, order-book sheet, full game page, make-offer and take-offer sheets. | Games tab | Best open offer per market |
| R3 🚧 | **Bets and Groups.** Bets tab, Groups tab, group page (leaderboard, members, invite), votes, buyback and leave sheets. | Bets + Groups tabs | — |
| R4 | **Me and the rest.** Me tab, friends, settings, notifications, blocked list, delete account, About & help, sign-in, username, empty states. | Me tab | — |
| R5 | **Polish.** Light-mode pass, accessibility pass, independent code review, TESTING.md rewrite. | — | — |

**Not planned for v1:** Android, live betting, parlays, player props, real-money anything, public groups, full group chat, websocket streams (possible later upgrade).
