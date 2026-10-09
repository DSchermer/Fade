# Fade — testing plan for Milestones 8–13

**Updated 2026‑10‑09 evening.** Everything is built, the migrations are in, the app runs on your Mac's simulator and on your iPhone, and the Apple-account features are proven (§12). What's left is **you tapping through the app** (§2–§8) plus a few Apple chores. Budget about **2 hours** for everything, or **45 minutes** for just the "must do" parts (marked ⭐).

---

## 0. How to use this file

- Work top to bottom. Each part has checkboxes. If a step doesn't match what's written, **stop, screenshot it, and tell me the step number** (for example "E5 failed: …").
- "A, B, C, D" are four test accounts (see §1.3). Use one simulator and switch accounts with Settings → Sign out, or run two simulators side by side (Xcode → Product → Destination).
- **Pull down on any list to refresh it.** Nothing updates live in v1 by design.
- Don't run any migration twice. If one errors partway, don't re-run it; send me the error text.
- The Sign in with Apple button is **not** how you switch test accounts. Use the orange **Debug only** box on the sign-in screen (email + password; it creates the account if it doesn't exist). That box exists only in builds you run from Xcode, never in TestFlight/App Store builds.

### What has been checked for you
- **Server side:** about 20 SQL test files plus 11 "everybody at once" race tests (settle twice, vote at once, leave while someone takes your offer, delete an account while someone takes its offer, …), a permission audit, and tests of the three Edge Functions against pretend servers. I broke the code on purpose in about 30 places to confirm the tests notice.
- **App ↔ server data:** a contract test decodes what the database returns with the app's own model types (23 checks pass).
- **Real devices:** the app compiles and runs; Sign in with Apple, push delivery, and deletion + Apple disconnect work on your iPhone (§12).

### What has NOT been checked: the screens themselves
Nobody (you or me) has tapped through the votes, feed, friends, buyback and leave/ownership screens yet, and the money flows haven't been tapped on the real connection. That is what §2–§8 are for. A reviewer reading the code already found one screen bug the tests couldn't see (the "You're out of coins" box on the group screen), so expect a few more small ones.

---

## 1. Setup — status ✅ (kept for reference)

### 1.1 Code, migrations and jobs ✅
- Migrations **0009–0014 are all applied** (0013 was applied last). The three integrity checks returned no rows, the lockdown check passed, and `apple_tokens` is private.
- Scheduled jobs: auto-cancel, settle, vote closer, two market syncs, and the **push sender** (`fade-send-push`). To re-check any time:
```sql
select jobname, schedule, active from cron.job order by jobname;
```
  You should see **six** active jobs: `fade-auto-cancel`, `fade-close-votes`, `fade-refresh-markets`, `fade-send-push`, `fade-settle`, `fade-sync-markets`.

### 1.2 Build and run
- **Simulator:** `git pull`, then `cd ios && xcodegen`, open `Fade.xcodeproj`, pick a simulator, press ▶.
- **Your iPhone:** plug it in, pick it in the device list, press ▶ (Developer Mode must be on; codesign may ask for your Mac password: Always Allow).
- If the app shows **"permission denied for table …"** anywhere, tell me the table name. Immediate fix: `grant select on public.TABLENAME to authenticated;` in the SQL editor.

### 1.3 The four test accounts ⭐
Use the orange **Debug only** box on the sign‑in screen.
- **A** = your existing owner account (the one you usually test with)
- **B** = your second existing account
- **C** and **D** = new, for example `qa3@example.com` and `qa4@example.com` with any 6+ character password; pick usernames like `qa3`, `qa4` when asked.

(The Apple-signed-in account you used on the phone was deleted during the deletion test. Signing in with Apple again creates a fresh empty account; it's separate from A–D.)

Create a fresh group **"Fade QA"** as A (defaults: 100 coins, unlimited buybacks). Join B, C, D with the invite code (+ → Join with a code). Everyone starts with 100.
- [ ] 4 members in "Fade QA", each with 100 coins

> **No games listed?** The Games list needs upcoming games. If Browse games is empty, tell me, and skip the steps that need a bet (marked 🎲).

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
- [ ] As B: group screen shows "This group decides buybacks by vote…" and **Ask the group for a buyback**. Tap it. (If the orange "You're out of coins" box isn't there, pull down to refresh the group screen once and tell me: this is the area the reviewer flagged.)
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

## 7. Notifications (Milestone 11) — push is live now

- [ ] Settings → **Notifications**: five toggles under "Tell me when…" (new offer / someone takes my offer / my bet is settled / a vote is called / a vote passes or fails). Flip one off, leave the screen, come back → it stayed off.
- [ ] **Real push, on your iPhone:** sign in on the phone with one of the debug accounts (say B, who is in "Fade QA"), tap **Allow notifications** → Allow. On the simulator, as A, post an offer in "Fade QA" (🎲) or call a reset vote. Within about a minute the **phone** shows "New offer in Fade QA …" or "Reset vote in Fade QA".
  - [ ] Turn "A new offer is posted" **off** for B, post another offer → no push for it.
  - [ ] **Sign out on the phone**, then trigger another event → the phone does **not** get it (the token was removed). Sign in again → pushes resume after the app registers.
  - [ ] People who muted or blocked the poster get nothing for that poster's activity.
- [ ] **Without the phone** (what *would* be sent): pretend B has a phone (SQL editor):
  ```sql
  insert into device_tokens (user_id, token, environment)
  values ((select id from profiles where username = '<B username>'), repeat('ab', 32), 'sandbox');
  ```
  Trigger events as above, then `select created_at, kind, title, body, sent_at, last_error from notification_outbox order by id desc limit 10;`. Rows for a fake token get `last_error` (Apple rejects it) — that's expected. Clean up: `delete from device_tokens where token = repeat('ab', 32);`

## 8. Delete an account (Milestone 11) ⭐

*(Deleting a Sign-in-with-Apple account and the Apple disconnect already passed on your iPhone: §12. This section tests the **group side** of deletion with debug accounts, which have no Apple link: the function skips Apple and deletes straight away.)*

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
select jobname, active from cron.job order by jobname;                                  -- 6 active jobs
```
- [ ] first three: no rows
- [ ] `sync_log` failures: none (or tell me what's there)

---

## 12. Needs the paid Apple account (status after 2026-10-09)

The exact steps are in `docs/APPLE_ACCOUNT_STEPS.md`.

| Feature | Status |
|---|---|
| Sign in with Apple (button) | ✅ **Verified on a real iPhone** (2026-10-09) |
| Apple token capture (`apple-link`) | ✅ Verified: `apple_tokens` went to 1 after signing in |
| Account deletion + Apple disconnect (`apple-delete-account`) | ✅ Verified: account deleted, token row removed, the entry disappeared from iPhone Settings → Sign in with Apple |
| Push notifications (`send-push` + `schedule_push.sql`) | ✅ Verified with a test message (queued in SQL, arrived on the phone). ⬜ Still to try: a *real* event, e.g. another account posts an offer in your group |
| Sign‑out removes the push token | ⬜ Covered in §7 |
| Invite link `fade://join/CODE` | ⬜ Needs the URL scheme added (steps §10 in the Apple guide) |
| TestFlight / App Store | ⬜ `docs/APPLE_ACCOUNT_STEPS.md` §12–13 |

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
15. **Apple token revocation** is now **on** (`appleRevocationEnabled = true`) and verified on your iPhone; it's required for App Store submission.
16. **Invite links:** the app understands `fade://join/CODE`, but the URL scheme isn't registered yet, so sharing still sends the plain code. (A real tappable link needs a domain.)
17. **Public pages** (support, privacy, terms) live in `docs/` for free GitHub Pages hosting; they contain placeholders for your email/name/state that **you must fill in**.
18. **No ads, analytics, or crash reporters** were added (keeps the App Privacy answers simple).

## 14. Known limitations / risks

- **Screens not yet tapped through** — see the top of this file.
- **The Apple login is only proven on your own account/phone.** Other people's phones will exercise the same code, but test with a friend during TestFlight.
- Reviewers can't use a demo password (Apple‑only login). The plan in `APP_STORE_LISTING.md` §7 (a demo group with your open offers) covers it, but it depends on there being upcoming games the day of review.
- A banned person can delete their account and sign up again with the same Apple ID. Fine at friend‑group scale.
- Polymarket permission (Terms of Use) is still your call — see `APP_REVIEW_AUDIT.md` item P‑1.
- Email login is still on in Supabase for your debug accounts. Turn it **off** before TestFlight (`APPLE_ACCOUNT_STEPS.md` §11). After that, the debug box stops working; plan your A–D testing before then.

## 15. What to send me when you're done

Copy this and fill it in:

```
Parts passed: 2 [ ] 3 [ ] 4 [ ] 5 [ ] 6 [ ] 7 [ ] 8 [ ] 9 [ ] 10 [ ] 11 [ ]
Failed steps (number + what you saw + screenshot):
Decisions in §13 you want changed:
Placeholders for the legal pages (support email / your name / state or country):
```
