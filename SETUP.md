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
