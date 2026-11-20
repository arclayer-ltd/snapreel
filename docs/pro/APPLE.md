# Snapreel Pro: Apple setup

Done on 20 November 2026 for the Pro plan (`docs/pro/API.md`). Nothing was submitted to App Review or
beta review, no certificate was created or revoked, and no agreement or program was accepted.
Secrets appear here only as file paths or secret names.

## IDs

### Team and app

| What | Value |
|---|---|
| Team | `N3DBKUVJS5` (Individual) |
| App Store Connect app | `6836019517`, "Snapreel: Screen Recorder", version 1.0 in Prepare for Submission |
| App ID | `co.arclayer.snapreel` (portal id `MN626WF252`) |
| Distribution certificate (reused) | `R5PJR5R5BS`, iOS Distribution, expires 2027-09-22 |

### App ID capabilities

`co.arclayer.snapreel` now has:
- In-App Purchase, Push Notifications, App Groups (these were already on);
- **Sign in with Apple**, as a primary App ID (new);
- **Associated Domains** (new).

The app's `Snapreel.entitlements` still needs these two keys, which the iPhone-app session owns:
- `com.apple.developer.applesignin` = `["Default"]`;
- `com.apple.developer.associated-domains` = `["applinks:snapreel.video", "webcredentials:snapreel.video"]`.

### Provisioning profile

| What | Value |
|---|---|
| Name | **Snapreel App Store Push**, unchanged, so the pbxproj and `ios.yml` need no edit |
| Profile | `QYH9A7VN24`, UUID `2a462973-e82b-48d3-8195-d97e394db231`, App Store, expires 2027-09-22 |
| Entitlements checked | `aps-environment` = production; `com.apple.developer.applesignin` = Default; `com.apple.developer.associated-domains` = `*`; app group `group.co.arclayer.snapreel` |
| Replaces | `X2Y9HWHQNU`, which went INVALID when the capabilities changed and was deleted |
| Repository secret | `APPSTORE_PROFILE_BASE64` on `arclayer-ltd/snapreel`, updated 2026-11-20, set from stdin after a base64 round-trip check (17,000 characters, 12,749 bytes) |

The broadcast and Live Activity profiles are unchanged, because their App IDs didn't change.

### Sign in with Apple

| What | Value |
|---|---|
| Services ID (web) | `co.arclayer.snapreel.web`, "Snapreel Web" (portal id `37SRVWF4FC`), grouped under primary App ID `co.arclayer.snapreel` |
| Web domains | `snapreel.video`, `jaajkutdglblwtpfcgag.supabase.co` |
| Return URL | `https://jaajkutdglblwtpfcgag.supabase.co/auth/v1/callback` |
| Key | "Snapreel Sign in with Apple", Key ID `3R89L942GD`, primary App ID `co.arclayer.snapreel` |
| Key file | `C:\Users\Hp\.appstoreconnect\siwa\AuthKey_3R89L942GD.p8`. Apple lets you download it once only, so back it up somewhere safe. Never commit it |
| Key settings | `C:\Users\Hp\.appstoreconnect\siwa\siwa.env`: `KEY_ID`, `TEAM_ID`, `CLIENT_IDS=co.arclayer.snapreel,co.arclayer.snapreel.web`, `KEY_PATH` |
| Vercel env | Project `snapreel-push` (team `dev-34969213`), Production, sensitive: `SIWA_KEY_ID`, `SIWA_TEAM_ID`, `SIWA_CLIENT_IDS`, `SIWA_KEY_P8` (the PEM file sent through stdin) |
| Private email relay | Domain `snapreel.video` plus senders `hello@snapreel.video` and `support@snapreel.video`, all three registered and passing SPF |

The root SPF is Hostinger's (`include:_spf.mail.hostinger.com`). Mail that Resend sends passes Apple's relay through Resend's DKIM on `snapreel.video`, which the backend session is adding. If relay mail bounces, check that DKIM record first.

**Supabase Auth, Apple provider** (the backend session sets this):
- Client IDs: `co.arclayer.snapreel.web,co.arclayer.snapreel`. The app's native `id_token` has `aud` = the bundle ID, and the web flow's has `aud` = the Services ID.
- Secret Key (for OAuth): the client-secret JWT described below.

**Token revocation on account deletion**: `POST https://appleid.apple.com/auth/revoke` with:
- `client_id`: the ID that issued the token, which is `co.arclayer.snapreel` for app sign-ins and `co.arclayer.snapreel.web` for web sign-ins;
- `client_secret`: a JWT whose `sub` is that same client ID.

That's why `SIWA_CLIENT_IDS` lists both.

### Subscriptions

**Group** "Snapreel Pro", `22597608`. Localisation en-US: name "Snapreel Pro", app name "Snapreel".

| | Yearly | Monthly |
|---|---|---|
| Product ID | `co.arclayer.snapreel.pro.yearly` | `co.arclayer.snapreel.pro.monthly` |
| Apple ID | `6837012951` | `6837013776` |
| Reference name | Snapreel Pro Yearly | Snapreel Pro Monthly |
| Period, level | 1 year, level 1 | 1 month, level 2 |
| Family Sharing | off | off |
| en-US display name | Snapreel Pro Yearly | Snapreel Pro Monthly |
| en-US description | Unlimited share links, insights and passwords | the same |
| Availability | all 175 territories, plus new territories automatically | the same |
| Price | USD 39.99, with Apple's equalised price in all 175 storefronts (for example GBP 39.99, EUR 44.99 in Germany, JPY 6,000, INR 3,999, BRL 249.90) | USD 5.99, equalised in all 175 (GBP 5.99, EUR 6.99, JPY 1,000, INR 599, BRL 39.90) |
| Introductory offer | 1-week free trial, one period, in all 175 territories, no end date | none |
| Review note | set (what Pro unlocks, where the paywall is, sign-in) | set |
| State | MISSING_METADATA: waiting for the review screenshot | MISSING_METADATA |

Product IDs can never be reused, even after deletion.

**Review screenshot**: still missing. No CI run on the iPhone-app branch had produced `pro.*` screenshots when this was written. Once one has:
1. Download the run's screenshots with `gh run download`.
2. For each subscription, `POST v1/subscriptionAppStoreReviewScreenshots` with `{fileName, fileSize}` and the subscription relationship.
3. PUT each `uploadOperations` part.
4. `PATCH` with `{uploaded: true, sourceFileChecksum: <md5>}`.

The subscriptions move to READY_TO_SUBMIT and are submitted together with the first app version that sells Pro.

### App Store Connect app settings

| What | Value |
|---|---|
| App Store Server Notifications | V2, `https://snapreel.video/api/appstore/notifications`, production and sandbox |
| Privacy Policy URL | `https://snapreel.video/privacy` |
| Support URL (version 1.0) | `https://snapreel.video/support` |
| Marketing URL (version 1.0) | `https://snapreel.video` |
| Licence agreement | Apple's standard EULA. No custom EULA is set |
| Age rating | **4+**. All content questions answered None or No. User-generated content: **Yes** (viewers' comments and reactions). Messaging and chat: No (no private messages between users). Unrestricted web access: **No** (links open in Safari; no in-app browser). Advertising, gambling, loot boxes, parental controls, age assurance, social media, shared location, dating, health topics: No. Brazil shows "Self-rated L" |
| App Privacy | **Published** 2026-11-20. See below |

App Privacy, all **linked to the user's identity**, used **only for App Functionality**, and **not used for tracking**:

| Category | Data type | What it is |
|---|---|---|
| Contact Info | Email Address | Sign-in, alerts |
| Contact Info | Name | The display name shown on watch pages (`profiles.display_name`). It isn't in the plan's list, but the app collects it, so it's declared |
| User Content | Photos or Videos | Shared screen and camera recordings |
| User Content | Audio Data | Shared voice recordings |
| User Content | Other User Content | Comments, reactions, titles, transcripts sent for captions |
| Identifiers | User ID | Supabase user ID, also the StoreKit `appAccountToken` |
| Purchases | Purchase History | Subscription status from Apple |

No tracking, no third-party advertising, no data brokers. If anything new is collected later, update this list and republish before the release that ships it. Two candidates:
- **Crash Data**, if a crash SDK is added;
- **Product Interaction**, if the app sends its own analytics.

### Small Business Program

The account is **not enrolled**. Apple's enrolment page offers the form to this team, and the subscription price points show 70% proceeds (USD 5.99 → 4.20, USD 39.99 → 28.00). Nothing was enrolled.

**Recommendation for the owner:** enrol at https://developer.apple.com/app-store/small-business-program/enroll/. With proceeds under USD 1M a year, Apple's cut drops from 30% to 15% on new purchases (subscriptions already drop to 15% after a subscriber's first year). Enrolment takes effect at the start of the next fiscal month after approval.

## Renewing the web Sign in with Apple client secret (every 6 months)

Supabase's Apple provider needs a "Secret Key (for OAuth)", which is a JWT signed with the key above. Apple accepts one for at most 6 months (15,777,000 s), so web sign-in breaks when it expires. Native sign-in in the app uses `id_token` and doesn't need it.

1. Make a new secret on this PC. The script prints nothing; it writes the secret to a file only you can read:

   ```powershell
   python -I -c "import time,jwt,os; e=dict(l.strip().split('=',1) for l in open(os.path.expanduser(r'~\.appstoreconnect\siwa\siwa.env')) if '=' in l); n=int(time.time()); s=jwt.encode({'iss':e['TEAM_ID'],'iat':n,'exp':n+180*86400,'aud':'https://appleid.apple.com','sub':'co.arclayer.snapreel.web'}, open(e['KEY_PATH']).read(), algorithm='ES256', headers={'kid':e['KEY_ID']}); open(os.path.expanduser(r'~\.appstoreconnect\siwa\client_secret.jwt'),'w').write(s)"
   ```

2. Put it in Supabase, either:
   - in the dashboard (project "Snapreel" → Authentication → Sign In / Providers → Apple → Secret Key (for OAuth)), pasting the file's contents; or
   - through the Management API, `PATCH https://api.supabase.com/v1/projects/jaajkutdglblwtpfcgag/config/auth` with `{"external_apple_secret": "<file contents>"}`, reading the file in the request and never echoing it.
3. Delete `client_secret.jwt` and note the new expiry date (today + 180 days) here.

If the backend makes this secret itself from `SIWA_*` (for example in a scheduled job), the job must run at least every 5 months. Write down where it runs.

Last secret made: _not yet; the backend session makes the first one._

## Draft review notes for the first Pro submission

Paste into App Review Information → Notes, and update anything that changed:

> Snapreel records the screen, camera or voice and keeps everything on the phone for free. Snapreel Pro (auto-renewable subscription, monthly or yearly with a 1-week free trial) adds hosted share links: a link anyone can watch in a browser, with viewer insights, passwords, expiry and branding.
>
> **Sign in:** no demo account is needed. Tap Copy link on any recording (or Settings → Account → Sign in) and choose Sign in with Apple. You can also enter any email address and type the 6-digit code that arrives.
>
> **Make a link:**
> 1. Record anything: tap the record button and choose Camera, or use Voice.
> 2. In the recording's player, tap Copy link. The link is created at once and the video uploads in the background.
> 3. Open the copied link (https://snapreel.video/v/…) in Safari on any device; it plays without an account.
> 4. Comment on it from the browser, and the comment appears in the app's Comments tab.
>
> **Pro:** Settings → Snapreel Pro shows the paywall with both plans, the trial, Restore Purchases, and links to the Terms of Use (Apple's standard EULA) and the Privacy Policy. Free accounts keep 25 links of up to 5 minutes; the paywall also opens on the 26th link, on a recording over 5 minutes, or when setting a password.
>
> **Account deletion:** Settings → Account → Delete account deletes the account, every shared video and comment, and revokes the Sign in with Apple token.
>
> **User-generated content:** viewers can comment and react. The owner can delete any comment and block its author from all their videos. Every watch page has "Report this video", which reaches support@snapreel.video, and the Terms forbid abusive content.
>
> Snapreel sells nothing outside the App Store. The website's pricing page only points to the app.

## Compliance checklist

Status on 20 November 2026. ✅ is done on Apple's side; ⏳ waits on another session or on submission.

| Guideline | What's needed | Status |
|---|---|---|
| 3.1.1 In-app purchase | Pro sold only through StoreKit; no web checkout and no in-app link to one | ✅ products exist with prices. ⏳ the app paywall (app session) and the website must not sell or link to a purchase (website session) |
| 3.1.2 Subscriptions | Paywall shows each plan's price and period, the trial and what it renews into, how to cancel, Restore, and links to Terms of Use and the Privacy Policy. The **App Store description must also link both**: the standard EULA `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` and `https://snapreel.video/privacy`. The version 1.0 description is still empty | ✅ privacy URL, standard EULA, a clear 1-week trial on yearly only. ⏳ paywall copy (app); the description with both links at submission |
| 3.1.3(b) Multiplatform | Pro bought in the app also works on the web dashboard. Allowed because Pro is also sold in-app; the dashboard only links to "Manage in the App Store" | ✅ by design. ⏳ check the dashboard has no purchase path (web session) |
| 4.8 Login services | Sign in with Apple offered next to email codes; no other third-party login | ✅ capability, key, Services ID, email relay. ⏳ the button in the app and on /login, and Supabase's provider config |
| 5.1.1(v) Account deletion | In-app deletion that also revokes Sign in with Apple tokens | ✅ key and `SIWA_*` env for `/auth/revoke`. ⏳ `/api/account/delete` (backend) and the Settings screen (app) |
| 1.2 User-generated content | Filter, report, block, contact info, takedown terms | ✅ age rating answers UGC = Yes. ⏳ report, block and filter (backend, app, web); Terms (website) |
| 5.1.2 Data use and sharing | No tracking, no ads, App Privacy matches the policy | ✅ App Privacy published with no tracking. ⏳ the privacy policy page must list the same data and processors (Supabase, Vercel, Resend, Apple) |
| 2.1 App completeness | Reviewers can sign in and try Pro; the backend is live; the subscriptions are submitted with the build | ✅ draft notes above; no demo account needed. ⏳ live backend, the review screenshot, attaching the subscriptions to the version |
| Age rating | Re-answered for UGC and web access | ✅ 4+, UGC Yes, unrestricted web access No |
| Export compliance | HTTPS only | ✅ `ITSAppUsesNonExemptEncryption` = NO in `Snapreel-Info.plist` |

## Still open

- **Subscription review screenshot**: waits for a CI run on the iPhone-app branch with the `pro.*` paywall screenshot, then the upload described above.
- **Entitlements in `Snapreel.entitlements`** (app session). The new profile already allows them, so a build without them still signs. A build with them needs this profile, which is now in CI.
- **`/.well-known/apple-app-site-association`** on snapreel.video, with `applinks` `/v/*` and `webcredentials` for `N3DBKUVJS5.co.arclayer.snapreel` (backend session).
- **Supabase Apple provider**: the client IDs and the first client secret (backend session).
- **Optional:** the Sign in with Apple server-to-server notification endpoint on the App ID, for "email forwarding turned off" and "account deleted" events from Apple. The contract has no endpoint for it yet.
- **Small Business Program**: the owner's decision; see above.
