import AiSkyKit
import BackgroundTasks
import Foundation
import WidgetKit

/// Periodic background work: keeps widget data fresh and sends rain / severe-weather alerts.
///
/// iOS decides when background refresh actually runs (typically every 15–60 minutes for
/// apps you use often), so alerts are best-effort.
enum BackgroundRefresher {
    static var taskIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "AiSky") + ".refresh"
    }

    static func schedule(after interval: TimeInterval = 20 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Unavailable in the Simulator or when Background App Refresh is off.
        }
    }

    static func run() async {
        schedule()
        let store = SharedStore.shared
        let settings = store.loadSettings()
        let repository = WeatherRepository.shared
        let locations = store.loadAllWeatherLocations()

        // Keep the first few locations fresh for widgets.
        for location in locations.prefix(3) {
            _ = try? await repository.snapshot(for: location, settings: settings, maxAge: 15 * 60)
        }
        _ = await repository.summaries(for: locations, settings: settings)

        if settings.rainAlertsEnabled || settings.severeAlertsEnabled {
            await AlertMonitor.check(settings: settings, locations: locations, repository: repository, store: store)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Evaluates watched locations and posts local notifications.
enum AlertMonitor {
    static func check(settings: AppSettings, locations: [WeatherLocation], repository: WeatherRepository, store: SharedStore) async {
        let watched = locations.filter { settings.rainAlertLocationIDs.contains($0.id) }
        guard !watched.isEmpty else { return }
        var lastRain = store.value([String: Date].self, forKey: .lastRainNotification) ?? [:]
        var notifiedAlerts = Set(store.value([String].self, forKey: .notifiedAlertIDs) ?? [])
        let now = Date()

        for location in watched {
            if settings.rainAlertsEnabled,
               let forecast = try? await repository.nextHour(for: location, settings: settings, now: now),
               let notification = AlertPlanner.rainNotification(for: location, forecast: forecast, lastNotified: lastRain[location.id], now: now) {
                await NotificationManager.post(notification)
                lastRain[location.id] = now
            }
            if settings.severeAlertsEnabled,
               let alerts = try? await repository.alerts(for: location, settings: settings, now: now) {
                let planned = AlertPlanner.severeNotifications(for: location, alerts: alerts, alreadyNotified: notifiedAlerts, now: now)
                for notification in planned {
                    await NotificationManager.post(notification)
                }
                notifiedAlerts.formUnion(alerts.map(\.id))
            }
        }
        store.set(lastRain, forKey: .lastRainNotification)
        store.set(Array(notifiedAlerts.suffix(300)), forKey: .notifiedAlertIDs)
    }
}
