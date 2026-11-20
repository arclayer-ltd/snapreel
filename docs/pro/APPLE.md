# Snapreel Pro: Apple setup

Done on 20 November 2026 for the Pro plan (`docs/pro/API.md`). Nothing was submitted to App Review or
beta review, no certificate was created or revoked, and no agreement or program was accepted.
Secrets appear here only as file paths or secret names. The legal and App Store compliance record, with
sources and the owner's open decisions, is [COMPLIANCE.md](COMPLIANCE.md).

## IDs

### Team and app

| What | Value |
|---|---|
| Team | `N3DBKUVJS5`, enrolled as an **Individual** (not a company) |
| Seller (legal entity) | **Rezan Ferdous**, Enayetpur, Sirajganj 6751, Bangladesh. Apple stores the street line as "ENAYETPUR, ENAYETPUR, ENAYETPUR" and the bank account holder as "MD. Rezan Ferdous". The App Store shows this name as the seller |
| Agreements (read 2026-11-20) | Apple Developer Program License Agreement issued 29 Oct 2026, accepted 31 Oct 2026. Paid Apps Agreement active 19 Oct 2026 – 21 Sep 2027; Free Apps active 31 Oct 2026 – 21 Sep 2027. Bank account in Bangladesh (USD) active. U.S. Form W-8BEN and the certificate of foreign status active since 20 Oct 2026. Membership renews 22 Sep 2027 |
| DSA (EU) status | **"Not a trader"**, set 16 Oct 2026 (before Pro existed). An owner decision; see COMPLIANCE.md |
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
| Review screenshot | `pro.paywall` from CI run 35 (1125×2436), uploaded 2026-11-20 | the same |
| State | READY_TO_SUBMIT | READY_TO_SUBMIT |

Product IDs can never be reused, even after deletion.

**Review screenshot**: uploaded 2026-11-20 from CI run 35's `pro.paywall.png` (reserve with `POST v1/subscriptionAppStoreReviewScreenshots`, PUT the parts, then `PATCH` `{uploaded: true, sourceFileChecksum}`). To replace it, delete the old one first.

Both are READY_TO_SUBMIT and are submitted together with the first app version that sells Pro.

### App Store Connect app settings

| What | Value |
|---|---|
| App Store Server Notifications | V2, `https://snapreel.video/api/appstore/notifications`, production and sandbox |
| Privacy Policy URL | `https://snapreel.video/privacy` |
| Support URL (version 1.0) | `https://snapreel.video/support` |
| Marketing URL (version 1.0) | `https://snapreel.video` |
| Licence agreement | Apple's standard EULA. No custom EULA is set. The terms of use at snapreel.video/terms add to it for the service, and the App Store description links both |
| Copyright (version 1.0) | `2026 Rezan Ferdous`, set 2026-11-20 |
| Description (version 1.0, en-US) | Set 2026-11-20 (1,984 characters): features, Free and Pro, the subscription terms, and links to the Terms of Use, Apple's Standard EULA, the Privacy Policy and support. Keywords, subtitle and promotional text are still empty |
| App Review Information | **Not saved yet**: the API refuses it without a contact phone, which is the owner's to enter. The notes to paste are below |
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

Both subscriptions also show `multiSeatStatus: ENABLED` and the markets App Store, **Apple Business** and **Apple
School** (Apple's defaults). The backend gives Pro to one Snapreel account through `appAccountToken`; check before
submission whether seats bought by an organisation could reach it, and turn multi-seat and those markets off if not.

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

## Review notes for the first Pro submission

Paste into App Store Connect → the version → App Review Information → Notes (4,000 characters at most; this is
about 2,000), with contact first name Rezan, last name Ferdous, email support@snapreel.video and the owner's phone
number in +880 format. Sign-in required: **off** (no demo account; reviewers use Sign in with Apple). Written
2026-11-20; update anything that changed before submitting.

> Snapreel records the screen, camera or voice and keeps everything on the iPhone, free and without an account. Snapreel Pro (auto-renewable subscription, monthly, or yearly with a 1-week free trial) adds more to hosted share links: links anyone can watch in a browser, with viewer insights, passwords, expiry and branding.
>
> SIGN IN: no demo account is needed. Use Sign in with Apple: tap Copy link on any recording, or go to Settings > Account > Sign in. You can also type any email address and enter the 6-digit code that arrives.
>
> MAKE A LINK:
> 1. Record something: tap the record button and choose Camera or Voice.
> 2. Open the recording and tap Copy link. The link is made at once and the video uploads in the background.
> 3. Open the copied link (https://snapreel.video/v/...) in Safari on any device. It plays without an account.
> 4. Leave a comment from the browser; it appears in the app on that recording's Comments tab.
>
> SNAPREEL PRO: Settings > Snapreel Pro opens the paywall with both plans, the trial and what it renews into, Restore Purchases, and links to the Terms of Use (EULA) and the Privacy Policy. It also opens on the 26th link, on a recording over 5 minutes, and when setting a password. Free accounts keep 25 links of up to 5 minutes.
>
> ACCOUNT DELETION: Settings > Account > Delete account deletes the account, every shared video and comment, and revokes the Sign in with Apple token. The web dashboard (snapreel.video/app) has the same option.
>
> USER-GENERATED CONTENT (1.2): viewers can comment and react on a link. The link's owner can delete any comment and block its author from all their videos (comment menu > Delete or block). Every watch page has "Report this video", which reaches the developer at support@snapreel.video; the Terms of Use forbid objectionable content, and reported content is reviewed and removed.
>
> Snapreel sells nothing outside the App Store; the website's pricing page only points to the app. The developer is an individual (Rezan Ferdous, Bangladesh). Support: support@snapreel.video.

## Compliance checklist

Moved to [COMPLIANCE.md](COMPLIANCE.md) on 20 November 2026, with each requirement's source, date and status, and
the owner's open decisions.

## Still open

- ~~`/.well-known/apple-app-site-association`~~: live on snapreel.video with `applinks` `/v/*` and `webcredentials` for `N3DBKUVJS5.co.arclayer.snapreel` (checked 2026-11-20).
- **App Review Information**: paste the notes above and add the contact phone (owner).
- **DSA trader status** and the other owner decisions in [COMPLIANCE.md](COMPLIANCE.md).
- **Supabase Apple provider**: the client IDs and the first client secret (backend session).
- **Optional:** the Sign in with Apple server-to-server notification endpoint on the App ID, for "email forwarding turned off" and "account deleted" events from Apple. The contract has no endpoint for it yet.
- **Small Business Program**: the owner's decision; see above.
