# Fade — testing plan for Milestones 8–13

Written on 2026‑10‑09 while you were away. **Everything is built.** This file is your checklist for tomorrow: what to run, what to tap, and what you should see. Budget about **2½ hours** for everything, or **45 minutes** for just the "must do" parts (marked ⭐).

Your starting point: migrations **0001–0008 are already applied** (you ran `leave_group` last). Everything after that is new and has **not** been run on your Supabase yet.

---

## 0. How to use this file

- Work top to bottom. Each part has checkboxes. If a step doesn't match what's written, **stop, screenshot it, and tell me the step number** (for example "E5 failed: …").
- "A, B, C, D" are four test accounts (see §2.5). Use one simulator and switch accounts with Settings → Sign out, or run two simulators side by side (Xcode → Product → Destination).
- **Pull down on any list to refresh it.** Nothing updates live in v1 by design.
- Don't run any migration twice. If one errors partway, don't re-run it; send me the error text.

### What I already tested (automatically, on a scratch database — not on your Supabase)
All the money rules, votes, resets, the feed, reports/blocks, friends, notification queue, account deletion and the new permission lockdown are covered by **~20 SQL test files plus 11 "everybody at once" race tests** (settle twice, vote at once, leave while someone takes your offer, delete an account while someone takes its offer, …). Every test passed on the last full run, and I broke the code on purpose in about 30 places to check the tests notice (they did, after I fixed gaps in two). 

### What I could NOT test
- **The SwiftUI screens.** There is no Xcode in my environment, so the M8–M12 *screens* (the files ending in `View.swift`, plus `PushManager.swift`) have never been compiled. **Expect a few red errors on your first build.** Copy them to me exactly. This is normal and usually quick to fix.
  - What I *could* do: I installed a Swift compiler on my side and (a) compiled all the non-screen Swift (stores, models, `Session`) against the real Supabase library with no errors, (b) ran your unit tests (7 pass), (c) syntax-checked every Swift file, and (d) built a "contract test" (`supabase/tests/contract/run.sh`): it fills a scratch database through the real server functions, saves the JSON each screen would receive, and decodes it with the app's own model types. All 23 decodes pass for the situations in that test database (settled, voided and pending bets, buybacks, votes, friends, comments, …), which catches renamed columns, wrong types and unexpected nulls. I also had an independent reviewer read every screen against the real store/model declarations: it found two likely compile errors (a `Section` with a title and footer in `FeedView`, and a sign-in screen with more than 10 items in one stack) and one bug where the buyback box on the group screen might never load. All three are fixed, but nothing has been compiled on a Mac yet.
- Anything that needs the **paid Apple account** (see §10).

---

## 1. Before you start: the 10‑minute setup ⭐

### 1.1 Get the code
```
cd ~/path/to/Fade && git pull
```
(You're on branch `claude/great-goldberg-z1ihhv`; that's where all the work is.)

### 1.2 Run the new migrations, in this order ⭐
For each one: `pbcopy < supabase/migrations/FILE` (from the repo root; from `ios/` use `../supabase/...`) → Supabase dashboard → SQL Editor → **New query** → paste → **Run** → wait for "Success".

| Order | File | What it adds | Quick check afterwards |
|---|---|---|---|
| 1 | `20261008000009_votes.sql` | Reset + buyback votes, season history | `select * from check_season_integrity();` → **no rows** |
| 2 | `20261008000010_feed_moderation.sql` | Feed, reactions, comments, word filter, reports, blocks/mutes, your moderation tools | `select count(*) from banned_terms;` → about 28 |
| 3 | `20261008000011_friends.sql` | Friends | `select count(*) from friendships;` → 0 |
| 4 | `20261008000012_notifications_deletion.sql` | Notification queue + preferences, in‑app account deletion | `select count(*) from notification_outbox;` → 0 |
| 5 | `20261008000013_apple_tokens.sql` | Table the Apple‑revocation feature will use later | `select count(*) from apple_tokens;` → 0 |
| 6 | `20261008000014_lockdown.sql` | Security hardening (explained in §9) | see below |

After all six, run these three; **each must return no rows**:
```sql
select * from check_ledger_integrity();
select * from check_betting_integrity();
select * from check_season_integrity();
```
Check the lockdown took effect (should return **no rows**):
```sql
select c.relname from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v')
   and has_table_privilege('anon', c.oid, 'select');
```
- [ ] 1–6 ran with "Success"
- [ ] three integrity checks: no rows
- [ ] anon check: no rows

### 1.3 Schedule the vote closer ⭐
`pbcopy < supabase/ops/schedule_votes.sql` → new query → paste → Run (prints a job number). Then:
```sql
select jobname, schedule, active from cron.job order by jobname;
```
You should see **fade-auto-cancel, fade-close-votes, fade-refresh-markets, fade-settle, fade-sync-markets** (all `active = true`). (`fade-send-push` comes later, with the paid account.)

- [ ] five jobs listed

### 1.4 Build the app ⭐
```
cd ios && xcodegen
```
Open `Fade.xcodeproj` → pick a simulator → **Run**.
- [ ] it builds. **If not:** copy the red error messages (file name, line number, text) and send them to me. Don't try to fix them.
- [ ] the app opens on the sign‑in screen, which now says "By continuing you confirm you are **18 or older**…"

If the app later shows **"permission denied for table …"** anywhere, that's me having locked down something the app reads. Tell me the table name, and as an immediate fix run `grant select on public.TABLENAME to authenticated;` in the SQL editor.

### 1.5 The four test accounts ⭐
On the sign‑in screen use the orange **Debug only** box (email + password creates the account if it doesn't exist).
- **A** = your existing owner account (the one you usually test with)
- **B** = your second existing account
- **C** and **D** = new: for example `qa3@example.com` and `qa4@example.com` with any password of 6+ characters; pick usernames like `qa3`, `qa4` when asked.

Create a fresh group **"Fade QA"** as A (defaults: 100 coins, unlimited buybacks). Join B, C, D with the invite code (+ → Join with a code). Everyone starts with 100.
- [ ] 4 members in "Fade QA", each with 100 coins

> **No games listed?** The Games list needs upcoming games. October has NFL, NHL and playoff baseball, so there should be plenty. If Browse games is empty, tell me, and skip the steps that need a bet (marked 🎲).

---

## 2. Quick regression (the lockdown must not have broken anything) ⭐ — 10 min

As A in "Fade QA":
- [ ] The group screen loads with your balance (100.00).
- [ ] **Browse games** shows games; open one → a market → **Make an offer** (say 20 shares at 60¢) → confirm. Balance: 12 coins tied up (20 × 60¢).
- [ ] **Open offers** shows your offer. **Leaderboard** loads (4 people at 0.00). **My bets** loads (empty). **Group feed** loads (shows your offer).
- [ ] As B: **Open offers** → tap A's offer → **Take offer** → take 5 shares → confirm. B's balance drops by 5 × 40¢ = 2.00.
- [ ] As A: **My bets** shows one pending bet of 5 shares; **Open offers** shows 15 left.
- [ ] Settings → Lifetime score and Record show (0 and 0–0).
No red error text anywhere = lockdown is fine. 🎲

---

## 3. Votes and resets (Milestone 8) ⭐

**Setup 🎲** (so the reset has something to void): from §2 you already have A's open offer (15 shares left) and one pending bet (A vs B). Also have **C** take 3 more shares of A's offer. Note everyone's balances: A, B, C, D.

### 3.1 Call a reset vote
- [ ] As A: group → **Votes & seasons** → **Call a vote to reset the group** → **Call the vote**.
- [ ] An **Open votes** card appears: "1 yes / 0 no / 4 members", with text "Passes at **3** yes votes…" and an orange warning that all unsettled bets will be voided.
- [ ] Go back to the group screen: an orange banner **"Reset vote in progress"** is at the top. (Pull down to refresh if not.)
- [ ] The **Call a vote** button is now greyed out (only one reset vote at a time).
- [ ] As B: the banner is visible; open it; vote **No**, then change your mind and vote **Yes** ("You can change it until the vote closes").
- [ ] Still open (2 of 4 yes).

### 3.2 It passes
- [ ] As C: vote **Yes**. The vote ends immediately (3 of 4 is more than half).
- [ ] As A, group screen: balance **100.00** again; no "tied up" row; banner gone.
- [ ] **My bets** / **Open offers**: the open offer is gone; the bet is shown as voided; nothing counts as a win or loss (Settings → Record unchanged).
- [ ] **Votes & seasons**: under Recent results "Passed · yes 3 / no 0"; under **Past seasons** → **Season 1** shows the standings (everyone's net profit 0.00 if no bets had settled).
- [ ] **Leaderboard** starts over at 0.00 for everyone; **Group feed** shows the vote result.
- [ ] SQL: the three integrity checks → still no rows.

### 3.3 It fails
- [ ] As A: call a new reset vote. As B: **No**. As C: **No**. → ends immediately as **Failed** (2 of 4 can no longer be beaten).

### 3.4 Time runs out (use the helper script)
- [ ] As A: call a vote; as B vote **Yes** (2 of 4 — not yet decided).
- [ ] SQL editor: open `supabase/ops/dev_close_vote.sql`, replace both `PASTE GROUP NAME HERE` with `Fade QA`, Run. The table should show `passed … yes 2, no 0, electorate 4, quorum 2 — "more yes than no when time ran out"`. The three integrity checks at the bottom: no rows.
- [ ] Repeat: A calls a vote and **nobody else votes** → run the script again → the vote shows `failed` ("not enough voters" style note).

### 3.5 Buyback by vote
- [ ] As A create a second group **"Vote QA"** with Buybacks = **By group vote**. Join B and C.
- [ ] 🎲 Make B broke: B posts an offer for all 100 coins' worth, C takes it all, then use `ops/dev_force_result.sql` with the result that makes B's side lose (`outcome_0` = the first side listed wins, `outcome_1` = the second; see the file's header). B now has 0 available and nothing tied up.
- [ ] As B: group screen shows "This group decides buybacks by vote…" and **Ask the group for a buyback**. Tap it.
- [ ] As A: Votes & seasons → open vote "Buyback for @…" → **Yes**. As C: **Yes** → passes; B has 100 coins again.
- [ ] Leaderboard: B shows "1 buyback"; B's **net profit is still negative** (a buyback never erases a loss).
- [ ] B can't ask again while holding coins (the button isn't shown).

---

## 4. Feed, comments, reactions (Milestone 9) ⭐

- [ ] **Group feed** (as A): see entries for offers posted/taken, votes, results. Pull to refresh.
- [ ] Tap an item → react with an emoji → count appears; tap again → removed. Check from B that the count is visible (after refresh).
- [ ] Add a comment ("nice pick") → **Send** → it appears under **Comments**; B sees it after refreshing.
- [ ] **Delete** your own comment (touch and hold it → Delete).
- [ ] **Filter test:** try comments `this is bullshit` → rejected with a message about offensive language. `sh1t happens` → rejected (look‑alike characters are caught). `What a classic Scunthorpe assist` → **accepted** (no false alarm on harmless words).
- [ ] Try a group name containing a banned word (+ → Create a group) → rejected. Try changing a username to one containing a banned word → rejected.

## 5. Report, mute, block, ban (Milestone 9) ⭐

Setup: B writes a comment "you are an idiot" (not on the banned list — it's your test of the report path).
- [ ] As A: touch and hold B's comment → **Report** → choose *Harassment* → **Send** → "Thanks — report sent".
- [ ] SQL editor: `select * from public.open_reports;` (also in `supabase/ops/moderation.sql` §1) → one row: reporter `test…`, reason `harassment`, content = B's comment text, author = B.
- [ ] Hide it: `select public.mod_hide_comment('<target_id from that row>', 'test');` → refresh the app: the comment is **gone for everyone**. `open_reports` is now empty.
- [ ] As C: report **a member**: Group screen → touch and hold a member's name → **Report** → *Spam* → Send. And report **a feed post** (open an item → "Report this post"). Both appear in `open_reports`.
- [ ] Dismiss one: `select public.mod_resolve_report('<report_id>', 'dismissed', 'ok');`
- [ ] **Mute:** as A, touch and hold one of C's comments → **Mute**. A no longer sees C's comments; B still does. Settings → **Blocked & muted people** lists C → **Unmute** restores them.
- [ ] **Block:** as C, touch and hold D's name (group screen) → **Block** → confirm. C and D no longer see each other's comments; D can't be added as C's friend. Settings → Blocked & muted people → unblock.
- [ ] **Ban:** `select public.mod_ban_user('<D's id>', 'test');` (find D's id with `select id, username from profiles where username = 'qa4';`). As D: try to post an offer, comment, or react → each fails with an "account disabled" style message. D can still *see* things. Then undo: `select public.mod_unban_user('<D's id>');` and confirm D works again.

## 6. Friends (Milestone 10) — 15 min

Friends button = the **two‑person icon** at the top‑left of the Home screen (next to the gear). Tabs: **Leaderboard / Requests / Add**.
- [ ] As A → **Add** → type B's username → **Send friend request** → confirmation message.
- [ ] As B → **Requests (1)** → **Accept**. Both A and B now appear on each other's **Leaderboard** tab with a lifetime score and "Record W–L".
- [ ] The **Add** tab suggests "People from your groups" (C, D) with "N shared groups"; tap **Add** for C. C sees the request and **Declines**; A's **Requests** shows "Waiting for them" → **Cancel** works on a pending one.
- [ ] Swipe a friend on the Leaderboard tab → **Remove**.
- [ ] Mistakes: your own username → error; a username that doesn't exist → error; a person who blocked you → can't be added.
- [ ] Not‑friends can't see each other's score; friends can (that's the only place lifetime score is shown to others).

## 7. Notification settings and queue (Milestone 11, no Apple account needed)

- [ ] Settings → **Notifications**: five toggles under "Tell me when…" (new offer / someone takes my offer / my bet is settled / a vote is called / a vote passes or fails). Flip one off, leave the screen, come back → it stayed off.
- [ ] Tap **Allow notifications** → iOS asks → Allow. (In the simulator without the paid account, nothing is actually delivered; that is expected.)
- [ ] **See what *would* be sent.** Pretend B has a phone (SQL editor):
  ```sql
  insert into device_tokens (user_id, token, environment)
  values ((select id from profiles where username = '<B username>'), repeat('ab', 32), 'sandbox');
  ```
  Then as A post an offer in Fade QA, and call a reset vote; as C take an offer. Then:
  ```sql
  select created_at, kind, title, body from notification_outbox order by id desc limit 10;
  ```
  - [ ] B has a `new_offer` row ("New offer in Fade QA …") and a `vote_called` row.
  - [ ] Turn "A new offer is posted" **off** for B in the app, post another offer → **no** new `new_offer` row for B.
  - [ ] People who muted/blocked the poster get nothing for that poster's activity.
  - [ ] Clean up: `delete from device_tokens where token = repeat('ab', 32);`

## 8. Delete an account (Milestone 11) ⭐

Setup: create account **E** (`qa5@example.com`, username `qa5`), join "Fade QA", post an offer (10 shares), have C take 4 of them (🎲), E writes a comment. Note C's balance first.
- [ ] As E: Settings → **Delete my account…** → the screen lists exactly what happens → type **DELETE** → **Delete my account**. You land on the sign‑in screen.
- [ ] As C: C's pending bet with E is **voided** and C has their full stake back. E's open offer is gone.
- [ ] Feed/comments: E's comment is gone; E's past feed lines say **"deleted user"**. Members list no longer contains E.
- [ ] SQL: `select count(*) from auth.users where email = 'qa5@example.com';` → **0**. `select username, display_name, deleted_at from profiles where display_name = 'Deleted user';` → a row with no username.
- [ ] Three integrity checks → no rows.
- [ ] Sign in again with `qa5@example.com` → you get a brand‑new empty account (username picker), not the old one.
- [ ] **Owner deletes:** make account F own a group with 2 other members, delete F → the member who has been in the group longest becomes owner (`select p.username, gm.role from group_members gm join profiles p on p.id = gm.user_id where gm.group_id = (select id from groups where name = '<group>');`).

## 9. What the lockdown migration (0014) changed — and the spot checks

Plain language: before, "not signed in" and "signed in" users technically had *write* permission on lots of tables, and only the Row Level Security rules stopped them. Now they have **no** write permission at all (writes only happen through the server functions), "not signed in" has nothing, and each new function must be granted by name.
- [ ] §1.2's anon check returned no rows.
- [ ] Spot check — run in SQL editor:
  ```sql
  select has_table_privilege('authenticated', 'public.offers', 'insert') as can_insert_offers,
         has_table_privilege('authenticated', 'public.offers', 'select') as can_read_offers,
         has_function_privilege('authenticated', 'public.ledger_post(uuid,uuid,uuid,text,bigint,text,text,uuid)', 'execute') as can_run_ledger_post;
  ```
  Expected: `false, true, false`.

## 10. Legal pages, icon, store text (Milestone 12)

- [ ] The Home‑screen **app icon** shows the Fade icon (not the blank default). The launch screen appears briefly when you open the app.
- [ ] Sign‑in screen: the **Terms of Use** and **Privacy Policy** words are tappable links. They will say "404 / not found" **until GitHub Pages is turned on** (`docs/APPLE_ACCOUNT_STEPS.md` §9) — that's expected today.
- [ ] Settings: **Privacy policy / Terms of use / Help & support** links exist, and **About coins & help** opens the "no real money" screen with the gambling‑help text.
- [ ] Open `docs/index.html`, `docs/privacy.html`, `docs/terms.html` in your browser (double‑click). Read them. **Fill in the yellow placeholders** (email, your name, state/country), or tell me the values and I'll do it.
- [ ] Skim `docs/APP_STORE_LISTING.md` (name, description, keywords, review notes) — tell me anything you want changed.
- [ ] Skim `docs/APP_REVIEW_AUDIT.md` — especially its "Before you submit" table.

## 11. Final health check ⭐

```sql
select * from check_ledger_integrity();
select * from check_betting_integrity();
select * from check_season_integrity();
select kind, ok, detail, at from sync_log where ok = false order by at desc limit 20;   -- ideally empty
select jobname, active from cron.job order by jobname;                                  -- 5 active jobs
```
- [ ] first three: no rows
- [ ] `sync_log` failures: none (or tell me what's there)

---

## 12. Cannot be tested until the paid Apple account is active

These are built but **unproven**. The exact steps are in `docs/APPLE_ACCOUNT_STEPS.md`; the checks for each are below.

| Feature | After setup, check on a real iPhone |
|---|---|
| Sign in with Apple (button) | Tap **Sign in with Apple** → pick username → works; sign out/in returns to the same account |
| Apple token capture (`apple-link` function) | After a fresh Apple sign‑in: `select count(*) from apple_tokens;` → 1 (needs `appleRevocationEnabled = true`) |
| Account deletion + Apple revocation (`apple-delete-account`) | Delete the account; then iPhone Settings → [your name] → Sign in with Apple → **Fade should no longer be listed** |
| Push notifications (`send-push` + `schedule_push.sql`) | Allow notifications; have another account post an offer; the push arrives within ~1 minute; `notification_outbox.sent_at` is filled |
| Sign‑out removes the push token | After signing out, no more pushes for that account arrive on the phone |
| Invite link `fade://join/CODE` | Needs the URL scheme added (steps §10 in the Apple guide) |
| TestFlight / App Store | `docs/APPLE_ACCOUNT_STEPS.md` §12–13 |

## 13. Decisions I made while you were away — veto any of these

I chose the simplest option consistent with CLAUDE.md and SPEC.md each time; they're also logged in CLAUDE.md.

1. **Minimum age is 18** (not 17), so the app is correct under either of Apple's top age tiers (sign‑in text, terms, privacy policy).
2. **Votes:** the caller automatically votes yes; ballots are visible to group members and can be changed until the vote closes; a reset vote passes at once when yes is more than half of *all* members, fails at once when no is at least half, and otherwise at the 24‑hour deadline needs the quorum (`min(members, max(2, ceil(25 %)))`) **and** more yes than no.
3. **Buyback votes** exist only for groups whose policy is "By group vote", only for yourself, only when you are fully busted, one open at a time. Passing pays the group's buyback amount.
4. **Reset** also starts a new season; the season's profit/loss moves into each person's lifetime score; voided bets never count for W–L or score (as specified).
5. **Account deletion** (not specified before): leaves every group, cancels your open offers, voids your unsettled bets with the *other* side refunded in full, removes friends/comments/reactions/tokens, renames you "deleted user" in saved activity, keeps your profit/loss in an anonymous lifetime tally (so groups' books still balance), and deletes the sign‑in. If you own a group, ownership goes to the member who has been there longest.
6. **Feed** is written by database triggers (no money function was touched). It refreshes when opened or pulled down — no live updates in v1.
7. **Word filter:** whole words only (so "class" and "Scunthorpe" are fine), catches look‑alike characters (`sh1t`) and stretched letters (`shiiit`). The starter list has profanity and threats but **no slurs on purpose** — add yours in `banned_terms` (`ops/moderation.sql` §5).
8. **Block is two‑way** (neither side sees the other's comments or feed posts, and any friendship ends); **mute is one‑way** (only you stop seeing them). Both are reversible in Settings → Blocked & muted people.
9. **Banned accounts** can't post offers, take offers, comment, react, or join groups. Their existing bets still settle so nobody else loses out.
10. **Comment limits:** 1–500 characters, at most 10 per minute per person.
11. **Win–loss** counts each bet separately (one taker = one bet), voids excluded.
12. **Push text** shows prices as cents plus American odds (for example "60¢ (−150)").
13. **Permission lockdown (0014)** — see §9. If anything in the app now says "permission denied", that's this.
14. **Sign‑out removes the phone's push token**, so a signed‑out phone stops getting that account's notifications.
15. **Apple token revocation** is built but switched **off** (`appleRevocationEnabled = false`) until the paid account exists; **required** before App Store submission.
16. **Invite links:** the app understands `fade://join/CODE`, but the URL scheme isn't registered yet, so sharing still sends the plain code. (A real tappable link needs a domain.)
17. **Public pages** (support, privacy, terms) live in `docs/` for free GitHub Pages hosting; they contain placeholders for your email/name/state that **you must fill in**.
18. **No ads, analytics, or crash reporters** were added (keeps the App Privacy answers simple).

## 14. Known limitations / risks

- **Never compiled** — see the top of this file.
- Reviewers can't use a demo password (Apple‑only login). The plan in `APP_STORE_LISTING.md` §7 (a demo group with your open offers) covers it, but it depends on there being upcoming games the day of review.
- A banned person can delete their account and sign up again with the same Apple ID. Fine at friend‑group scale.
- Polymarket permission (Terms of Use) is still your call — see `APP_REVIEW_AUDIT.md` item P‑1.
- Email login is still on in Supabase for your debug accounts. Turn it **off** before TestFlight (`APPLE_ACCOUNT_STEPS.md` §11).

## 15. What to send me when you're done

Copy this and fill it in:

```
Build: [ok / errors pasted below]
Parts passed: 1.2 [ ] 1.3 [ ] 1.4 [ ] 2 [ ] 3 [ ] 4 [ ] 5 [ ] 6 [ ] 7 [ ] 8 [ ] 9 [ ] 10 [ ] 11 [ ]
Failed steps (number + what you saw + screenshot):
Decisions in §13 you want changed:
Placeholders for the legal pages (support email / your name / state or country):
```
