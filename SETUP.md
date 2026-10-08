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
