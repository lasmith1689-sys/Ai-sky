import Foundation

/// An XYZ ("slippy map") tile: zoom `z`, column `x` from the antimeridian eastward, row `y` from
/// the north edge southward.
public struct RadarTileKey: Hashable, Sendable, CustomStringConvertible {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    public var description: String { "\(z)/\(x)/\(y)" }

    /// The tile `levels` zoom levels up that contains this one (itself for 0 or less).
    public func ancestor(levels: Int) -> RadarTileKey {
        if levels <= 0 { return self }
        if levels >= z { return RadarTileKey(z: 0, x: 0, y: 0) }
        return RadarTileKey(z: z - levels, x: x >> levels, y: y >> levels)
    }

    /// This tile, or its ancestor at `maxZoom` when it's deeper than a source provides.
    public func clamped(toMaxZoom maxZoom: Int) -> RadarTileKey {
        ancestor(levels: z - maxZoom)
    }
}

/// XYZ tiles in MapKit's map-point space: the world is a 2^28-point square (`MKMapSize.world`)
/// with its origin at the north-west corner and y growing southward, the same layout as XYZ tiles,
/// so tile (z, x, y) covers map points [x, x+1) × [y, y+1) times `tileSize(atZoom: z)`.
public enum RadarTiling {
    /// Width and height of the world in map points (`MKMapSize.world.width`).
    public static let worldSize: Double = 268_435_456
    public static let maxZoom = 22

    /// The zoom level whose 256-point tiles are drawn at about 256 points when the map shows
    /// `zoomScale` screen points per map point (2^28 / 256 = 2^20, so zoom = 20 + log2(zoomScale)).
    public static func zoomLevel(forZoomScale zoomScale: Double) -> Int {
        guard zoomScale > 0, zoomScale.isFinite else { return 0 }
        let level = 20 + log2(zoomScale)
        return min(max(Int(level.rounded()), 0), maxZoom)
    }

    public static func tileSize(atZoom z: Int) -> Double {
        worldSize / Double(1 << max(0, min(z, maxZoom)))
    }

    /// The tile's square in map points.
    public static func rect(for key: RadarTileKey) -> (x: Double, y: Double, size: Double) {
        let size = tileSize(atZoom: key.z)
        return (Double(key.x) * size, Double(key.y) * size, size)
    }

    /// The tiles at zoom `z` that overlap the map-point rectangle [minX, maxX) × [minY, maxY),
    /// row by row from the north-west corner. Parts outside the world are ignored.
    public static func keys(minX: Double, minY: Double, maxX: Double, maxY: Double, zoom z: Int) -> [RadarTileKey] {
        let zoom = max(0, min(z, maxZoom))
        let size = tileSize(atZoom: zoom)
        let last = (1 << zoom) - 1
        guard maxX > minX, maxY > minY else { return [] }
        let x0 = max(0, Int((minX / size).rounded(.down)))
        let y0 = max(0, Int((minY / size).rounded(.down)))
        let x1 = min(last, Int((maxX / size).rounded(.up)) - 1)
        let y1 = min(last, Int((maxY / size).rounded(.up)) - 1)
        guard x0 <= x1, y0 <= y1 else { return [] }
        var keys: [RadarTileKey] = []
        keys.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 {
                keys.append(RadarTileKey(z: zoom, x: x, y: y))
            }
        }
        return keys
    }

    /// The tile containing a coordinate (Web Mercator), for tests and diagnostics.
    public static func key(latitude: Double, longitude: Double, zoom z: Int) -> RadarTileKey {
        let n = Double(1 << z)
        let clampedLatitude = max(min(latitude, 85.05112878), -85.05112878) * .pi / 180
        let x = Int(((longitude + 180) / 360 * n).rounded(.down))
        let y = Int(((1 - log(tan(clampedLatitude) + 1 / cos(clampedLatitude)) / .pi) / 2 * n).rounded(.down))
        return RadarTileKey(z: z, x: min(max(x, 0), Int(n) - 1), y: min(max(y, 0), Int(n) - 1))
    }
}
