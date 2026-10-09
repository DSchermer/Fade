# Setup — Milestone 7 (leaderboards, buybacks, global score)

## 1. Supabase
`pbcopy < ../supabase/migrations/20261008000007_buybacks_leaderboard.sql` → new query → paste → Run. (No scheduled job this time.)
Check: `select * from check_ledger_integrity();` and `select * from check_betting_integrity();` — **no rows**.

## 2. App
`git pull`, `cd ios && xcodegen`, Run.

## What to tap to test Milestone 7
**Leaderboard**
1. Open a group → **Leaderboard**. You should see every member ranked. Toggle **Net profit** / **Raw balance**.
   - *Net profit* = what you hold now − your starting coins − buyback coins. Winners are green (+), losers red (−). Everyone's net profits add up to 0.
   - *Raw balance* shows what each person holds, with "(N buybacks)" next to their name if they bought back.

**Buyback (unlimited group — the one you made first)**
2. Get one account broke. Easiest: make a bet, then pretend you lost it with `dev_force_result.sql`, or as the loser post an offer for ALL your available coins, let the other account take it all, then force the result so you lose. (You are only "broke" when available coins **and** coins tied up in bets and offers are all zero.)
3. As the broke account, open the group: an orange **You're out of coins** box appears with **Buy back in for 100 coins**. Tap it → confirm. Your balance becomes 100 again.
4. **Leaderboard**: you now show "1 buyback · 100 coins" and your **net profit is still negative** — a buyback does not wipe out a loss.
5. At the bottom of the Leaderboard, **Buyback history** lists who bought back and when (everyone in the group can see it).
6. You cannot buy back while you still have coins (the box is simply not shown).

**Weekly limit** — create a group with *Limited per week* (say 1 per week); go broke twice. The second time the box says you've used your buyback for the week and shows when the next one is available.

**By vote groups** — a broke member sees "This group lets members vote on buybacks. Voting arrives in a later update." (Milestone 8.)

**Global score**
7. Gear → Settings: **Lifetime score** (net profit added up across ALL your groups; buybacks count against you) and **Record (won–lost)**.

---

# Setup — Milestone 6 (settling bets)

## 1. Supabase (copy each file with `pbcopy`, paste into a new query, Run)
1. `pbcopy < ../supabase/migrations/20261008000006_settlement.sql`
2. `pbcopy < ../supabase/ops/schedule_settlement.sql` — schedules the job that pays out finished games every minute. It prints a job number.
3. Check both: `select * from check_ledger_integrity();` and `select * from check_betting_integrity();` — **no rows**.

## 2. App
`git pull`, `cd ios && xcodegen`, Run.

## What to tap to test Milestone 6
**A. Fast test (pretend Polymarket finished a game).** You need a bet between two accounts first (Milestone 5 steps; use a game that hasn't started).
1. In Supabase run this to find the bet's market id:
   `select m.id, m.event_title, m.question, count(*) as pending_bets from public.bets b join public.markets m on m.id = b.market_id where b.status = 'pending' group by 1, 2, 3;`
2. `pbcopy < ../supabase/ops/dev_force_result.sql`, paste into a new query, replace `PASTE-MARKET-ID-HERE` with that id (keep the quotes), leave `outcome_0` (first side listed wins) or change it to `outcome_1` / `void`, Run. The two result tables at the bottom must say 0 rows.
3. In the app, open the group → **My bets** (pull down to refresh). The bet moved to **Settled** and says **Won +… coins** (green) or **Lost -… coins** (red). Check balances on the group screen: the winner collected the whole pot; the loser's tied-up coins are gone; any unfilled shares were returned.
4. Gear → Settings: **Record (won–lost)** shows 1–0 for the winner and 0–1 for the loser.
5. Repeat with a different bet and choose `void`: **Voided — stakes refunded**, both balances back to what they were, and the record does not change.
6. Run the same file again with the same market: nothing changes (a bet is never paid twice).

**B. Real test (recommended before you trust it).** Place a small bet between your test accounts on a game that starts tonight. After the game ends, Polymarket usually finalizes within a couple of hours; the app settles it on its own within about 6 minutes of that. Until then **My bets** shows "Game started — awaiting official result".

**What should NOT happen:** a bet on a game that is over but not yet final (Polymarket "proposed" or "disputed") must stay pending, with its coins still set aside.

---

# Setup — Milestone 5 (offers and bets)

## 1. Supabase (SQL Editor, copy each file with `pbcopy` as before)
1. `pbcopy < ../supabase/migrations/20261008000005_offers.sql` → new query → paste → **Run**. (From the repo root drop the `../`.)
2. `pbcopy < ../supabase/ops/schedule_auto_cancel.sql` → new query → paste → **Run**. It schedules the job that cancels unfilled shares when a game starts (every minute). It prints a job number.
3. Check: `select * from check_ledger_integrity();` and `select * from check_betting_integrity();` — both must return **no rows**.

## 2. App
`git pull`, `cd ios && xcodegen`, Run. (xcodegen now also creates a test target; ignore it for now.)

## What to tap to test Milestone 5 (you need TWO accounts: test1 and test2, both in the same group)
Use the simulator: sign in as `test1@example.com`, later sign out and sign in as `test2@example.com` (both are in the group from Milestone 3; if test2 isn't, join with the code).

**As test1 (the maker):**
1. Open the group → **Browse games** → pick a game starting later than now → tap **Moneyline** (or any line).
2. Tap **Make an offer**. Pick a side, type a price of `60` and `100` shares. The screen should say: **You risk 60 coins, you win +40 coins, winner collects 100 coins.** (If you only have 100 coins it will say you can afford it; try 200 shares and watch it refuse: "You only have … available".)
3. Tap **Post**. Back on the group screen: **Available** drops by 60 and **Tied up in offers & bets** shows 60.
4. Group → **My bets**: your offer is listed with "Cancel 100 unfilled shares".

**As test2 (the taker):**
5. Sign out (gear → Sign out), sign in as `test2@example.com`, open the group → **Open offers**: you see test1's offer ("@test1 backs …, 60¢, 100 of 100 shares left").
6. Tap it. Set **Shares: 50**. The screen should say **You risk 20 coins, you win +30 coins; @test1 risks 30 coins; winner collects 50 coins.** Tap **Confirm**.
7. Your available coins drop by 20. **My bets** shows the bet: "Waiting for the game to start".

**Back as test1:**
8. **My bets**: the offer now says "50 of 100 shares left" and "50 shares already taken — those bets stand", and the bet appears under **Your bets**.
9. Tap **Cancel 50 unfilled shares** → confirm. You get 30 coins back; the 30 coins in the bet stay tied up.

**Rules to try:**
10. As test1 open your own offer from a market screen: tapping it does nothing (you can't take your own offer).
11. Switch the price format (gear → Price format → American), reopen Make an offer: type `-150` — it should show **Actual price: 60¢ (-150)**.
12. In the SQL Editor run both integrity checks again: still **no rows**. Also `select sum(available + escrow) from group_members;` should equal 100 coins × the number of members (plus any buybacks) — betting never creates or destroys coins.

---

# Setup — Milestone 4 (real games from Polymarket)

## 1. Supabase (SQL Editor, one query at a time)
1. Paste all of `supabase/migrations/20261008000004_markets.sql` → **Run**.
2. Paste all of `supabase/ops/schedule_market_sync.sql` → **Run**. This switches on two Supabase extensions (`http`, `pg_cron`) and schedules the jobs (games every 15 minutes, start-time/result checks every 5 minutes). If it complains about an extension, turn on **http** and **pg_cron** under **Database → Extensions**, then run it again.
3. Load the first batch of games now (don't wait 15 minutes). Run just this line and be patient — it can take up to a minute:
   `select public.sync_markets();`
   It prints a number (how many markets it stored).
4. Check: `select league, market_type, count(*) from markets group by 1, 2 order by 1, 2;` — you should see rows for nfl/nba/mlb/nhl (depending on the season, some leagues may have none). Then `select * from sync_log order by id desc limit 10;` — the newest row should say `discover` with `ok = true`. If any row has `ok = false`, copy its `detail` text to me.

## 2. App
`git pull`, `cd ios && xcodegen` (re-pick your Personal Team if asked), Run.

## What to tap to test Milestone 4
1. Sign in, open any group, tap **Browse games**.
2. You should see upcoming games grouped by day with start times in **your** time zone, for example "Celtics vs. Cavaliers · NBA · 7:00 PM".
3. Tap the league tabs (**NFL / NBA / MLB / NHL**) — the list filters.
4. Tap a game: **Moneyline**, then **Spread** and **Over / Under** each show one main line, with **More lines (N)** that expands to the alternate lines.
5. Compare one game's start time with polymarket.com's sports page — it should match.
6. Pull down on the list to refresh.
7. Safety check: in the SQL Editor run `select * from check_ledger_integrity();` (no rows) — this milestone doesn't touch coins.

---

# Setup — Milestone 3 (groups)

1. **Supabase → SQL Editor → New query**: paste all of `supabase/migrations/20261008000003_groups.sql` and **Run**.
2. `git pull`, then `cd ios && xcodegen`, open the project (re-pick your Personal Team under Signing & Capabilities if asked), and Run in the simulator.

## What to tap to test Milestone 3
1. Sign in as `test1@example.com` (debug box). The home screen says **No groups yet**.
2. Tap **Create a group**. Name it `Friday Crew`, leave the starting balance at 100, buybacks **Unlimited**, then **Create**. The group appears in the list with **100 coins**.
3. Tap the group. You should see: your balance (100 total, 100 available), an **invite code** (8 letters/numbers), you as the only member marked "owner", and the group rules.
4. Tap **Copy** (button changes to "Copied"). Write the code down.
5. Go back, tap the **gear → Sign out**. Sign in as `test2@example.com` (new account → pick a username if asked).
6. Tap **+ → Join with a code**, type the code (lower case is fine) → **Join**. `Friday Crew` appears with **100 coins**.
7. Open it: **Members (2)** lists both usernames with 100 each.
8. Try **+ → Join with a code** with a made-up code: you should see "No group found with that code."
9. Back as test2, **+ → Create a group** with **Limited per week** (a stepper appears) and the buyback amount toggle off with a different amount (say 50). Open that group and check "Group rules".
10. In Supabase **Table Editor**: `groups` (your two groups), `group_members` (balances), `ledger` (one `grant` row per member). In the SQL Editor run `select * from check_ledger_integrity();` — it must return **no rows**.

---

# >>> STATUS (2026-10-08): paid Apple account not enrolled yet <<<
The Supabase URL and publishable key are already in the app. Until your Apple account is active you can test everything except the Apple button, using the **debug email login** in the simulator:
1. Supabase: run `supabase/migrations/20261008000002_usernames.sql` (SQL Editor). **Authentication → Sign In / Providers → Email**: make sure it is enabled and **Confirm email** is OFF.
2. `git pull`, `cd ios && xcodegen`, open the project, select your Personal Team under Signing & Capabilities (as in Milestone 1), pick a simulator, Run.
3. In the orange "Debug only" box enter `test1@example.com` and a password of 6+ characters → **Sign in / create test account** → pick a username → you land on "Hi, @name". Gear → change price format, sign out, make a `test2@example.com` account and check that reusing test1's username is refused.
4. When the Apple account is active: uncomment the `entitlements` block in `ios/project.yml`, add your Team ID there (`DEVELOPMENT_TEAM`), re-run `xcodegen`, and do section 1 steps 2 and 4 below to test the Apple button on a real iPhone.

---

# Setup — Milestone 2 (real sign-in) — do these on your Mac

## 1. Supabase
1. **SQL Editor → New query**: paste all of `supabase/migrations/20261008000002_usernames.sql` and **Run**. (Milestone 1's file is already applied.)
2. **Authentication → Sign In / Providers → Apple**: switch **Enable Sign in with Apple** on. In **Client IDs** type `com.dschermer.fade`. Leave the secret/key fields empty (they're only for websites). **Save**.
3. **Authentication → Sign In / Providers → Email**: keep it enabled for now but switch **Confirm email** OFF. This is only so debug test accounts work. **Before TestFlight we turn Email OFF completely** (Fade's only real login is Apple).
4. **Project Settings → API** (or **API Keys**): copy the **Project URL** and the **publishable** key (starts with `sb_publishable_…`, or the older `anon` key). Do **not** copy the secret / service_role key anywhere.

## 2. Apple
1. Go to https://developer.apple.com/account → **Membership details** → copy your **Team ID** (10 letters/numbers).
2. Nothing else to configure by hand: Xcode registers the app ID and the Sign in with Apple capability automatically when you build with your team.

## 3. Send me three things in chat
- Supabase **Project URL**
- Supabase **publishable key** (it's meant to be public)
- Apple **Team ID**

I'll put them in `ios/Fade/AppConfig.swift` and `ios/project.yml` and push.

## 4. Build it
1. `git pull`, then `cd ios && xcodegen` and open `Fade.xcodeproj`. The first build downloads the Supabase library (a minute or two).
2. Simulator: you can test the **debug email login** (below). Sign in with Apple also works in the simulator if the simulator is signed into an Apple ID (Simulator → Settings app → Sign in).
3. Real iPhone (recommended for Apple sign-in): plug it in, on the iPhone turn on **Settings → Privacy & Security → Developer Mode** (it restarts), then pick the iPhone in Xcode's device picker and Run. First launch: iPhone **Settings → General → VPN & Device Management** → trust your developer certificate.

## 5. What to tap to test Milestone 2
1. Tap **Sign in with Apple** (real iPhone). After Face ID the **Pick a username** screen appears.
2. Try `ab` (Continue stays disabled), then a valid name such as `yourname`. You land on "Hi, @yourname".
3. Tap the **gear → Price format**: switch to American, close and reopen Settings; it stays. Force-quit and reopen the app: you're still signed in, with the same setting.
4. **Sign out** returns to the sign-in screen. Sign in with Apple again: it goes straight to the home screen (no username prompt).
5. Simulator, debug box: enter `test1@example.com` + a 6+ character password → **Sign in / create test account** → pick a different username. Then sign out and make `test2@example.com`. Try giving it the first user's username: you should see "That username is already taken."
6. In Supabase **Table Editor → profiles** you should see your rows.

---

# Setup — Milestone 1 (do these on your Mac)

## A. Supabase (free) — creates your backend database
1. Go to https://supabase.com → **Start your project** → sign up (GitHub or email is fine).
2. **New project**: name `fade`, set a database password (save it in a password manager), pick the region closest to you, plan **Free**.
3. When it finishes (about 2 minutes) open **SQL Editor** → **New query**.
4. Open `supabase/migrations/20261008000001_foundation.sql` from this repo, paste the whole file in, and click **Run**. You should see "Success. No rows returned".
5. Open **Table Editor**: you should see `profiles`, `groups`, `group_members`, `seasons`, `season_standings`, `ledger`. Each should show an **RLS enabled** badge.
6. (Optional check) In SQL Editor run `select * from check_ledger_integrity();` — it must return **no rows**.

You don't need to copy any keys yet; the app connects to Supabase in Milestone 2.

## B. Xcode app skeleton
1. Install Xcode from the Mac App Store if you haven't (and open it once to accept the license).
2. In Terminal: `brew install xcodegen` (if you don't have Homebrew, tell me and I'll walk you through it).
3. `cd` into this repo, then: `cd ios && xcodegen` — this creates `Fade.xcodeproj`.
4. `open Fade.xcodeproj`. In the left sidebar click **Fade** (blue icon) → **Signing & Capabilities** → tick **Automatically manage signing** and choose your **Personal Team** (your Apple ID; no paid account needed yet).
5. Pick an **iPhone 15** simulator at the top and press **Run** (▶).

## C. What to tap to test Milestone 1
1. The sign-in screen shows "Fade", "Bet your friends. Play money only." and the notice that coins are free play money with no cash value.
2. Tap **About Fade coins & help resources** → the sheet shows the explanation and two help links. Tap **Done**.
3. Tap **Debug sign in (debug builds only)** → you land on a home screen saying "Hi, Debug User".
4. Tap the **gear** (top right) → **About coins & help** opens the same sheet; **Sign out** returns you to sign-in.

(Local database tests, run in the cloud workspace, not on your Mac: `supabase/tests/run.sh`.)

## If the app won't launch in the simulator
Seen on 2026-10-08: "Application launch for 'com.dschermer.fade' did not return a process handle" (Xcode 27 beta building for an iOS 26.1 simulator). Try these in order, re-running after each:
1. In Xcode: **Product → Clean Build Folder** (⇧⌘K), then Run again.
2. Pull the latest from git, then `cd ios && xcodegen` again (this adds standard Info.plist keys), and Run.
3. In the Simulator app: **Device → Erase All Content and Settings…**, then Run again.
4. Pick a simulator whose iOS version matches your Xcode's SDK (the device picker at the top; **Window → Devices and Simulators** to add one). If none is installed: **Xcode → Settings → Components** to download the iOS 27 simulator.
5. Still failing? In Xcode run it again and copy the text from the **debug console** (bottom panel) and send it to me. If the app crashed, Xcode shows the reason there.
