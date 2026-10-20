# PR #1 falsification audit

Base: `claude/iphone-weather-app-widgets-7w9fga` at `155d0d6` ("Don't pause Apple Weather after a cancelled request").
Scope: WeatherRepository reuse and pause logic; radar tiles and the HRRR timeline (including the
stale-HRRR 6-hour skip); the Apple Weather to Open-Meteo fallback; the 20-place library limit.

Method: code reading only. Swift is not installed in the audit environment, so nothing here was
compiled or run locally. The new tests in
`Packages/AiSkyKit/Tests/AiSkyKitTests/SharedCacheAuditTests.swift` are expected to fail on this
code, and the CI run on branch `claude/hq-pr1-audit` is the proof (or disproof) of that claim.
Paths below are relative to `Packages/AiSkyKit/Sources/AiSkyKit/` unless they start with another
top-level folder.

## Confirmed bugs (each has a failing test)

### B1. The shared snapshot cache never sees the other process's newer snapshot

- `Storage/SnapshotCache.swift:17-25`: `snapshot(for:)` returns the in-memory copy whenever one
  exists and only reads disk on a miss. Nothing ever invalidates `memory`.
- The cache is documented as "shared by the app and widgets" (`Storage/SnapshotCache.swift:3`), and
  both processes create `SnapshotCache.shared` over the same App Group directory
  (`Storage/SnapshotCache.swift:5`, `Storage/SharedStore.swift:67`).
- Reuse goes through it: `Repository/WeatherRepository.swift:101` and `:121-125`;
  the widget uses `WeatherRepository(weatherKitAvailable: false)` (`AiSkyWidgets/Timeline/WidgetDataLoader.swift:9`, `:26`).
- Effect: once a widget extension process has stored or read a snapshot for a location, it keeps
  serving that copy. When the app later stores a fresh Apple Weather snapshot, the widget still sees
  its own older Open-Meteo copy, finds it stale, refetches Open-Meteo and overwrites the app's file.
  This defeats the intent stated at `Repository/WeatherRepository.swift:107-111` ("Widgets take the
  app's Apple Weather snapshots"). The same applies in reverse to the app process.
- How often it bites depends on how long iOS keeps the widget extension process alive, which this
  audit did not measure. The unit-level behaviour is deterministic.
- Test: `SharedCacheAuditTests.testWidgetSeesTheAppsNewerSnapshot`.
- Seen failing: CI run 39361633998 (commit `3fd1ec0`).
- **Fix status: fixed on `claude/hq-pr1-audit`, pending CI.** Each in-memory snapshot now records
  the version of its file (modification date plus file number; atomic writes change both) when it
  was read or written. `snapshot(for:)` does one `stat` per call and re-reads the file when its
  version differs; with no file on disk the memory copy still stands (as before).

### B2. Summaries written by one process are erased by the other (lost update)

- `Storage/SnapshotCache.swift:68-74`: `loadSummaries()` reads `summaries.json` once and caches it in
  `summaries` forever.
- `Storage/SnapshotCache.swift:33-35` and `:56-63` then write the whole in-memory dictionary back,
  so any entry the other process added after the first read is dropped from disk. The "never replace
  a newer entry" check at `:60` also compares against the stale in-memory copy.
- Effect: library rows and the multi-location widget lose cached summaries and refetch them; the
  extra network work is the main cost.
- Same root cause as B1 (per-process memory never revalidated against disk).
- Test: `SharedCacheAuditTests.testSummaryStoredByTheOtherProcessSurvivesALaterWrite`.
- Seen failing: CI run 39361633998 (commit `3fd1ec0`).
- **Fix status: fixed on `claude/hq-pr1-audit`, pending CI.** `summaries.json` is version-checked the
  same way on every read, and every write goes through `updateSummaries`, which starts from the
  current file, changes only this process's keys, and writes atomically. The "never replace a newer
  entry" check now compares against the file. Residual: the read-merge-write is not locked across
  processes, so two writes within the same instant can still lose one entry (would need
  `NSFileCoordinator` or a file lock); the window is now one write instead of the process lifetime.

## Risks and questions (no test added unless noted)

### WeatherRepository pause logic

- R1. Pause is unbounded if the recorded failure is in the future relative to `now`.
  `Repository/WeatherRepository.swift:50-52` only checks `now.timeIntervalSince(failure.date) < 15 min`,
  which is also true for any negative interval, and `:84` stamps the failure with the wall clock
  `Date()`. If the device clock moves backwards after a failure, Apple Weather stays paused until the
  clock catches up, not for 15 minutes. Needs a large backward clock change, so listed as a risk.
  Re-checked against the code: the reading holds. Test added:
  `WeatherKitPauseAuditTests.testPauseEndsWhenTheClockMovedBackwards` (pushed alone first, commit
  `fe1b8e2`, expected to fail). **Fixed, pending CI**: the pause now applies only while the elapsed
  time is in `0..<15 min`; `weatherKitStatusMessage` uses the same range so it doesn't report a
  pause that `shouldUseWeatherKit` no longer applies.
- R2. `weatherKitStatusMessage` (`Repository/WeatherRepository.swift:61-76`) ignores both the
  `weatherKitAvailable` override (it reads `BuildConfiguration.isWeatherKitEnabled` at `:63`) and the
  injected `now` (it uses `Date()` at `:72`), while `shouldUseWeatherKit` honours both. In production
  both are the same values, so this is a testability and consistency issue, not a user-visible bug.
- R3. Likely duplicate fallback notes. On a real Apple Weather failure, `:167` records the failure,
  `:169` appends "Apple Weather was unavailable, so this forecast uses Open-Meteo.", and then
  `:185` appends the different string from `:73` ("Apple Weather is temporarily unavailable (...)").
  The `!notes.contains(message)` guard at `:185` cannot catch it because the strings differ. Not
  unit-testable without injecting a WeatherKit failure (`weatherKitForecast` at `:195-201` is not
  injectable), so not claimed as a bug.
- R4. `summaries(...)` never records or clears the pause. WeatherKit errors are swallowed by `try?`
  at `:226`, so a failing Apple Weather is retried for every stale library location on every refresh
  instead of backing off. Behaviour is still correct (Open-Meteo fills the gaps at `:239-241`).
- Verified, no issue: cancellations do not start the pause (`:82`) and there is a test for it
  (`Tests/AiSkyKitTests/StorageAndUnitsTests.swift:379-397`). `canReuse` (`:112-118`) matches its doc
  comment and existing tests (`StorageAndUnitsTests.swift:352-376`).

### Apple Weather to Open-Meteo fallback

- R5. When Apple Weather succeeds but Open-Meteo fails and the location has no stored time zone,
  `Repository/WeatherRepository.swift:148-152` cannot copy Open-Meteo's zone, so the snapshot keeps
  `TimeZone.current` from `Providers/WeatherKit/WeatherKitProvider.swift:92` (the device zone, not
  the place's). WeatherKit library summaries do the same (`WeatherKitProvider.swift:109`). A newly
  saved place in another zone could show times in the device zone until a full fetch fills it in.
- R6. If both providers fail, `:175-176` rethrows the Open-Meteo error and does not record the
  Apple Weather failure. Probably intended (being offline is not Apple Weather's fault); question
  for the author.

### Radar tiles and HRRR timeline

- R7. The 6-hour HRRR skip is measured against the latest radar frame, not against `now`
  (`Providers/Radar/RadarService.swift:223`). If the IEM radar metadata is itself hours old
  (`:153`, `:196`), nothing flags it: the timeline's "now" frame and the following "forecast" frames
  can all be in the past. No staleness check on `latestValidTime` exists. Whether the UI exposes
  the frame times clearly enough was not verified.
  Re-checked against the code: the reading holds, but narrowly. `noaaTimeline` receives `now` and
  only uses it for `fetchedAt` and when the metadata is missing; when the IEM metadata is fresh
  (the normal case) measuring against the latest frame is equivalent to measuring against `now`.
  It only matters when the IEM mosaic itself has stalled, and then there is no newer radar to show
  anyway. No test added: the right behaviour (a staleness threshold, and whether to drop the
  forecast, flag the timeline, or fall back to RainViewer) is a product decision, not a contained fix.
- R8. `RadarTiling.keys` (`Providers/Radar/RadarTiling.swift:63-67`) converts `Double` to `Int`
  without checking for non-finite values; e.g. `minX = -infinity` with a finite `maxX` passes the
  guard at `:63` and traps at `:64`. The only caller passes a MapKit draw rect
  (`AiSky/Views/Radar/RadarOverlay.swift:60`), which should be finite, so this is a hardening note.
- Verified, no issue: the 6-hour boundary is inclusive (`RadarService.swift:223`, `<=`), consistent
  with "older than this is skipped" at `:124-126`; leads are kept to quarter hours and at most
  1080 minutes (`:233`); forecast frame ids include the run stamp, so a new run never reuses old
  tiles (`:237`); shard choice is stable per tile (`:74`). Existing tests cover the stale-run skip
  (`StorageAndUnitsTests.swift:254-263`).

### 20-place library limit

- No bug found. The limit is enforced in `Storage/LocationLibrary.swift:39-47` (duplicate check
  first, then `canAdd` at `:30-32`), the app routes adds through it (`AiSky/State/AppModel.swift:256`),
  and tests cover 20 places and the 21st (`StorageAndUnitsTests.swift:13-24`).
- R9. `Storage/SharedStore.swift:113` silently truncates to 20 on save. Today every write goes
  through `LocationLibrary`, so this is a safety net, but any future path that writes more than 20
  places would lose the extra places without telling the user.

## What remains unverified

- Nothing was compiled or run here (no Swift toolchain). The two tests are claimed to fail on the
  audited code; the CI run on `claude/hq-pr1-audit` decides.
- Real-device behaviour of B1/B2 (how long the widget extension process lives) was not measured.
- No network calls to the IEM, RainViewer, Open-Meteo or Apple Weather were made.
