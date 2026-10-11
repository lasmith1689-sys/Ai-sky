import AiSkyKit
import CoreGraphics
import Foundation
import ImageIO
import os
import UIKit

/// Downloads, decodes and caches the radar tiles of every frame, so stepping or playing through
/// frames only redraws decoded images from memory instead of starting new downloads.
///
/// - The tiles MapKit draws for the current frame are fetched first (`.visible`).
/// - Once the map settles, the same tiles are prefetched for every other frame, starting from the
///   current one in playback order (`.prefetch`); prefetches for tiles that left the screen are cancelled.
/// - A frame is "ready" when every on-screen tile is cached (or failed), which playback waits for.
///
/// Thread-safe: MapKit draws overlays on background threads.
final class RadarTileStore: @unchecked Sendable {
    enum Priority {
        case visible
        case prefetch
    }

    /// Called on the main queue when a tile finished loading. Set it from the main queue.
    var onTileLoaded: (@MainActor (_ frameID: String, _ key: RadarTileKey) -> Void)?
    /// Called on the main queue (coalesced) when frames may have become ready. Set it from the main queue.
    var onProgress: (@MainActor () -> Void)?

    static let logger = Logger(subsystem: "com.lasmith1689.AiSky", category: "Radar")

    private final class TileImage {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private struct Request {
        let id: Int
        let task: URLSessionDataTask
        var priority: Priority
    }

    private struct Counts {
        var loaded = 0
        var failed = 0
    }

    /// Decoded tiles. 256 × 256 × 4 bytes each, so about 500 tiles: every frame of a full screen.
    private let images: NSCache<NSString, TileImage> = {
        let cache = NSCache<NSString, TileImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    private let lock = NSLock()
    private var inFlight: [String: Request] = [:]
    /// Failed tiles count as done (so playback doesn't wait on them) until `retryAfter`.
    private var failures: [String: Date] = [:]
    /// Tiles MapKit has asked the renderer to draw, with when (uptime), and when each zoom was last drawn.
    private var drawn: [RadarTileKey: TimeInterval] = [:]
    private var drawnZoomTime: [Int: TimeInterval] = [:]
    private var visibleRect: (minX: Double, minY: Double, maxX: Double, maxY: Double)?
    private var frames: [RadarFrame] = []
    private var currentIndex = 0
    private var counts: [String: Counts] = [:]
    private var nextRequestID = 0

    // Main queue only.
    private var prefetchScheduled = false
    private var progressScheduled = false

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RadarTiles", isDirectory: true)
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, directory: directory)
        // Every tile URL names its imagery's time, so a cached copy is never out of date.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpAdditionalHeaders = ["User-Agent": HTTPClient.defaultUserAgent]
        return URLSession(configuration: configuration)
    }()

    private static let decodeQueue = DispatchQueue(label: "AiSky.RadarTileStore.decode", qos: .userInitiated, attributes: .concurrent)

    // MARK: Reading (any thread)

    func image(frame: RadarFrame, key: RadarTileKey) -> CGImage? {
        images.object(forKey: Self.cacheKey(frame.id, key) as NSString)?.image
    }

    /// The tile itself or, while it loads, the nearest cached ancestor (drawn enlarged).
    func bestImage(frame: RadarFrame, key: RadarTileKey) -> (image: CGImage, key: RadarTileKey)? {
        for levels in 0...3 where levels <= key.z {
            let candidate = key.ancestor(levels: levels)
            if let cached = self.image(frame: frame, key: candidate) {
                return (cached, candidate)
            }
        }
        return nil
    }

    /// Whether every tile on screen is loaded (or failed) for `frame`.
    func isReady(_ frame: RadarFrame) -> Bool {
        let (keys, failed) = lock.withLock { (activeKeysLocked(for: frame), failures) }
        return keys.allSatisfy { key in
            let cacheKey = Self.cacheKey(frame.id, key)
            return failed[cacheKey] != nil || images.object(forKey: cacheKey as NSString) != nil
        }
    }

    func readyFrameIDs() -> Set<String> {
        let frames = lock.withLock { self.frames }
        return Set(frames.filter(isReady).map(\.id))
    }

    // MARK: Updates

    /// Called by the renderer with the tiles (at the drawn zoom) of each rectangle MapKit draws.
    func noteDrawn(_ keys: [RadarTileKey]) {
        guard let zoom = keys.first?.z else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let isNew: Bool = lock.withLock {
            var isNew = false
            for key in keys {
                if drawn.updateValue(now, forKey: key) == nil {
                    isNew = true
                }
            }
            drawnZoomTime[zoom] = now
            if drawn.count > 600 {
                drawn = drawn.filter { now - $0.value < 120 }
            }
            return isNew
        }
        if isNew {
            schedulePrefetch()
        }
    }

    func setVisibleRect(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        lock.withLock { visibleRect = (minX, minY, maxX, maxY) }
        schedulePrefetch()
        scheduleProgress()
    }

    func setFrames(_ frames: [RadarFrame], currentIndex: Int) {
        let changed: Bool = lock.withLock {
            let changed = self.frames != frames
            self.frames = frames
            self.currentIndex = currentIndex
            return changed
        }
        if changed {
            schedulePrefetch()
            scheduleProgress()
        }
    }

    /// Requests a frame's on-screen tiles ahead of the prefetch queue (playback is about to show it).
    func prepare(_ frame: RadarFrame) {
        let keys = lock.withLock { activeKeysLocked(for: frame) }
        for key in keys {
            load(frame, key, priority: .visible)
        }
    }

    // MARK: Loading

    func load(_ frame: RadarFrame, _ key: RadarTileKey, priority: Priority) {
        let cacheKey = Self.cacheKey(frame.id, key)
        if images.object(forKey: cacheKey as NSString) != nil { return }
        guard let url = frame.tileURL(for: key) else { return }

        #if DEBUG
        if url.scheme == Self.testPatternScheme {
            if let image = Self.testPatternImage(for: key) {
                store(image, cacheKey: cacheKey)
            }
            notifyLoaded(frameID: frame.id, key: key)
            return
        }
        #endif

        let task: URLSessionDataTask? = lock.withLock {
            if var existing = inFlight[cacheKey] {
                if priority == .visible, existing.priority == .prefetch {
                    existing.task.priority = URLSessionTask.highPriority
                    existing.priority = .visible
                    inFlight[cacheKey] = existing
                }
                return nil
            }
            if let retryAfter = failures[cacheKey], retryAfter > Date() {
                return nil
            }
            let frameID = frame.id
            nextRequestID += 1
            let requestID = nextRequestID
            let task = Self.session.dataTask(with: url) { [weak self] data, response, error in
                self?.finish(requestID: requestID, cacheKey: cacheKey, frameID: frameID, key: key, url: url, data: data, response: response, error: error)
            }
            task.priority = priority == .visible ? URLSessionTask.highPriority : URLSessionTask.lowPriority
            inFlight[cacheKey] = Request(id: requestID, task: task, priority: priority)
            return task
        }
        task?.resume()
    }

    private func finish(requestID: Int, cacheKey: String, frameID: String, key: RadarTileKey, url: URL, data: Data?, response: URLResponse?, error: Error?) {
        if (error as? URLError)?.code == .cancelled {
            lock.withLock { removeRequestLocked(requestID, cacheKey: cacheKey) }
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        Self.decodeQueue.async { [weak self] in
            guard let self else { return }
            let image = status == 200 ? data.flatMap(Self.decode) : nil
            let kind = Self.kind(of: url)
            // Cache before clearing the request, so a draw in between doesn't start a second download.
            if let image {
                self.store(image, cacheKey: cacheKey)
            }
            let isIdle: Bool = self.lock.withLock {
                self.removeRequestLocked(requestID, cacheKey: cacheKey)
                if image != nil {
                    self.failures.removeValue(forKey: cacheKey)
                    self.counts[kind, default: Counts()].loaded += 1
                } else {
                    // RainViewer's free tier allows 100 requests a minute per IP; back off longer on 429.
                    self.failures[cacheKey] = Date().addingTimeInterval(status == 429 ? 60 : 30)
                    self.counts[kind, default: Counts()].failed += 1
                }
                return self.inFlight.isEmpty
            }
            if image == nil {
                let reason = status.map { "HTTP \($0)" } ?? (error?.localizedDescription ?? "no data")
                Self.logger.error("Radar tile failed: \(reason, privacy: .public) \(url.absoluteString, privacy: .public)")
            }
            if isIdle {
                self.logSummary()
            }
            self.notifyLoaded(frameID: frameID, key: key)
        }
    }

    /// Removes the request only if it's still the one in flight for this tile (a cancelled prefetch
    /// can finish after a new request for the same tile started).
    private func removeRequestLocked(_ requestID: Int, cacheKey: String) {
        if inFlight[cacheKey]?.id == requestID {
            inFlight.removeValue(forKey: cacheKey)
        }
    }

    private func store(_ image: CGImage, cacheKey: String) {
        images.setObject(TileImage(image), forKey: cacheKey as NSString, cost: image.bytesPerRow * image.height)
    }

    private func notifyLoaded(frameID: String, key: RadarTileKey) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onTileLoaded?(frameID, key)
                self.scheduleProgress()
            }
        }
    }

    // MARK: Prefetching

    private func schedulePrefetch() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.prefetchScheduled else { return }
                self.prefetchScheduled = true
                // Let a pan or zoom settle so tiles that only flashed by aren't fetched for every frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.prefetchScheduled = false
                        self.prefetch()
                    }
                }
            }
        }
    }

    @MainActor
    private func prefetch() {
        let (frames, start) = lock.withLock { (self.frames, self.currentIndex) }
        guard !frames.isEmpty else { return }
        let first = min(max(0, start), frames.count - 1)
        let ordered = frames[first...] + frames[..<first]
        var wanted = Set<String>()
        for frame in ordered {
            let keys = lock.withLock { activeKeysLocked(for: frame) }
            for key in keys {
                wanted.insert(Self.cacheKey(frame.id, key))
                load(frame, key, priority: .prefetch)
            }
        }
        // Tiles that left the screen, or frames that left the timeline, aren't worth finishing.
        let stale: [URLSessionDataTask] = lock.withLock {
            let keys = inFlight.filter { $0.value.priority == .prefetch && !wanted.contains($0.key) }.map(\.key)
            return keys.compactMap { inFlight.removeValue(forKey: $0)?.task }
        }
        stale.forEach { $0.cancel() }
    }

    private func scheduleProgress() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.progressScheduled else { return }
                self.progressScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.progressScheduled = false
                        self.onProgress?()
                    }
                }
            }
        }
    }

    /// The on-screen tiles for `frame`: the most recently drawn zoom's tiles that overlap the
    /// visible map, mapped to the frame's native zoom.
    private func activeKeysLocked(for frame: RadarFrame) -> [RadarTileKey] {
        guard let zoom = drawnZoomTime.max(by: { $0.value < $1.value })?.key else { return [] }
        var seen = Set<RadarTileKey>()
        var keys: [RadarTileKey] = []
        for key in drawn.keys where key.z == zoom && isVisibleLocked(key) {
            let native = key.clamped(toMaxZoom: frame.maxNativeZoom)
            if seen.insert(native).inserted {
                keys.append(native)
            }
        }
        return keys
    }

    private func isVisibleLocked(_ key: RadarTileKey) -> Bool {
        guard let visibleRect else { return true }
        let tile = RadarTiling.rect(for: key)
        return tile.x < visibleRect.maxX && tile.x + tile.size > visibleRect.minX
            && tile.y < visibleRect.maxY && tile.y + tile.size > visibleRect.minY
    }

    // MARK: Helpers

    private static func cacheKey(_ frameID: String, _ key: RadarTileKey) -> String {
        "\(frameID)|\(key.z)/\(key.x)/\(key.y)"
    }

    /// Decodes now, on the calling (background) queue, so drawing never decodes.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    private static func kind(of url: URL) -> String {
        let text = url.absoluteString
        if text.contains("ridge::") { return "noaa" }
        if text.contains("hrrr::") { return "hrrr" }
        if text.contains("rainviewer") { return "rainviewer" }
        return url.host ?? "other"
    }

    /// One line per burst of loading, for the CI smoke test: `Radar tiles: hrrr 64 loaded 0 failed, noaa 88 loaded 0 failed`.
    private func logSummary() {
        let counts = lock.withLock { self.counts }
        let text = counts.keys.sorted().map { "\($0) \(counts[$0]!.loaded) loaded \(counts[$0]!.failed) failed" }.joined(separator: ", ")
        Self.logger.notice("Radar tiles: \(text, privacy: .public)")
    }

    // MARK: Debug test pattern

    #if DEBUG
    /// `aisky-test://{z}/{x}/{y}` frames draw each tile's address, so the smoke test can read the
    /// tile grid off a screenshot and check it's upright and in the right place.
    static let testPatternScheme = "aisky-test"

    static func testPatternImage(for key: RadarTileKey) -> CGImage? {
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.withAlphaComponent(0.25).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            let text = "z\(key.z) x\(key.x) y\(key.y)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.white,
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
        return image.cgImage
    }
    #endif
}
