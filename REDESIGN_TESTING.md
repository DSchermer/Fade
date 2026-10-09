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
