# Install Ai Sky with TestFlight (no Mac needed)

GitHub's Mac build servers build Ai Sky and upload it to TestFlight, Apple's app for installing
test versions. You only need a web browser (a Windows PC is easiest; an iPhone works) and your
iPhone.

**Cost:** the [Apple Developer Program](https://developer.apple.com/programs/) is $99 a year.
TestFlight, Apple Weather (500,000 requests a month), GitHub's build servers (free for public
repositories) and the weather and radar data are all free.

The IDs below come from `AISKY_BUNDLE_ID_PREFIX = com.lasmith1689` in `Config/Shared.xcconfig`:

| What | Value |
|---|---|
| App ID | `com.lasmith1689.AiSky` |
| Widget App ID | `com.lasmith1689.AiSky.Widgets` |
| App Group | `group.com.lasmith1689.AiSky` |

## 1. Join the Apple Developer Program

1. On your iPhone, install the **Apple Developer** app from the App Store.
2. Open **Account**, tap **Enroll Now**, and follow the steps. Use your legal name, and have
   two-factor authentication turned on for your Apple Account.
3. Pay the $99 fee. Wait for the "Welcome to the Apple Developer Program" email; it can take from
   a few minutes to a couple of days.

## 2. Register the app's IDs

Go to [developer.apple.com/account](https://developer.apple.com/account) ▸ **Certificates, IDs &
Profiles** ▸ **Identifiers**.

1. **App Group:** click **+**, choose **App Groups**, then enter Description `Ai Sky` and
   Identifier `group.com.lasmith1689.AiSky`. Click **Continue**, then **Register**.
2. **App:** click **+**, choose **App IDs** ▸ **App**, then enter Description `Ai Sky` and
   Bundle ID (Explicit) `com.lasmith1689.AiSky`. Under **Capabilities**, tick **App Groups**. For
   Apple Weather, also tick **WeatherKit** on both the **Capabilities** and **App Services** tabs.
   Click **Continue**, then **Register**.
3. **Widgets:** do the same with Description `Ai Sky Widgets` and Bundle ID
   `com.lasmith1689.AiSky.Widgets`, ticking only **App Groups**.
4. Open each of the two App IDs again, click **Configure** (or **Edit**) next to **App Groups**,
   tick `group.com.lasmith1689.AiSky`, and click **Save**.

If Apple says an ID is already taken, use your own prefix (for example `com.yourname`) for all
three IDs, and add it in GitHub as a repository **variable** named `AISKY_BUNDLE_ID_PREFIX`
(see step 5), or ask Claude to change `Config/Shared.xcconfig`.

## 3. Create the app in App Store Connect

In [App Store Connect](https://appstoreconnect.apple.com), open **Apps**, click **+** ▸ **New App**, and fill in:

- **Platforms:** iOS
- **Name:** anything that's free on the App Store, for example `Ai Sky Weather`. The name under
  the icon on your phone stays **Ai Sky**.
- **Primary Language:** English (U.S.)
- **Bundle ID:** `com.lasmith1689.AiSky`
- **SKU:** `aisky`
- **User Access:** Full Access

Then set up TestFlight now, so you don't have to come back later: open the new app's **TestFlight**
tab, click **+** next to **Internal Testing**, name the group `Me`, turn on automatic distribution,
and add yourself as a tester. Every build will then reach you by itself.

## 4. Create an API key

GitHub uses this key to sign and upload builds for you.

1. In App Store Connect, open **Users and Access** ▸ **Integrations** ▸ **App Store Connect API**
   ▸ **Team Keys**. The first time, click **Request Access** and accept the terms.
2. Click **+** (Generate API Key). Name it `GitHub`, set **Access** to **Admin**, and click **Generate**.
   Admin access is what lets GitHub use Apple's cloud signing, so you never have to manage
   certificates.
3. Click **Download** to save `AuthKey_XXXXXXXXXX.p8`. Apple lets you download it **only once**.
   Keep it private.
4. Write down the **Key ID** (in the list) and the **Issuer ID** (above the list).
5. Your **Team ID** is at [developer.apple.com/account](https://developer.apple.com/account) ▸
   **Membership details**.

## 5. Add the key to GitHub

Open [the repository's Actions secrets](https://github.com/lasmith1689-sys/Ai-sky/settings/secrets/actions)
(**Settings** ▸ **Secrets and variables** ▸ **Actions**) and add four **repository secrets** with
**New repository secret**:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Your Team ID |
| `ASC_KEY_ID` | The Key ID |
| `ASC_ISSUER_ID` | The Issuer ID |
| `ASC_KEY_P8` | The whole text of the `.p8` file, including the `BEGIN` and `END` lines |

To copy the `.p8` text:

- **Windows:** right-click the file ▸ **Open with** ▸ **Notepad**, then press Ctrl+A and Ctrl+C.
- **iPhone:** in the Files app, rename the file to `AuthKey.txt`, open it, then **Select All** ▸ **Copy**.

GitHub encrypts secrets and hides them from build logs, and people who copy (fork) the repository
can't read them. Never paste the key into a chat, an issue, or a commit.

Optional settings go on the **Variables** tab of the same page:

| Variable | Value |
|---|---|
| `AISKY_ENABLE_WEATHERKIT` | `YES` for Apple Weather (tick WeatherKit in step 2 first) |
| `AISKY_BUNDLE_ID_PREFIX` | Only if you used your own prefix in step 2 |

## 6. Build

Tell Claude the secrets are in, or start a build yourself: on GitHub, open **Actions** ▸ **TestFlight**,
open the latest run, and click **Re-run all jobs**. After the code is merged into `main`, you can
also use **Run workflow**.

Building and uploading takes about 15 minutes. Apple then processes the build, usually within
5–30 minutes, and emails you when it's ready. After that, every change pushed to the repository
is built and uploaded the same way.

## 7. Install on your iPhone

1. On your iPhone, install **TestFlight** from the App Store and sign in with the same Apple Account.
2. Open the TestFlight invitation email on your iPhone and tap **View in TestFlight** (or just
   open TestFlight), then tap **Install** next to Ai Sky. Later builds show up as updates in
   TestFlight.

If Ai Sky doesn't show up, check that you added yourself to the `Me` group (end of step 3).

Each TestFlight build works for 90 days, and every new build starts a fresh 90 days.

## If a build fails

The failed run in **Actions** ends with a one-line explanation:

| Message | Fix |
|---|---|
| "Create the app in App Store Connect…" | Step 3. The bundle ID must match exactly. |
| "Register the App Group…" | Step 2. Both App IDs need the App Group ticked (step 2.4). |
| "Turn on WeatherKit…" | Tick WeatherKit on both tabs (step 2.2), or set `AISKY_ENABLE_WEATHERKIT` to `NO`. |
| "Check the API key…" | The key needs **Admin** access, and all three values must come from the same key. |
| "That build number was already used" | Click **Re-run all jobs**. |

Until the secrets are added, each run only checks that the App Store version builds, and ends
with "Nothing was uploaded".
