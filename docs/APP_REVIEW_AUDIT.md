# Fade — App Review audit (Milestone 13)

I reviewed the app the way an App Store reviewer would, guideline by guideline, against the code and docs in this repository. **I can't see Apple's current guidelines text or talk to Apple from here, and I have not run the app on a device**, so this is a careful best-effort list, not a guarantee of approval. Where I'm unsure I say so.

Legend: ✅ done / compliant · 🔧 fixed during this audit · 👤 needs you (I can't do it) · ⚠️ residual risk

---

## Before you submit — the short list (👤 things only you can do)

| # | What | Why it matters |
|---|---|---|
| 1 | **Fill the yellow placeholders** in `docs/index.html`, `privacy.html`, `terms.html` (support email, your name, state/country) and turn on GitHub Pages (APPLE_ACCOUNT_STEPS §9). | Guideline 5.1.1(i) and 1.2 require a working privacy policy URL and a way to contact you. A page full of `[YOUR …]` placeholders is a guaranteed rejection. |
| 2 | **Switch `appleRevocationEnabled = true`**, deploy `apple-link` + `apple-delete-account`, and test sign-in → delete on a real phone (APPLE_ACCOUNT_STEPS §6, §8; TESTING.md "needs paid account"). | Guideline 5.1.1(v): apps that offer Sign in with Apple must revoke the token when deleting the account. |
| 3 | **Settle the Polymarket permission question** (item P-1 below). | Guideline 5.2.2 (third-party services) — you must be permitted by their terms. |
| 4 | **Turn the Supabase Email provider OFF** (APPLE_ACCOUNT_STEPS §11). | Otherwise anyone can create accounts with no Apple ID; also contradicts the review notes. |
| 5 | **Create the demo group + offers for the reviewer** and put the code in the review notes (APP_STORE_LISTING §7). | Guideline 2.1: reviewers must be able to exercise every feature. |
| 6 | **Add your own banned words** (slurs) to `banned_terms` (`supabase/ops/moderation.sql` §5). | The starter list intentionally has none; the filter is only as good as its list. |
| 7 | **Be ready to answer reports within 24 hours** after launch (ops/moderation.sql §1). | Guideline 1.2 expects timely action. |

---

## Guideline-by-guideline

### 1. Safety

**1.1 Objectionable content** — ✅ The app itself contains none. User text is limited to usernames, group names and comments, all passed through the word filter (`contains_banned_term`).

**1.2 User-generated content** (the one most likely to get questions — Fade has comments):

| Requirement | Status |
|---|---|
| Filter objectionable material | ✅ usernames, group names and comments are checked on the server (can't be bypassed by a modified client); look-alike symbols and stretched letters are normalised. ⚠️ Any keyword list is incomplete — see "Before you submit" #6. |
| Report mechanism with timely responses | ✅ Report on comments, feed posts and members (`report_content`); reports land in a private table; you read them with `open_reports`. 👤 you commit to acting within 24 hours; the support page and review notes promise exactly that. |
| Block abusive users | ✅ Block hides their content from you and ends friendships; Mute hides content only; both are listed and reversible in Settings. |
| Published contact info | ✅ in-app (Settings → Help & support) and on the support page. 👤 fill in the email. |
| Ability for you to remove content & ban users | ✅ `mod_hide_comment`, `mod_hide_feed_item`, `mod_ban_user` (banned accounts can't post offers, take offers, comment, react or join). Existing bets still settle, so a ban never costs other players money. |

⚠️ *Known limitation:* a banned person can delete their account and sign in again with the same Apple ID as a "new" user. There is no device or Apple-ID ban list in v1. Acceptable for friend-group scale; mention it if you ever see abuse and I'll add a hashed Apple-ID ban list.

**1.4 Physical harm** — ✅ Gambling-help text and link in the legal screen and support page (National Council on Problem Gambling).

**1.5 Developer information** — 👤 working support contact (see above).

### 2. Performance

**2.1 App completeness**
- ✅ No placeholder or "lorem ipsum" content; no `TODO`s in the UI strings; debug login is wrapped in `#if DEBUG` so it is not compiled into TestFlight/App Store builds (checked: `Session.swift`, `SignInView.swift`).
- ⚠️ **Reviewer testability.** The only login is Sign in with Apple, so I can't give the reviewer a demo password. The reviewer will sign in with their own Apple ID, join your demo group by code and take your offers. If there are no upcoming games that day (off-season, a quiet Tuesday) the Games list is empty and the reviewer can't try the core flow. Mitigation: demo group (item #5), check the list the day you submit, and the review notes explain what to do if it's empty. This is the single biggest practical risk of a rejection under 2.1.
- ✅ Empty/error states exist for lists (no groups, no games, no offers, no bets, feed empty) and network failures show readable messages.
- ⚠️ **The Swift code has not been compiled by me** (no Xcode in my environment). You build it in Xcode each time, so compile errors will show up for you first; send them to me.

**2.3 Accurate metadata** — ✅ listing text matches the behavior; I avoided league/team trademarks in name, subtitle and keywords (APP_STORE_LISTING §1–2). Screenshots must be real app screens. Don't claim "official" anything.

**2.5.x Software requirements** — ✅ public APIs only; no background modes; no private frameworks; no downloaded executable code; iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

### 3. Business

**3.1.1 In-app purchase** — ✅ none. Coins can't be bought, sold or transferred outside a group, so the "virtual currency must use IAP" rule does not apply.

**3.2.2(ii) Unacceptable business model / real-money** — ✅ no real money, no prizes, no ads. UI says so on sign-in, in the legal screen, on the support page and in the review notes.

### 4. Design

**4.0 / 4.2 Minimum functionality** — ✅ a full app, not a web wrapper.

**4.1 Copycats / 4.3 Spam** — ✅ original concept. ⚠️ Prediction-market-adjacent apps get extra scrutiny; the review notes are upfront about the data source.

**4.8 Login services** — ✅ Sign in with Apple is the *only* login (and it collects no name/email), so no equivalent-option rule is triggered. The DEBUG login isn't in release builds; the Email provider switch (item #4) closes the server side.

### 5. Legal

**5.1.1 Data collection and storage**
- (i) Privacy policy: ✅ written (`docs/privacy.html`), linked in-app (sign-in screen, Settings, legal screen) and to be linked in App Store Connect. 👤 placeholders.
- (ii) Consent: ✅ no data beyond what the game needs; notifications are asked only when you tap "Allow notifications" (never on launch).
- (iii) Data minimization: ✅ no name, email, location, contacts, photos or analytics.
- (v) **Account deletion**: ✅ in-app, 3 taps (Settings → Delete my account… → confirm). The server function (`delete_my_account`) refunds the other side of any bet, cancels open offers, hands group ownership to the longest-standing member, deletes friends/comments/reactions/tokens, anonymizes the profile and deletes the sign-in row. Tested with race tests. 🔧→👤 *Apple token revocation* is built but disabled until the paid account exists (item #2).
- Privacy manifest: ✅ `PrivacyInfo.xcprivacy` (no tracking, no tracking domains, collected data types matching the nutrition label). Our own code uses none of Apple's "required reason" APIs (no UserDefaults, file timestamps, etc.). ⚠️ Libraries ship their own manifests; if Xcode's archive step warns about a missing one, send me the warning.
- App Privacy answers: ✅ prepared in `APP_STORE_LISTING.md` §6.

**5.1.2 Data use and sharing** — ✅ no tracking; no data sold or shared for ads. Supabase and Apple are processors, named in the policy.

**5.2 Intellectual property**
- **P-1 (👤, important):** *Third-party service permission (5.2.2).* The app reads schedules and results from Polymarket's public Gamma API. In `POLYMARKET_RESEARCH.md` I could not read their Terms of Use clauses, and you indicated they were fine. For App Review you are asked to confirm you're allowed to use the data. Safest path: read https://polymarket.com/tos yourself for "API" / "data" / "automated", and if there's any doubt, email them and keep their reply. If they say no, the ingest is one module and can be pointed at another source.
- ✅ Team and league names appear only as factual game labels (how every scoreboard does it); no logos, no league marks, and the support page, legal screen and listing say Fade isn't affiliated with any league or team.
- ✅ Icon is original.

**5.3 Gaming, gambling, and lotteries**
- **5.3.1–5.3.4 (real-money gaming)** don't apply: no real money in or out, no prizes. The rules say real-money gambling requires licenses and geo-restriction; because Fade has none of that, the "no real money, ever" statements are not just marketing — **never add a way to buy or cash out coins**, or the app will need an entirely different review path.
- ✅ **Age rating**: simulated gambling answered at the highest level (APP_STORE_LISTING §5); users must confirm they're 18+ at sign-in and the terms say 18+. 🔧 I changed the in-app/terms/privacy age from 17 to 18 so it is valid under either rating scheme.
- ⚠️ Reviewers sometimes ask whether coins can be exchanged. The answer ("No: not purchasable, not redeemable, not transferable across groups, no prizes") is in the review notes and visible in-app.

### 6. Other / technical hygiene
- ✅ Export compliance: only standard HTTPS; `ITSAppUsesNonExemptEncryption = NO` is set (🔧 added to `project.yml` in this audit). If App Store Connect still asks, answer "standard encryption only / exempt".
- ✅ App category set to Sports (`LSApplicationCategoryType`), 🔧 added.
- ✅ No secrets in the binary: only the public Supabase URL and *publishable* key (designed to be public; Row Level Security protects data). Service-role and Apple/APNs keys live in Supabase secrets/Vault only. A repository secret scan (`grep` for `service_role`, `.p8`, `BEGIN PRIVATE KEY`) finds only docs and placeholders.
- ✅ Push: permission prompt only on user tap; per-type toggles; device tokens removed on sign-out/delete.
- ⚠️ `aps-environment` entitlement must be present on release builds once you uncomment the entitlements block; the Xcode archive flow switches to *production* automatically.

---

## What I changed during this audit
1. Minimum age 17 → 18 (sign-in text, terms, privacy policy, SPEC) so it's correct under both Apple rating tiers.
2. Added `ITSAppUsesNonExemptEncryption = NO` and the Sports category to `project.yml`.
3. Privacy policy: states that reports are retained (anonymously) after account deletion.
4. Games empty-state text now explains off-seasons.
5. Sign-out now removes this phone's push token from the account (before, a signed-out phone could keep getting that account's notifications until someone else signed in on it).
6. Edge Functions accept a pasted private key with literal `\n` characters (if the Supabase secrets box flattens line breaks).
7. Support page: corrected the button name for sharing an invite.

## Residual risks, ranked
1. **Empty Games list on review day** (2.1) — plan for it (demo group, screen recording offer).
2. **Placeholders / unreachable policy URL** (5.1.1) — fill in and verify the links open in a private browser tab.
3. **Prediction-market association & gambling theme** — rated 17+/18+ and clearly play-money; some reviewers still ask questions. Answer calmly with the facts in the review notes.
4. **Compile errors on first Xcode build** — not an App Review risk, but a schedule risk; send errors to me.
5. **Polymarket permission** (P-1).
