import AiSkyKit
import Foundation
import Observation

/// Loads radar frames and drives the animation.
@MainActor
@Observable
final class RadarViewModel {
    private(set) var timeline: RadarTimeline?
    var frameIndex = 0
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var source: RadarSource = .rainViewer
    /// Frames whose on-screen tiles are all loaded (or failed), for the timeline's progress.
    private(set) var readyFrameIDs: Set<String> = []

    let tileStore = RadarTileStore()
    private let service = RadarService()
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        tileStore.onProgress = { [weak self] in
            self?.refreshReadiness()
        }
    }

    var frames: [RadarFrame] { timeline?.frames ?? [] }

    var currentFrame: RadarFrame? {
        frames.indices.contains(frameIndex) ? frames[frameIndex] : frames.last
    }

    /// "Now": the newest observed frame. Frames after it are forecasts.
    var latestObservedIndex: Int? { timeline?.latestObservedIndex }

    /// Loads the timeline for the source appropriate to `latitude/longitude`.
    func load(preference: RadarSourcePreference, latitude: Double, longitude: Double, force: Bool = false) async {
        let resolved = RadarService.resolve(preference, latitude: latitude, longitude: longitude)
        if !force, resolved == source, let timeline, Date().timeIntervalSince(timeline.fetchedAt) < 4 * 60 {
            return
        }
        source = resolved
        isLoading = true
        defer { isLoading = false }
        do {
            let newTimeline = try await fetchTimeline(resolved)
            let previousID = currentFrame?.id
            let wasAtNow = timeline == nil || frameIndex == timeline?.latestObservedIndex
            timeline = newTimeline
            errorMessage = nil
            Self.log(newTimeline)
            // Frames keep their ids across refreshes, so a frame you're looking at (or playing
            // through) stays put; otherwise follow "now".
            if isPlaying || !wasAtNow, let previousID, let index = newTimeline.frames.firstIndex(where: { $0.id == previousID }) {
                frameIndex = index
            } else if isPlaying {
                frameIndex = min(frameIndex, max(0, newTimeline.frames.count - 1))
            } else {
                frameIndex = newTimeline.latestObservedIndex ?? max(0, newTimeline.frames.count - 1)
            }
            #if DEBUG
            if Self.debugScreen == "radarForecast" {
                frameIndex = max(0, newTimeline.frames.count - 1)
            }
            #endif
            refreshReadiness()
        } catch {
            errorMessage = "Radar unavailable: \(error.localizedDescription)"
        }
    }

    private func fetchTimeline(_ source: RadarSource) async throws -> RadarTimeline {
        #if DEBUG
        if Self.debugScreen == "radarTiles" {
            return Self.testPatternTimeline
        }
        #endif
        return try await service.timeline(for: source)
    }

    /// Re-fetches new frames every five minutes while the Radar tab is visible.
    func startAutoRefresh(preference: @escaping () -> (RadarSourcePreference, Double, Double)) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, !Task.isCancelled else { return }
                let (pref, lat, lon) = preference()
                await self.load(preference: pref, latitude: lat, longitude: lon, force: true)
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func togglePlayback(speed: Double) {
        isPlaying ? pause() : play(speed: speed)
    }

    func play(speed: Double) {
        guard frames.count > 1 else { return }
        isPlaying = true
        if frameIndex >= frames.count - 1 {
            frameIndex = 0
        }
        playTask?.cancel()
        playTask = Task { [weak self] in
            let frameDuration = 1 / max(0.5, speed)
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(frameDuration * self.dwell(at: self.frameIndex)))
                guard !Task.isCancelled, !self.frames.isEmpty else { return }
                let next = self.frameIndex >= self.frames.count - 1 ? 0 : self.frameIndex + 1
                // Hold the current frame until the next one's tiles are in (up to 3 seconds), so
                // playback never flashes an empty or half-drawn map.
                let frame = self.frames[next]
                if !self.tileStore.isReady(frame) {
                    self.tileStore.prepare(frame)
                    var waited = 0
                    while !Task.isCancelled, !self.tileStore.isReady(frame), waited < 30 {
                        try? await Task.sleep(for: .milliseconds(100))
                        waited += 1
                    }
                }
                guard !Task.isCancelled else { return }
                if self.frames.indices.contains(next) {
                    self.frameIndex = next
                }
            }
        }
    }

    /// How many frame durations to stay on a frame: linger on "now" and on the last frame so both read.
    private func dwell(at index: Int) -> Double {
        if index == frames.count - 1 { return 3 }
        if index == latestObservedIndex, timeline?.hasForecast == true { return 2.5 }
        return 1
    }

    func pause() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    func step(_ delta: Int) {
        pause()
        guard !frames.isEmpty else { return }
        frameIndex = min(max(0, frameIndex + delta), frames.count - 1)
    }

    func showLatest() {
        pause()
        frameIndex = timeline?.latestObservedIndex ?? max(0, frames.count - 1)
    }

    private func refreshReadiness() {
        let ready = tileStore.readyFrameIDs()
        if ready != readyFrameIDs {
            readyFrameIDs = ready
        }
    }

    /// One line per load, for the CI smoke test: which frames the timeline has.
    private static func log(_ timeline: RadarTimeline) {
        let observed = timeline.frames.filter { !$0.isForecast }
        let forecast = timeline.frames.filter(\.isForecast)
        let latest = observed.last.map { $0.time.ISO8601Format() } ?? "none"
        let run = timeline.forecastRunTime.map { $0.ISO8601Format() } ?? "none"
        let source = timeline.source.rawValue
        RadarTileStore.logger.notice("Radar timeline: \(source, privacy: .public) \(observed.count) observed to \(latest, privacy: .public), \(forecast.count) forecast, run \(run, privacy: .public)")
    }

    #if DEBUG
    /// `-AiSkyScreen radarForecast` opens on the last forecast frame; `radarTiles` shows a test
    /// pattern of tile addresses instead of radar (see `RadarTileStore.testPatternImage`).
    static let debugScreen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AiSkyScreen"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }()

    static let testPatternTimeline = RadarTimeline(
        source: .noaa,
        frames: [RadarFrame(id: "test-pattern", time: Date(), tileURLTemplate: "\(RadarTileStore.testPatternScheme)://{z}/{x}/{y}", maxNativeZoom: RadarTiling.maxZoom)],
        fetchedAt: Date()
    )
    #endif
}
