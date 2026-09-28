# Ai Sky

A Dark Sky–style weather app for iPhone, with Precip-style rainfall tracking, radar, air quality, and Home Screen + Lock Screen widgets.

## Features

**Forecast** (swipe between your places)
- Current temperature, **feels-like (real feel)** with an explanation ("Humidity is making it feel warmer"), today's high/low
- **Next hour, minute by minute**: Dark Sky's precipitation graph with LIGHT / MED / HEAVY guides and plain-English summaries like *"Light rain starting in 12 min, stopping 25 min later."*
- Next 48 hours: a condition-colored timeline with sunrise/sunset, rain chances, and charts for temperature, feels-like, precipitation, wind, UV, and humidity
- 10-day forecast with temperature range bars and a weekly summary; tap any day for its hourly charts and stats
- **Precipitation (Precip-style)**: rain totals for the past hour, 24 hours, 7 days, and 30 days; today so far; the next hour, 24 hours, and 7 days; when it last rained; a 3-week daily rainfall chart
- **Air quality**: US EPA or European AQI, the main pollutant, health advice, a 5-day outlook, PM2.5/PM10/O₃/NO₂/SO₂/CO readings, and pollen where it's available
- Details: humidity and dew point, wind with a compass and gusts, UV index with sun-protection hours, sunrise/sunset arc, pressure trend, visibility, cloud cover, and moon phase
- Government weather alerts (NWS for U.S. places, or worldwide with Apple Weather)

**Rainfall history** (Precip-style; tap *Rainfall History* on the Precipitation card)
- Totals for the past 7 days, 30 days, this month, this year, 12 months, or **any date range back to 1940**
- Compared with the **1991–2020 normal** for the same days, and with the same days last year
- Daily, weekly, or monthly bars with normal markers, and a running-total chart against normal
- Wet days, the wettest day, and the longest dry spell. Tap any wet day to see it hour by hour.

**Time Machine** (Dark Sky-style; tap *Time Machine* on the 10-day forecast)
- The weather on **any date since 1940**, or up to two weeks ahead: conditions, high/low, feels-like, hourly temperature, precipitation, and wind, humidity, sunrise/sunset, and moon phase
- Step day by day, pick a date, or jump to this day 1, 10, 25, or 50 years ago

**Radar** (its own tab)
- Animated precipitation radar with play/pause, a timeline scrubber, and a color legend
- High-resolution **NOAA NEXRAD** over the U.S. and **RainViewer** everywhere else (chosen automatically, or pick one)
- Your saved places are pinned with their current temperatures. Tap a pin to open its forecast.
- **Touch and hold anywhere on the map** to see that spot's rainfall history or open it in the Time Machine, or to save it to your places.

**Location library**
- Save **up to 20 places** (your current location doesn't count toward the 20). Search by city, address, ZIP code, or landmark.
- Reorder, rename ("Home", "Cabin"), and delete places. The list shows each place's current conditions and local time.

**Widgets** (each widget can show your current location or any saved place)

| Widget | Home Screen | Lock Screen |
|---|---|---|
| Conditions | small, medium, large | circular (temp gauge), rectangular, inline |
| Next Hour | small, medium | rectangular (with minute graph), inline |
| Air Quality | small | circular (AQI gauge), rectangular, inline |
| Rainfall | small, medium | rectangular |
| My Places | medium (3 places), large (6 places) | — |

**Notifications (optional)**: "Rain starting soon" and severe-weather alerts for the places you choose.

## What you need

- A **Mac with Xcode 16 or newer** (Xcode 26 recommended)
- An **iPhone running iOS 17 or newer**
- An **Apple ID**. A free one works. The paid [Apple Developer Program](https://developer.apple.com/programs/) ($99/year) is recommended: apps you install with a free Apple ID expire after 7 days, and only paid accounts can turn on Apple Weather (see below).

## Put it on your iPhone

1. **Get the code.** In Terminal, run:
   ```sh
   git clone https://github.com/lasmith1689-sys/Ai-sky.git
   cd Ai-sky
   open AiSky.xcodeproj
   ```
2. **Set your signing info.** In Xcode, open `Config/Shared.xcconfig`:
   - `AISKY_BUNDLE_ID_PREFIX`: change it if Xcode says the bundle identifier isn't available. Any unique reverse-DNS name works, for example `com.yourname`.
   - `DEVELOPMENT_TEAM`: your Team ID. You can also leave it blank and choose your team for **both** the `AiSky` and `AiSkyWidgetsExtension` targets under *Signing & Capabilities*.
3. **Prepare your iPhone.** Connect it with a cable, or use the same Wi-Fi network after you've paired it once. Then turn on **Settings ▸ Privacy & Security ▸ Developer Mode** and restart when asked.
4. In Xcode's toolbar, choose the **AiSky** scheme and your iPhone, then press **Run** (⌘R).
5. **Free Apple ID only:** the first launch shows "Untrusted Developer". Go to **Settings ▸ General ▸ VPN & Device Management**, tap your Apple ID, and tap **Trust**.
6. In the app, allow location access, or search for places in the **Locations** tab.

### Add widgets
- **Home Screen:** touch and hold an empty area, tap **Edit ▸ Add Widget**, and search for **Ai Sky**. To choose which place a widget shows, touch and hold the widget and tap **Edit Widget**.
- **Lock Screen:** touch and hold the Lock Screen, tap **Customize ▸ Lock Screen**, tap the widget area, and choose **Ai Sky**.

## Turn on Apple Weather (optional, recommended)

Apple Weather is the service Dark Sky became after Apple bought it. It adds **true minute-by-minute rain forecasts** and **worldwide government alerts**. It needs a paid Apple Developer Program membership.

1. In `Config/Shared.xcconfig`, set `AISKY_ENABLE_WEATHERKIT = YES`.
2. Sign in at [developer.apple.com ▸ Certificates, Identifiers & Profiles ▸ Identifiers](https://developer.apple.com/account/resources/identifiers/list) and open your app's identifier (for example `com.lasmith1689.AiSky`). Xcode creates it the first time you run the app. Turn on **WeatherKit** on the **Capabilities** tab *and* on the **App Services** tab, then save.
3. Run the app again. Apple can take about 30 minutes to activate WeatherKit for a new app. Until then the app uses Open-Meteo and shows a note at the bottom of the forecast.

You can switch sources any time in **Settings ▸ Weather Data ▸ Forecast Source**. Without WeatherKit, the next-hour graph uses Open-Meteo's 15-minute data; in the U.S. that comes from NOAA's HRRR model.

## Where the data comes from

| Data | Source | Notes |
|---|---|---|
| Forecasts, feels-like, 15-minute precipitation, rainfall history | [Open-Meteo](https://open-meteo.com/) | Free, no API key, CC BY 4.0, for non-commercial use |
| Minute-by-minute forecasts, alerts (optional) | Apple Weather (WeatherKit) | Paid developer account |
| Air quality and pollen | Open-Meteo (Copernicus CAMS models) | Pollen covers Europe only |
| Weather history (Time Machine, rainfall history, normals) | Open-Meteo [forecast](https://open-meteo.com/en/docs) (last 3 months) and [historical](https://open-meteo.com/en/docs/historical-weather-api) APIs (ERA5, ERA5-Land, ECMWF IFS reanalysis) | 1940 onwards; values are averages over a 9–25 km grid, not a local station's readings |
| U.S. alerts | [National Weather Service](https://www.weather.gov/) | Used when Apple Weather is off |
| Radar (U.S.) | NOAA NEXRAD via [Iowa Environmental Mesonet](https://mesonet.agron.iastate.edu/) | Updated every 5 minutes, past 50 minutes |
| Radar (worldwide) | [RainViewer](https://www.rainviewer.com/api.html) | Free tier: past 2 hours, native zoom up to 7 (the app enlarges tiles when you zoom in further) |

Known limits:
- **Background alerts are best-effort.** iOS decides how often apps refresh in the background (usually every 15–60 minutes), so a "rain soon" alert can arrive late. Keep **Background App Refresh** on for Ai Sky.
- **Widgets refresh roughly every 20–60 minutes**, as iOS allows. They reuse the app's latest forecast when it's recent, and otherwise download fresh data from Open-Meteo.
- **Past rainfall totals are estimates.** Open-Meteo derives them from weather-model analyses and reanalysis, not rain gauges, so a local downpour can be under- or over-counted.
- **Normals are downloaded once per place** (30 years of daily data, about 150 KB) and kept on your phone.

## Project layout

```
AiSky.xcodeproj          Xcode project (app + widget extension + shared package)
Config/                  Shared.xcconfig (bundle ID, team, WeatherKit switch), Info.plists, entitlements
AiSky/                   The iOS app (SwiftUI)
  State/                 App state, weather cache, location + search
  Services/              Background refresh, notifications
  Views/                 Forecast, Radar, Locations, Settings screens
AiSkyWidgets/            WidgetKit extension (Home Screen + Lock Screen widgets)
Packages/AiSkyKit/       Shared Swift package: models, API clients, caching, summaries, charts
  Tests/                 Unit tests with sample API responses
```

## Tests

```sh
swift test --package-path Packages/AiSkyKit
```

GitHub Actions runs these tests on every push, builds the app and widgets for the iOS Simulator, and runs the tests there too.

## Troubleshooting

- **"Failed to register bundle identifier" or "No profiles for…"**: change `AISKY_BUNDLE_ID_PREFIX` in `Config/Shared.xcconfig` to something unique, and make sure a team is selected for both targets.
- **Widgets don't list your saved places**: the app and the widget extension must share the same App Group. It's derived automatically from `AISKY_BUNDLE_ID_PREFIX`, so if you changed bundle IDs by hand in Xcode, change them back or keep the prefixes matching.
- **"Apple Weather was unavailable" note**: WeatherKit isn't enabled for your App ID yet (see above), or it's still activating.
- **The app stopped opening after a week**: that's how free Apple ID installs work. Run it from Xcode again, or join the Apple Developer Program.
