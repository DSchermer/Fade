# Fade — App Store Connect listing (copy/paste kit)

Everything you need to type into App Store Connect, written ahead of time. Needs the paid Apple Developer account (see `APPLE_ACCOUNT_STEPS.md`). Nothing here is secret.

> **Things I could not verify from here:** Apple changes the exact wording of App Store Connect forms (especially the age-rating questionnaire and App Privacy page) every year or so. The answers below are the *meaning* of each answer. If a question reads differently, answer according to the meaning and, if unsure, choose the more conservative option.

---

## 1. Basics

| Field | Value |
|---|---|
| App name (30 max) | **Fade** |
| Subtitle (30 max) | **Play-money picks with friends** |
| Bundle ID | `com.dschermer.fade` |
| SKU (anything, never shown) | `fade-ios-001` |
| Primary category | **Sports** |
| Secondary category | **Social Networking** |
| Price | **Free**, no in-app purchases |
| Content rights | "Does your app contain, show, or access third-party content?" → **Yes** (sports schedules/results from a public prediction-market data feed). You must hold the rights; see `APP_REVIEW_AUDIT.md` item P-1 before ticking "I have the rights". |
| Support URL | `https://dschermer.github.io/Fade/` (after you turn on GitHub Pages; see APPLE_ACCOUNT_STEPS §9) |
| Privacy policy URL | `https://dschermer.github.io/Fade/privacy.html` |
| Marketing URL (optional) | leave blank |
| Copyright | `2026 <your name>` |

**Do not** put league or team names (NFL, NBA, MLB, NHL, team names) in the app name, subtitle or keyword field, and do not use team logos in screenshots. Those are trademarks and are a common cause of rejection (Guideline 2.3.7 / 5.2). Mentioning them as plain words in the description ("pro football, basketball, baseball and hockey games") is fine.

## 2. Keywords (100 characters max, comma-separated, no spaces)

```
friends,picks,odds,bets,leaderboard,group,play money,sports,fantasy,wager,pool,competition
```
(90 characters.) Don't repeat words that are already in the name or subtitle.

## 3. Promotional text (170 max — can be edited anytime without a new review)

```
Post your own odds on real games, take your friends' bets, and climb the leaderboard. Free play-money coins only — no real money, ever.
```

## 4. Description (4000 max)

```
Fade is a free game for friend groups. You post your own odds on real pro football, basketball, baseball and hockey games, your friends take the other side, and everyone competes on the group leaderboard.

IT'S ALL PLAY MONEY
Fade coins are free. They can't be bought, sold, cashed out or traded for anything, and there are no prizes. Fade never handles real money.

HOW IT WORKS
• Create a group or join one with an invite code. Each group is its own little economy with its own coins.
• Pick a game, choose a side, set your own price (from 1¢ to 99¢ — or American odds like -150 / +150, your choice), and say how many shares. Each share pays 1 coin to whoever is right.
• Friends "fade" you by taking the other side of any part of your offer. Before anyone confirms, both sides see exactly what they risk and what they can win.
• Offers close automatically when the game starts. No live betting.
• Results come from official outcomes. If a result is disputed or delayed, your bet simply waits. If an event is cancelled, everyone gets their coins back.

COMPETE AND TALK
• Two leaderboards: net profit and raw balance.
• A lifetime score across all your groups, plus a friends leaderboard.
• A group feed with reactions and comments.
• Went broke? Buy back in, following your group's rule: unlimited, limited per week, or by group vote.
• Groups can vote to reset everyone to the starting balance and start a new season.

SAFE BY DESIGN
• Report, mute or block anyone. Reported content is reviewed within 24 hours.
• Delete your account anytime in Settings.
• Sign in with Apple — no email, no password, no tracking.

If gambling is a problem for you, free confidential help is available: 1-800-GAMBLER (US).

Fade is not affiliated with or endorsed by any sports league or team.
```

## 5. Age rating questionnaire

Answer for the *meaning*; the current form lists topics with None / Infrequent / Frequent options.

| Topic | Answer | Why |
|---|---|---|
| Simulated gambling | **Frequent / Intense** (the highest option) | The whole app is play-money sports betting. Being honest here is the safest route; mis-rating gets apps removed. |
| Real-money gambling / contests | **No** | No real money, no prizes. |
| User-generated content / messaging / chat | **Yes** | Comments in group feeds. |
| Unrestricted web access | **No** | The app opens only the policy/support links. |
| Violence, sexual content, profanity, horror, drugs, alcohol, medical | **None** | The app produces none; user comments are filtered and reportable. |

Expected result: the highest tier (17+ in the older scheme, 18+ in the newer one). That is intended and consistent with the sign-in screen, which makes users confirm they are 18 or older (that satisfies both a 17+ and an 18+ rating). Do not try to get a lower rating.

## 6. App Privacy ("nutrition label")

Collected data, all **linked to the user**, **not used for tracking**, purpose **App Functionality** only:

| Apple's data type | What it is in Fade |
|---|---|
| Identifiers → **User ID** | Your Sign in with Apple ID and your chosen username |
| Identifiers → **Device ID** | The push-notification token (only if you allow notifications) |
| User Content → **Other User Content** | Offers, bets, votes, reactions, comments, group names |

Not collected: name, email, phone, location, contacts, photos, health, browsing history, search history, purchases, advertising data, analytics, crash data collected by us. No third-party SDKs that collect data (the Supabase client library only talks to our own backend).

**Tracking:** answer **No** (we do not link data with other companies' data for ads, or share it with data brokers).

`ios/Fade/PrivacyInfo.xcprivacy` (the privacy manifest inside the app) matches this table. If you ever add analytics or a crash reporter, redo both.

## 7. App Review information

| Field | Value |
|---|---|
| Sign-in required | **Yes** |
| Demo account | Not possible: the only login is Sign in with Apple, and the reviewer uses their own Apple ID. Explain in the notes below. |
| Contact | your name, phone, email (reviewers call/email if there's a problem) |

**Notes for the reviewer** (paste, then fill the `<…>` parts the day you submit):

```
Fade is a free, play-money game for friend groups. Coins have no cash value: they cannot be bought, cashed out, transferred outside a group, or exchanged for prizes. The app has no in-app purchases, ads or prizes. Age rating is set to the highest tier because of simulated gambling.

SIGN IN: Sign in with Apple only. The first launch asks you to choose a username.

HOW TO TRY IT (about 3 minutes):
1. After sign-in tap + → "Join with a code" and enter the invite code  <DEMO-GROUP-CODE>. This is a demo group with a few open offers from our own account on upcoming games.
2. Open the group → "Browse games" → pick a game → pick a market → tap an open offer → "Take offer", choose a number of shares and confirm. The confirmation sheet shows the exact risk and payout. ("Make an offer" posts your own.)
3. Group → "Group feed" shows activity; touch and hold a comment to Report / Mute / Block. Group → "Leaderboard" shows rankings.
4. Settings → "Delete my account" deletes the account and all personal data in-app (Guideline 5.1.1(v)).

DATA SOURCE: Game schedules and official results are read from a public third-party prediction-market data feed (Polymarket). We never place orders or touch money there. Bets wait for the official final result.

IF THERE ARE NO UPCOMING GAMES: sports have off-seasons. If the Games list is empty on the day of review, please contact us and we will provide a screen recording of the full flow; the code paths are identical.

USER-GENERATED CONTENT SAFETY (Guideline 1.2): objectionable-content filter on usernames, group names and comments; Report, Mute and Block on every comment and member; reports are reviewed by us within 24 hours; abusive accounts can be banned. Contact: <support email>.
```

**Before you submit, do these two things** (they are the most likely things to go wrong):
1. Create the demo group from your own account, share its code in the notes, and post 3–4 offers on games that start at least a few days after the review will happen. Offers auto-cancel when the game starts. Top them up if the review drags on.
2. Check the Games list is non-empty in the production build the same day.

## 8. Screenshot shot list

Apple wants at least one set at **6.9-inch** (iPhone 16/17 Pro Max); 3–6 screenshots are plenty. Take them in the Simulator (Device: iPhone 17 Pro Max → Cmd-S saves a PNG on the Desktop). Use a group with friendly fake usernames and no real names or emails.

1. **Games list** — upcoming games with the league filter (caption: *"Pick any game"*) — the "Browse games" screen
2. **Offer sheet** — the confirmation sheet showing risk and payout (*"Post your own odds"*)
3. **Open offers on a game** — several offers to take (*"Fade a friend's pick"*)
4. **Leaderboard** — net profit with a few members (*"Win bragging rights"*)
5. **Feed** — offers, results, reactions, a comment (*"Talk your trash"*)
6. **Home screen with groups** or the **Vote banner** (*"Your group, your rules"*)

Don't show team logos. Make sure the status bar looks normal (Simulator → Features → Status Bar can set 9:41 on some Xcode versions).

## 9. Version information

- **What's New** (first release): `First release.`
- **Version:** 1.0 (`MARKETING_VERSION`), **Build:** increases by 1 for every upload (`CURRENT_PROJECT_VERSION` in `ios/project.yml`).

## 10. Export compliance

The app only uses Apple's standard HTTPS. In `project.yml` it sets `ITSAppUsesNonExemptEncryption = NO`, so App Store Connect won't ask on every upload. If asked: *uses encryption → only standard encryption in the OS (HTTPS) → exempt*.
