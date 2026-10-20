# PR #1 falsification audit

Base: `claude/iphone-weather-app-widgets-7w9fga` at `155d0d6` ("Don't pause Apple Weather after a cancelled request").
Scope: WeatherRepository reuse and pause logic; radar tiles and the HRRR timeline (including the
stale-HRRR 6-hour skip); the Apple Weather to Open-Meteo fallback; the 20-place library limit.

Method: code reading. Swift is not installed in the audit environment, so nothing here was
compiled or run locally; CI on branch `claude/hq-pr1-audit` is the only execution evidence.
The audit tests are in `Packages/AiSkyKit/Tests/AiSkyKitTests/SharedCacheAuditTests.swift` and
`Packages/AiSkyKit/Tests/AiSkyKitTests/WeatherKitPauseAuditTests.swift`.
Paths below are relative to `Packages/AiSkyKit/Sources/AiSkyKit/` unless they start with another
top-level folder. Line numbers refer to the code at `33a62e4` unless marked "at `155d0d6`".

## Status at `33a62e4`

B1, B2 and R1 are fixed in `33a62e4`. Evidence (all CI runs are on branch `claude/hq-pr1-audit`):

- Failing first: commit `fe1b8e2`, CI run 39366659883. Its AiSkyKit job 118444940697 failed in
  the "Unit tests (macOS)" step on exactly the three audit tests (B1, B2, R1, listed below); the
  iOS Simulator step was skipped after that failure. The run's overall conclusion is shown as
  "cancelled", not "failure": the App Store archive and iOS app jobs were cancelled, and the
  Publish screenshots job succeeded.
- Fixed: commit `33a62e4`, CI run 39366825098, conclusion success, all 4 jobs green (AiSkyKit unit
  tests, iOS app + widgets, App Store archive dry run, Publish screenshots). AiSkyKit job
  118446307063 reports "Executed 133 tests, with 0 failures" on both macOS and the iOS Simulator.
- Earlier, B1 and B2 were also seen failing in CI run 39361633998 (commit `3fd1ec0`).

R7 stays open as a product decision (see below). Other risks (R2 to R6, R8, R9) are unchanged.

## Confirmed bugs (each has a failing-first test)

### B1. The shared snapshot cache never saw the other process's newer snapshot

- At `155d0d6`, `Storage/SnapshotCache.swift:17-25`: `snapshot(for:)` returned the in-memory copy
  whenever one existed and only read disk on a miss. Nothing ever invalidated `memory`.
- The cache is documented as "shared by the app and widgets" (`Storage/SnapshotCache.swift:3`), and
  both processes create `SnapshotCache.shared` over the same App Group directory
  (`Storage/SnapshotCache.swift:10`, `Storage/SharedStore.swift:67`).
- Reuse goes through it: `Repository/WeatherRepository.swift:103` and `:123-127`;
  the widget uses `WeatherRepository(weatherKitAvailable: false)` (`AiSkyWidgets/Timeline/WidgetDataLoader.swift:9`, `:26`).
- Effect: once a widget extension process had stored or read a snapshot for a location, it kept
  serving that copy. When the app later stored a fresh Apple Weather snapshot, the widget still saw
  its own older Open-Meteo copy, found it stale, refetched Open-Meteo and overwrote the app's file.
  This defeated the intent stated at `Repository/WeatherRepository.swift:109-113` ("Widgets take the
  app's Apple Weather snapshots"). The same applied in reverse to the app process.
- How often it bit depends on how long iOS keeps the widget extension process alive, which this
  audit did not measure. The unit-level behaviour is deterministic.
- Test: `SharedCacheAuditTests.testWidgetSeesTheAppsNewerSnapshot`.
- **Fix status: FIXED in `33a62e4`** (evidence above). Each in-memory snapshot records the version
  of its file (modification date plus file number; atomic writes change both) when it was read or
  written (`Storage/SnapshotCache.swift:14-23`, `:115-121`). `snapshot(for:)` (`:35-48`) does one
  `stat` per call and re-reads the file when its version differs; with no file on disk the memory
  copy still stands, as before (`:38-41`).

### B2. Summaries written by one process were erased by the other (lost update)

- At `155d0d6`, `Storage/SnapshotCache.swift:68-74`: `loadSummaries()` read `summaries.json` once
  and cached it in `summaries` forever. `:33-35` and `:56-63` then wrote the whole in-memory
  dictionary back, so any entry the other process added after the first read was dropped from
  disk. The "never replace a newer entry" check at `:60` also compared against the stale
  in-memory copy.
- Effect: library rows and the multi-location widget lost cached summaries and refetched them; the
  extra network work was the main cost.
- Same root cause as B1 (per-process memory never revalidated against disk).
- Test: `SharedCacheAuditTests.testSummaryStoredByTheOtherProcessSurvivesALaterWrite`.
- **Fix status: FIXED in `33a62e4`** (evidence above). `loadSummaries()` (`Storage/SnapshotCache.swift:91-100`)
  version-checks `summaries.json` the same way on every read, and every write goes through
  `updateSummaries` (`:105-113`), which starts from the current file, changes only this process's
  keys, and writes atomically. Callers: `store(_:)` at `:59`, `remove(locationID:)` at `:65`,
  `store(summaries:)` at `:78-86`; the "never replace a newer entry" check at `:82` now compares
  against the file.
- Residual (not fixed): summaries have no cross-process lock. The read-merge-write in
  `updateSummaries` is not coordinated between processes, so two writes in the same instant can
  still lose one entry (would need `NSFileCoordinator` or a file lock); the window is now one write
  instead of the process lifetime.
- Residual (pre-existing, not fixed): a corrupt or undecodable `summaries.json` still decodes as an
  empty dictionary (`try?` with `?? [:]` at `Storage/SnapshotCache.swift:96-97`; the same at
  `155d0d6` `:70-71`), and the next write then overwrites the file with only this process's
  entries. Cost is refetching summaries, not a crash.

## Risks and questions (no test added unless noted)

### WeatherRepository pause logic

- R1. Pause was unbounded if the recorded failure is in the future relative to `now`.
  At `155d0d6`, `Repository/WeatherRepository.swift:50-52` only checked
  `now.timeIntervalSince(failure.date) < 15 min`, which is also true for any negative interval, and
  the failure is stamped with the wall clock `Date()` (now `:86`). If the device clock moved
  backwards after a failure, Apple Weather stayed paused until the clock caught up, not for 15
  minutes. Test: `WeatherKitPauseAuditTests.testPauseEndsWhenTheClockMovedBackwards` (pushed alone
  first in commit `fe1b8e2`).
  **Fix status: FIXED in `33a62e4`** (evidence above). The pause now applies only while the elapsed
  time is in `0..<15 min` (`Repository/WeatherRepository.swift:52-55`); `weatherKitStatusMessage`
  uses the same range (`:73-74`) so it doesn't report a pause that `shouldUseWeatherKit` no longer
  applies.
- R2. `weatherKitStatusMessage` (`Repository/WeatherRepository.swift:63-78`) ignores both the
  `weatherKitAvailable` override for its first check (it reads `BuildConfiguration.isWeatherKitEnabled`
  at `:65`) and the injected `now` (it uses `Date()` at `:74`), while `shouldUseWeatherKit` honours
  both. In production both are the same values, so this is a testability and consistency issue,
  not a user-visible bug.
- R3. Likely duplicate fallback notes. On a real Apple Weather failure, `:169` records the failure,
  `:171` appends "Apple Weather was unavailable, so this forecast uses Open-Meteo.", and then
  `:187-188` appends the different string from `:75` ("Apple Weather is temporarily unavailable (...)").
  The `!notes.contains(message)` guard at `:187` cannot catch it because the strings differ. Not
  unit-testable without injecting a WeatherKit failure (`weatherKitForecast` at `:197-203` is not
  injectable), so not claimed as a bug.
- R4. `summaries(...)` never records or clears the pause. WeatherKit errors are swallowed by `try?`
  at `:228`, so a failing Apple Weather is retried for every stale library location on every refresh
  instead of backing off. Behaviour is still correct (Open-Meteo fills the gaps at `:241-243`).
- Verified, no issue: cancellations do not start the pause (`:84`) and there is a test for it
  (`Tests/AiSkyKitTests/StorageAndUnitsTests.swift:379-397`). `canReuse` (`:114-120`) matches its doc
  comment and existing tests (`StorageAndUnitsTests.swift:352-376`).

### Apple Weather to Open-Meteo fallback

- R5. When Apple Weather succeeds but Open-Meteo fails and the location has no stored time zone,
  `Repository/WeatherRepository.swift:150-154` cannot copy Open-Meteo's zone, so the snapshot keeps
  `TimeZone.current` from `Providers/WeatherKit/WeatherKitProvider.swift:92` (the device zone, not
  the place's). WeatherKit library summaries do the same (`WeatherKitProvider.swift:109`). A newly
  saved place in another zone could show times in the device zone until a full fetch fills it in.
- R6. If both providers fail, `Repository/WeatherRepository.swift:177-178` rethrows the Open-Meteo
  error and does not record the Apple Weather failure. Probably intended (being offline is not
  Apple Weather's fault); question for the author.

### Radar tiles and HRRR timeline

- R7. **Open product decision; not fixed and no test added.** The 6-hour HRRR skip is measured
  against the latest radar frame, not against `now` (`Providers/Radar/RadarService.swift:223`). If
  the IEM radar metadata is itself hours old (`:153`, `:196`), nothing flags it: the timeline's
  "now" frame and the following "forecast" frames can all be in the past. No staleness check on
  `latestValidTime` exists. Whether the UI exposes the frame times clearly enough was not verified.
  Re-checked against the code: the reading holds, but narrowly. `noaaTimeline` receives `now` and
  only uses it for `fetchedAt` and when the metadata is missing; when the IEM metadata is fresh
  (the normal case) measuring against the latest frame is equivalent to measuring against `now`.
  It only matters when the IEM mosaic itself has stalled, and then there is no newer radar to show
  anyway. The right behaviour (a staleness threshold, and whether to drop the forecast, flag the
  timeline, or fall back to RainViewer) is for the product owner to decide before any fix.
- R8. `RadarTiling.keys` (`Providers/Radar/RadarTiling.swift:59-68`) converts `Double` to `Int`
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

## What remains unverified or open

- Nothing was compiled or run in the audit environment (no Swift toolchain); the fix evidence is
  CI only. The full job logs could not be downloaded here; the test results above come from the
  jobs' check-run annotations and step conclusions.
- Real-device behaviour of B1/B2 (how long the widget extension process lives) was not measured,
  and the fix was not exercised across two real processes, only through the unit tests.
- Open: R7 (product decision); the summaries cross-process lock and the corrupt `summaries.json`
  handling noted under B2.
- No network calls to the IEM, RainViewer, Open-Meteo or Apple Weather were made.
