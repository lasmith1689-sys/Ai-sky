import Foundation

/// A local notification the background refresher should post.
public struct PlannedNotification: Sendable, Equatable {
    public var id: String
    public var title: String
    public var body: String
    public var threadID: String

    public init(id: String, title: String, body: String, threadID: String) {
        self.id = id
        self.title = title
        self.body = body
        self.threadID = threadID
    }
}

/// Decides when to send "rain starting soon" and severe-weather notifications
/// (the Dark Sky "down to the minute" alerts), without spamming.
public enum AlertPlanner {
    /// Only warn when precipitation starts within this many seconds.
    public static let rainLeadTime: TimeInterval = 30 * 60
    /// Don't repeat a rain alert for the same place within this window.
    public static let rainCooldown: TimeInterval = 2 * 3600

    public static func rainNotification(
        for location: WeatherLocation,
        forecast: NextHourForecast?,
        lastNotified: Date?,
        now: Date = Date()
    ) -> PlannedNotification? {
        let summary = NextHourSummarizer.summarize(forecast, now: now, preferProviderText: false)
        guard summary.state == .starting,
              !summary.isPossibleOnly,
              let startsIn = summary.startsIn,
              startsIn <= rainLeadTime else {
            return nil
        }
        if let lastNotified, now.timeIntervalSince(lastNotified) < rainCooldown {
            return nil
        }
        let noun = summary.precipitationKind == .none ? "Rain" : summary.precipitationKind.noun.capitalizedFirst
        return PlannedNotification(
            id: "rain-\(location.id)-\(Int(now.timeIntervalSince1970))",
            title: "\(noun) soon · \(location.name)",
            body: summary.text,
            threadID: "rain-\(location.id)"
        )
    }

    /// New alerts (not previously notified) at or above `minimumSeverity`.
    public static func severeNotifications(
        for location: WeatherLocation,
        alerts: [WeatherAlertInfo],
        alreadyNotified: Set<String>,
        minimumSeverity: AlertSeverity = .moderate,
        now: Date = Date()
    ) -> [PlannedNotification] {
        alerts
            .filter { $0.isActive(at: now) && $0.severity >= minimumSeverity && !alreadyNotified.contains($0.id) }
            .map { alert in
                PlannedNotification(
                    id: "alert-\(alert.id)",
                    title: "\(alert.title) · \(location.name)",
                    body: alert.headline ?? alert.region ?? "Tap for details from \(alert.source).",
                    threadID: "alerts-\(location.id)"
                )
            }
    }
}
