# Fade redesign — what to tap after each step

The new look is built in steps (see the table in `MILESTONES.md`). After each step you update the app, tap through the list below, and send me screenshots of anything that looks wrong. Screens that haven't been converted yet keep their old look and keep working.

---

## Step R1 — new look, floating tab bar, combined Feed

### A. Update the database (once, 1 minute)
1. Open your Supabase project → **SQL Editor** → **New query**.
2. Open the file `supabase/migrations/20261009000015_feed_listing_extras.sql` from the project, copy everything, paste it into the editor, and press **Run**.
3. You should see **Success. No rows returned.** (The app still works without this step, but the group name and the "Fade this offer" button won't show on feed cards.)

### B. Update the app
1. In Terminal, in your Fade folder: `git pull`, then `cd ios && xcodegen`.
2. Open `Fade.xcodeproj` in Xcode, pick your iPhone (or a simulator), press **Run**.
3. If Xcode shows red errors instead of building, take a screenshot of the first one and send it to me. That's the most likely thing to go wrong in a step this size, and it's quick for me to fix.

### C. Things to look at and tap
1. **Look.** Dark screen, a floating rounded bar at the bottom with **Feed, Games, Bets, Groups, Me**. The Feed tab is selected (blue).
2. **Feed header.** "fade." in big letters, a round button with your initials at the top right (tap it → goes to the Me tab).
3. **Group chips** under the header: **All groups** plus one chip per group. Tap a group chip: the list narrows to that group. Tap **All groups**: everything is back.
4. **Cards.** You should see cards for offers, bets taken, results, buybacks and votes. An offer card shows three little boxes (their price, shares open, the price to fade them at) and, if the offer is still open and isn't yours, a blue **Fade this offer** button.
5. **Fade this offer** → the *old-style* "Take offer" sheet opens (it gets the new look in step R2). Cancel it.
6. **Open a post.** Tap anywhere on a card (not on a button). You land on the post screen: the card, a row of 8 emoji, the comments, and a text box at the bottom.
   - Tap an emoji: it highlights and the count goes up. Tap again: it goes away.
   - Type a comment and press the blue arrow: it appears in the list.
7. **Report.** On someone else's comment, touch and hold → **Report**. A sheet slides up with the reasons as a list. Pick one, press **Send report**. You see "Thanks, report sent" with **Mute** and **Block** options for that person. (Don't block anyone you need for testing, or use debug account D.)
8. **Vote card.** In a group, call a reset vote (Groups tab → pick the group → Votes & seasons). Back on the Feed you should see a yellow-tinted card with **Yes · n** and **No · n** buttons. Tap one: the count changes.
9. **Pull down** on the feed to refresh.
10. **Other tabs.** Games and Bets say "Being rebuilt" with a button to Groups (they get their real screens in the next steps). The Groups tab is the old group list. The Me tab is the old settings page. All of these still work; the floating bar stays visible on them.
11. **Light mode** (optional): on the iPhone go to Settings → Display & Brightness → **Light**, come back to Fade. Everything should switch to light colours and stay readable.

### D. What to send me
Screenshots of: the Feed (All groups), a post screen, the report sheet, and anything that looks off or any red Xcode error.


---

## Step R2 — Games tab, order book, game page, make and take offers

### A. Update the database (once)
Supabase → SQL Editor → New query → paste the whole file `supabase/migrations/20261009000016_game_lines.sql` → **Run** → "Success. No rows returned". (Without it the Games tab shows an error.)

### B. Update the app
`git pull`, `cd ios && xcodegen`, Run in Xcode (same as before).

### C. Things to tap
1. **Games tab.** "Games" title, a magnifying-glass button, league tabs (**All, NHL, NBA, NFL, MLB**) with a blue underline, then a box **"Offers go to: <your group>"**. Under it, games grouped by day (Today / Tomorrow / dates).
2. **A game card** shows the time and league, a blue "n open offers" tag when there are offers, the two team names, and a grid of price boxes: **Spread, Total, Win** for each team. A blue price means someone is offering that side right now (the cheapest price you could get). A grey **+** means no one is offering yet.
3. **Change the group.** Tap the "Offers go to" box and pick another group: the prices change to that group's offers.
4. **Search.** Tap the magnifying glass, type a team name; games filter as you type.
5. **Order book.** Tap any price box. A sheet slides up: the game, a switch **Back <side 1> | Back <side 2>**, and every open offer for that side, cheapest first (each shows who, the price in your format and the other format, shares, "risk … to win …"). The first one has a blue **Take** button.
6. **Take an offer** (use another account's offer, not your own): tap **Take** → a sheet with the price, a shares box (− / number / +, plus **All** and **Max**), and "You put up / <name> puts up / Winner collects". Press **Take N shares**. The sheet closes and your balance drops by "You put up". Check the Feed: a "took N shares" card appears.
7. **Make an offer.** In the order book tap **Make your own offer**. Pick the side, set the price with − / + or type it (try the **¢ | American** switch: the number converts), set the shares (try 25, 50, Max), read the three amounts, press **Post offer**. The sheet closes; the offer shows up in the order book and in the Feed.
8. **Not enough coins.** Try to post or take more than you have: the button greys out and a red line says how many coins you have available.
9. **Full game page.** Tap the team names on a game card. You get **Win**, **Spread** and **Total** cards with two price boxes each, "More lines (n)" to open the other lines, and **Order book** links. Tap any price there to open the order book for that exact line.
10. **Feed → Fade this offer** now opens the same new Take sheet.
11. Pull down to refresh the Games list.

### D. What to send me
Screenshots of: the Games tab, an order book, the Make-an-offer sheet with numbers filled in, the game page, and anything that looks off or any Xcode error.


---

## Step R3 — Bets tab, Groups tab, the group page, votes, buybacks, leaving

No new database step. `git pull`, `cd ios && xcodegen`, Run.

### Things to tap
1. **Bets tab.** Title "Bets", **In play** (coins tied up) at the top right, tabs **Pending / Open offers / Settled** with counts, and group chips if you're in more than one group.
   - **Pending**: a card for each bet that isn't settled. Before the game: your side and price, "You vs <name> · <group> · 25 shares", **You put up / To win**, "Starts in 2h 14m" and a **Share** button. After the game starts: an amber box "Game started — awaiting official result…".
   - **Open offers**: your unfilled offers, with **Cancel N unfilled shares** (asks you to confirm and returns the coins).
   - **Settled**: Won / Lost / Void cards with the big +/− amount; cancelled offers also show here.
2. **Groups tab.** Create group / Join with a code buttons, then a card per group: badge, name, "6 members · Unlimited buybacks", **Balance / Net / Rank** boxes, a yellow "Reset vote open" tag when one is running, a blue "n open offers" tag, and (if you have 0 coins) a yellow "You're out of coins" strip with a button.
3. **Open a group** (tap its card). Top: **Balance / Net / In play**, the group's rules line, an **Invite** button in the top bar.
   - **Leaderboard**: switch **Net profit | Raw balance**; rank numbers, "n buybacks" under a name, your row is tinted.
   - **Feed**: that group's activity (same cards as the main Feed).
   - **Votes**: open votes with a green/red progress bar, **Yes / No**, "Call a vote to reset the group", recent results, past seasons.
   - **Members**: everyone with balances; a **⋯** menu on other people (Report / Mute / Block); if you own the group, a **Make owner** button on each other member; group rules; **Invite friends**; **Leave group**.
4. **Invite**: tap Invite — big code, **Copy code**, **Share invite**.
5. **Create a group** (Groups tab → Create group): name with a counter, starting balance with − / + (type a number too), the **Unlimited | Per week | By vote** switch, "Same buyback as starting balance" switch. Press **Create group**.
6. **Join with a code**: eight boxes fill as you type (or **Paste from clipboard**). **Join group** turns on at 8 characters.
7. **Vote** (needs 2+ people): Members/Votes → **Call a vote to reset the group** → confirm. The yellow banner appears at the top of the group page and in the Feed. As another account, tap **Yes** — the bar and counts move.
8. **Buyback** (use a debug account with 0 coins, e.g. after losing everything): the group page shows the **"You're out of coins"** card. If buybacks are allowed you get **Buy back in for N coins** → a sheet with what you receive, that net profit stays the same, and that the group sees it → confirm. If the weekly limit is used you see when the next one opens. In a "By vote" group you get **Ask the group for a buyback**.
9. **Leave a group**: Members → **Leave group**.
   - With a bet that isn't settled: a sheet **"You can't leave yet"** lists those bets (no error afterwards).
   - Otherwise: **"Leave <group>?"** shows open offers cancelled / coins gone / net profit kept, with **Leave group** and **Stay**.
   - As the owner with other members: the button is greyed and a yellow note says to hand over first. Tap **Make owner** on someone → confirm sheet → done, then you can leave.
10. Report/mute/block from the ⋯ menu still work; the report sheet is the new one.

### What to send me
Screenshots of the Bets tab (each of the three parts if you can), the Groups tab, a group page (Leaderboard and Members), the Votes part with an open vote, and anything that looks off or any Xcode error.


---

## Step R4 — Me tab, friends, settings, sign-in, and the rest

No new database step. `git pull`, `cd ios && xcodegen`, Run.

### Things to tap
1. **Sign-in screen** (sign out first, from the Me tab): a big "fade." wordmark, the tagline, three numbered steps, the "free play money" note, the Apple button, the age/terms line, and "About coins and help resources" (opens the About & help screen). In a debug build the orange test-account box is still there.
2. **Pick a username** (only for a brand-new account): "@" field, Continue.
3. **Me tab.** Your name and avatar, the **Lifetime score** card (big +/− number, Record, Groups, Buybacks), a **Friends** preview (top of the friends leaderboard, a blue "n requests" tag, **See all**), then **Settings**:
   - **Show prices as: ¢ | American** — switch it and look at the Games tab: prices change format everywhere.
   - **Notifications** → green "allowed" card and five switches (turn one off and back on).
   - **Blocked and muted people** → grouped lists with Unblock / Unmute and the short explanation.
   - **About coins and help** (sheet), Terms, Privacy, Help — links.
   - **Sign out**, and **Delete my account…** at the bottom.
4. **Friends** (Me → See all): switch **Leaderboard | Requests | Add**.
   - Leaderboard: rank, avatar, "Record 7–4", lifetime score; your row is tinted; touch and hold a friend to remove them.
   - Requests: incoming cards with **Accept / Decline**; "Waiting for them" with **Cancel**.
   - Add: type an exact username → **Send friend request**; "People from your groups" with **Add**.
5. **Delete account** (use a spare debug account!): the red "This can't be undone" banner, six consequences, type **DELETE**, the red button turns on. Only do this on a throwaway account.
6. **About & help**: the play-money card, "Need help?" with the National Council on Problem Gambling link and **Call 1-800-GAMBLER**, and the legal links.

### What to send me
Screenshots of the sign-in screen, the Me tab (scrolled to the top and the bottom), Friends (all three parts), and anything that looks off or any Xcode error.
