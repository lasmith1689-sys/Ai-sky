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

    private let service = RadarService()
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var frames: [RadarFrame] { timeline?.frames ?? [] }

    var currentFrame: RadarFrame? {
        frames.indices.contains(frameIndex) ? frames[frameIndex] : frames.last
    }

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
            let newTimeline = try await service.timeline(for: resolved)
            let wasAtLatest = timeline == nil || frameIndex >= frames.count - 1
            timeline = newTimeline
            errorMessage = nil
            if wasAtLatest || !isPlaying {
                frameIndex = newTimeline.latestObservedIndex ?? max(0, newTimeline.frames.count - 1)
            }
        } catch {
            errorMessage = "Radar unavailable: \(error.localizedDescription)"
        }
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
                let atEnd = self.frameIndex >= self.frames.count - 1
                // Linger on the newest frame so the current state is readable.
                try? await Task.sleep(for: .seconds(atEnd ? frameDuration * 3 : frameDuration))
                guard !Task.isCancelled else { return }
                self.frameIndex = atEnd ? 0 : self.frameIndex + 1
            }
        }
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
}
