# Fade — what to do once your Apple Developer account is active

Do these in order. Each step says where to click. Nothing here is needed for the simulator tests; it is all for real-phone testing, TestFlight and the App Store.

Time needed: about 1–2 hours in total, most of it waiting on Apple's website.

> **Menu names:** Apple and Supabase rename buttons now and then. If a label isn't exactly as written, look for the closest one. If you get stuck, paste what you see back to me.

---

## 0. Turn the paid account on
1. https://developer.apple.com/programs/enroll → enroll as an **Individual** ($99/year). Apple may take up to 2 business days.
2. Once approved, sign in at https://developer.apple.com/account. You'll see the full menu (Certificates, Identifiers & Profiles; Membership details; etc.).

## 1. Find your Team ID
Developer account → **Membership details** → **Team ID** (10 characters, like `AB12CD34EF`). Write it down; you'll use it three times.

## 2. Register the app (App ID)
1. Developer account → **Certificates, Identifiers & Profiles** → **Identifiers** → **+**.
2. Choose **App IDs** → **App** → Continue.
3. Description: `Fade`. Bundle ID: **Explicit** → `com.dschermer.fadeapp`.
4. Under Capabilities tick **Sign in with Apple** and **Push Notifications**. Continue → Register.

## 3. Create the two keys (each downloads ONCE — keep the files safe)
Keys are how our server proves to Apple who we are. Store the downloaded `.p8` files somewhere private (a password manager or an encrypted folder). **Never commit them to git, never email them.**

**a) Push key**
1. **Keys** → **+** → Key name `Fade push`, tick **Apple Push Notifications service (APNs)** → Continue → Register → **Download** (a file like `AuthKey_ABC123DEFG.p8`).
2. Note the **Key ID** (10 characters; also in the file name). If asked for an environment, choose **Sandbox & Production**.

**b) Sign in with Apple key**
1. **Keys** → **+** → Key name `Fade sign in`, tick **Sign in with Apple** → **Configure** → choose Primary App ID `Fade (com.dschermer.fadeapp)` → Save → Continue → Register → **Download**.
2. Note its **Key ID** too.

## 4. Tell Supabase about Sign in with Apple
Supabase dashboard → **Authentication** → **Sign In / Providers** (or **Providers**) → **Apple** → enable it and set **Client IDs** to `com.dschermer.fadeapp` → Save. (The app signs in natively, so no web "Services ID" or secret key is needed here.)

## 5. Switch the app over to your team
1. In `ios/project.yml` set `DEVELOPMENT_TEAM: "AB12CD34EF"` (your Team ID).
2. Uncomment the `entitlements:` block just under `dependencies:` (the one with `com.apple.developer.applesignin` and `aps-environment`). Keep `aps-environment: development`; Xcode switches it to production automatically when you archive for TestFlight.
3. In a terminal: `cd ios && xcodegen`, then open `Fade.xcodeproj` in Xcode. In **Signing & Capabilities** you should now see *Sign in with Apple* and *Push Notifications* with no red errors. Plug in your iPhone, pick it as the run target, press **Run**. (First time on a phone: iPhone Settings → Privacy & Security → Developer Mode → on.)

## 6. Deploy the three Edge Functions (Supabase servers)
For each of `send-push`, `apple-link`, `apple-delete-account`:
1. Supabase dashboard → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Name it exactly as the folder name. Paste the whole contents of `supabase/functions/<name>/index.ts`. **Deploy**.

Then **Edge Functions → Secrets** (sometimes under Project Settings → Edge Functions) and add:

| Secret name | Value |
|---|---|
| `APNS_KEY_ID` | Key ID of the **push** key |
| `APNS_TEAM_ID` | your Team ID |
| `APNS_PRIVATE_KEY` | the **entire** contents of the push `.p8` file (open it in TextEdit, select all, copy), including the `-----BEGIN…` and `-----END…` lines |
| `APNS_BUNDLE_ID` | `com.dschermer.fadeapp` |
| `APPLE_KEY_ID` | Key ID of the **Sign in with Apple** key |
| `APPLE_TEAM_ID` | your Team ID |
| `APPLE_PRIVATE_KEY` | the entire contents of the Sign in with Apple `.p8` |
| `APPLE_BUNDLE_ID` | `com.dschermer.fadeapp` |

The functions also get `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` from Supabase automatically; don't add those.

## 7. Start the push sender
1. Supabase → **Project Settings** → **API Keys** → find the **service_role** key (on the "Legacy API keys" tab if the page has tabs; a long string starting `eyJ…`). **This key is a master password. Don't put it in the repository, the app, a screenshot or a chat.**
2. Open `supabase/ops/schedule_push.sql`, replace `PASTE-YOUR-SERVICE-ROLE-KEY` with that key **in the SQL editor only** (don't save the file with the key in it), and Run it. This stores the key encrypted in Supabase Vault and schedules the sender every minute.
3. Check it ran: SQL editor → `select * from cron.job_run_details order by start_time desc limit 5;` (status should be `succeeded`), and `select * from public.notification_outbox order by id desc limit 5;` (rows should get a `sent_at`).

## 8. Switch Apple revocation on (required before App Store)
Apple requires that deleting an account also revokes the Sign in with Apple connection. Our Edge Functions do that; the app only calls them when the flag is on.
1. `ios/Fade/AppConfig.swift` → set `appleRevocationEnabled = true`.
2. Re-run on your phone: sign out, sign in with Apple, then later delete a test account. See `TESTING.md` §"Needs the paid account" for the exact check.

## 9. Turn on the public web pages (privacy policy + support)
1. Fill in the yellow placeholders in `docs/index.html`, `docs/privacy.html`, `docs/terms.html` (your support email, your name, your state/country). Search each file for `todo`. Have a lawyer or a template service glance at them before launch if you can; they're written in plain language, not legal advice.
2. GitHub → repository `DSchermer/Fade` → **Settings** → **Pages** → Source: **Deploy from a branch** → Branch: the branch your code lives on (right now `claude/great-goldberg-z1ihhv`; the repository has no `main` branch yet, so if you later merge into `main`, switch this to `main`) → folder `/docs` → Save.
3. After a minute these should open: https://dschermer.github.io/Fade/ , `/privacy.html` , `/terms.html`. (The repo must be public for the free GitHub plan to serve Pages; the repo contains no secrets. If you'd rather keep it private, tell me and we'll host the pages elsewhere.)

## 10. Invite links (optional polish for v1)
The app already understands `fade://join/CODE`. Right now invites share the plain code (“Open Fade → Join with a code → CODE”), which works everywhere. To make a tappable link:
- **Quick version (custom scheme):** in `ios/project.yml`, under the `Fade` target add:
  ```yaml
      info:
        path: Fade/Info.plist
        properties:
          CFBundleURLTypes:
            - CFBundleURLName: com.dschermer.fadeapp
              CFBundleURLSchemes: [fade]
  ```
  then `cd ios && xcodegen`. Messages won't make `fade://…` blue/tappable, but it works from Notes, Safari's address bar, or a QR code. Test: with the app installed, run `xcrun simctl openurl booted "fade://join/ABCD1234"` on the simulator.
- **Proper version (universal links, `https://yourdomain/join/CODE`):** needs a domain you own (~$12/yr), the *Associated Domains* capability, and an `apple-app-site-association` file on that domain. Do this after launch if people ask for it.

## 11. Turn OFF email login (do this before TestFlight)
Supabase → **Authentication** → **Sign In / Providers** → **Email** → switch **off**. Sign in with Apple must be the only way in. Your debug email/password accounts stop working after this; they only exist in DEBUG builds anyway.

## 12. TestFlight (your friends try it)
1. https://appstoreconnect.apple.com → **My Apps** → **+** → **New App**: platform iOS, name `Fade`, language English, bundle ID `com.dschermer.fadeapp`, SKU `fade-ios-001`.
2. In Xcode: set the run destination to **Any iOS Device (arm64)** → menu **Product → Archive**. When it finishes the Organizer opens → **Distribute App** → **App Store Connect** → Upload (accept the defaults).
3. In App Store Connect → your app → **TestFlight**: wait for the build to finish "Processing" (5–30 min; you'll get an email). Answer the export-compliance question if asked (see `APP_STORE_LISTING.md` §10).
4. **Internal testing** (you, up to 100 people on your App Store Connect team): instant. **External testing** (your friends): add them by email/public link; the first external build needs a short Apple "Beta App Review" (usually under a day).
5. Add the reviewer notes from `APP_STORE_LISTING.md` §7 to TestFlight's "Test Information" too.

## 13. Submit to the App Store
1. Fill in the listing from `APP_STORE_LISTING.md` (description, keywords, screenshots, privacy answers, age rating).
2. Re-read `APP_REVIEW_AUDIT.md` — especially "Before you submit" at the top.
3. Pick the build → **Add for Review** → **Submit**. Reviews usually take 1–3 days. If rejected, paste the message to me and we fix it.
