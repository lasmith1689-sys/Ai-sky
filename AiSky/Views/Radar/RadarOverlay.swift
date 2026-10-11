import AiSkyKit
import MapKit
import UIKit

/// The radar layer: one world-sized overlay whose renderer draws whichever frame is current.
///
/// Every frame used to be its own `MKTileOverlay`, all loaded at once with the hidden ones at zero
/// alpha, so each pan or zoom started a download and decode for every tile of every frame. Now one
/// renderer draws decoded tiles from `RadarTileStore`; changing frames is a redraw from memory.
final class RadarOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
}

final class RadarOverlayRenderer: MKOverlayRenderer {
    private let store: RadarTileStore
    private let lock = NSLock()
    private var frame: RadarFrame?

    init(overlay: RadarOverlay, store: RadarTileStore) {
        self.store = store
        super.init(overlay: overlay)
    }

    var currentFrameID: String? {
        lock.withLock { frame?.id }
    }

    /// Switches frames; tiles already in memory draw immediately.
    func show(_ newFrame: RadarFrame?) {
        let changed: Bool = lock.withLock {
            guard frame != newFrame else { return false }
            frame = newFrame
            return true
        }
        if changed {
            setNeedsDisplay()
        }
    }

    /// Redraws the tile's area when a tile of the current frame arrives.
    func tileDidLoad(frameID: String, key: RadarTileKey) {
        guard frameID == currentFrameID else { return }
        setNeedsDisplay(Self.mapRect(for: key))
    }

    static func mapRect(for key: RadarTileKey) -> MKMapRect {
        let tile = RadarTiling.rect(for: key)
        return MKMapRect(x: tile.x, y: tile.y, width: tile.size, height: tile.size)
    }

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        // Draw whatever is cached (or an enlarged ancestor) right away; missing tiles redraw as they arrive.
        true
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let frame = lock.withLock({ self.frame }) else { return }
        let zoom = RadarTiling.zoomLevel(forZoomScale: Double(zoomScale))
        let keys = RadarTiling.keys(minX: mapRect.minX, minY: mapRect.minY, maxX: mapRect.maxX, maxY: mapRect.maxY, zoom: zoom)
        guard !keys.isEmpty else { return }
        store.noteDrawn(keys)

        // Deeper than the source goes, one native tile covers several drawn ones: draw it enlarged.
        var seen = Set<RadarTileKey>()
        let nativeKeys = keys.map { $0.clamped(toMaxZoom: frame.maxNativeZoom) }.filter { seen.insert($0).inserted }

        context.saveGState()
        context.clip(to: rect(for: mapRect))
        context.interpolationQuality = .medium
        // UIKit drawing handles the map context's top-down orientation (a bare CGContext.draw would
        // put the image upside down).
        UIGraphicsPushContext(context)
        for key in nativeKeys {
            if let best = store.bestImage(frame: frame, key: key) {
                context.saveGState()
                // An ancestor stands in only for this tile's square, not its loaded neighbors'.
                context.clip(to: rect(for: Self.mapRect(for: key)))
                UIImage(cgImage: best.image).draw(in: rect(for: Self.mapRect(for: best.key)))
                context.restoreGState()
            }
            if store.image(frame: frame, key: key) == nil {
                store.load(frame, key, priority: .visible)
            }
        }
        UIGraphicsPopContext()
        context.restoreGState()
    }
}
