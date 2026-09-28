import AiSkyKit
import MapKit
import UIKit

/// Map tile overlay for one radar frame.
///
/// Radar services only provide tiles up to a certain zoom (RainViewer's free tier stops at
/// zoom 7). Beyond that, the parent tile is fetched and the matching quarter/eighth/... is
/// cropped and scaled up, so the radar stays visible when zooming into a neighborhood.
final class RadarTileOverlay: MKTileOverlay {
    let frame: RadarFrame

    private static let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpAdditionalHeaders = ["User-Agent": HTTPClient.defaultUserAgent]
        return URLSession(configuration: configuration)
    }()

    init(frame: RadarFrame) {
        self.frame = frame
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 1
        maximumZ = 19
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let highResolution = path.contentScaleFactor >= 2 && frame.supportsHighResolutionTiles
        let nativeZoom = min(path.z, frame.maxNativeZoom)
        let zoomDelta = path.z - nativeZoom
        let parentX = path.x >> zoomDelta
        let parentY = path.y >> zoomDelta
        guard let url = frame.tileURL(z: nativeZoom, x: parentX, y: parentY, highResolution: highResolution) else {
            result(nil, nil)
            return
        }
        let childX = path.x - (parentX << zoomDelta)
        let childY = path.y - (parentY << zoomDelta)
        let scale = path.contentScaleFactor

        Self.fetch(url) { data in
            guard let data else {
                result(nil, nil)
                return
            }
            if zoomDelta == 0 {
                result(data, nil)
            } else {
                result(Self.crop(data, zoomDelta: zoomDelta, x: childX, y: childY, scale: scale), nil)
            }
        }
    }

    private static func fetch(_ url: URL, completion: @escaping (Data?) -> Void) {
        let key = url.absoluteString as NSString
        if let cached = memoryCache.object(forKey: key) {
            completion(cached as Data)
            return
        }
        session.dataTask(with: url) { data, response, _ in
            guard let data, !data.isEmpty,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(nil)
                return
            }
            memoryCache.setObject(data as NSData, forKey: key, cost: data.count)
            completion(data)
        }
        .resume()
    }

    /// Crops the (x, y) sub-tile out of a parent tile `zoomDelta` levels up and scales it to 256 pt.
    private static func crop(_ data: Data, zoomDelta: Int, x: Int, y: Int, scale: CGFloat) -> Data? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let divisions = CGFloat(1 << zoomDelta)
        let width = CGFloat(image.width) / divisions
        let height = CGFloat(image.height) / divisions
        let rect = CGRect(x: CGFloat(x) * width, y: CGFloat(y) * height, width: width, height: height).integral
        guard let cropped = image.cropping(to: rect) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let size = CGSize(width: 256, height: 256)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.interpolationQuality = .medium
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.pngData()
    }
}
