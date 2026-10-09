# Edge Functions (need the paid Apple Developer account)

These three small functions run on Supabase's servers. They are **not needed for anything up to and including the simulator tests**; they only matter once the Apple Developer account is active.
Deploy each one in the Supabase dashboard: **Edge Functions → Deploy a new function → Via Editor**, paste the file, name it exactly as the folder, deploy. Secrets go under **Edge Functions → Secrets**. Full walk-through: `docs/APPLE_ACCOUNT_STEPS.md`.

| Function | Needs secrets | What it does |
|---|---|---|
| `send-push` | `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `PUSH_SECRET` | Every minute (via `ops/schedule_push.sql`) takes waiting notifications from the database queue and sends them through Apple's push service. |
| `apple-link` | `APPLE_KEY_ID`, `APPLE_TEAM_ID`, `APPLE_PRIVATE_KEY`, `APPLE_BUNDLE_ID` | Right after Sign in with Apple, trades Apple's one-time code for a long-lived token and stores it (service-only table) so the account can be disconnected from Apple on deletion. |
| `apple-delete-account` | same as `apple-link` | Deleting an account: tells Apple to revoke the Sign in with Apple connection, then runs the normal `delete_my_account()`. Apple requires this for apps that use Sign in with Apple. |

**Untested by necessity:** none of these could be run without Apple credentials. They are short and commented; see TESTING.md for how to check each one on your phone.


**Tests:** `supabase/functions/test/run.sh` runs all three against pretend servers (Node 22+). The functions call the database with plain web requests (no library), so they work with both of Supabase's key formats.
