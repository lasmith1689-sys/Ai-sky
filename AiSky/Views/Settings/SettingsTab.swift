import AiSkyKit
import SwiftUI
import UIKit
import UserNotifications

struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                unitsSection(model: model)
                dataSection(model: model)
                radarSection(model: model)
                alertsSection(model: model)
                widgetsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                notificationStatus = await NotificationManager.authorizationStatus()
            }
        }
    }

    // MARK: Units

    private func unitsSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Picker("Temperature", selection: $model.settings.units.temperature) {
                ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
            }
            Picker("Wind Speed", selection: $model.settings.units.windSpeed) {
                ForEach(WindSpeedUnit.allCases) { Text($0.symbol).tag($0) }
            }
            Picker("Precipitation", selection: $model.settings.units.precipitation) {
                ForEach(PrecipitationUnit.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Pressure", selection: $model.settings.units.pressure) {
                ForEach(PressureUnit.allCases) { Text($0.symbol).tag($0) }
            }
            Picker("Distance", selection: $model.settings.units.distance) {
                ForEach(DistanceUnit.allCases) { Text($0.symbol).tag($0) }
            }
            Button("Use Regional Defaults") {
                model.settings.units = UnitPreferences.defaults(for: .autoupdatingCurrent)
            }
        } header: {
            Text("Units")
        }
    }

    // MARK: Data

    private func dataSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Picker("Forecast Source", selection: $model.settings.dataSource) {
                ForEach(DataSourcePreference.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Air Quality Index", selection: $model.settings.aqiScale) {
                ForEach(AQIScale.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Weather Data")
        } footer: {
            Text(dataSourceFooter(model: model))
        }
    }

    private func dataSourceFooter(model: AppModel) -> String {
        if let message = model.repository.weatherKitStatusMessage(model.settings) {
            return message
        }
        if model.repository.weatherKitAvailable {
            return "Apple Weather (the technology behind Dark Sky) provides minute-by-minute rain forecasts and government alerts. Open-Meteo supplies air quality and rainfall history."
        }
        return "Forecasts come from Open-Meteo's high-resolution models (15-minute precipitation, feels-like, air quality). To add Apple Weather's minute-by-minute rain forecasts, enable WeatherKit — see the README."
    }

    // MARK: Radar

    private func radarSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Picker("Radar Source", selection: $model.settings.radarSource) {
                ForEach(RadarSourcePreference.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Map Style", selection: $model.settings.radarMapStyle) {
                ForEach(MapStylePreference.allCases) { Text($0.displayName).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("Opacity: \(Int(model.settings.radarOpacity * 100))%")
                Slider(value: $model.settings.radarOpacity, in: 0.3...1.0)
            }
            VStack(alignment: .leading) {
                Text("Animation Speed: \(String(format: "%.1f", model.settings.radarSpeed)) frames/sec")
                Slider(value: $model.settings.radarSpeed, in: 1...6, step: 0.5)
            }
        } header: {
            Text("Radar")
        } footer: {
            Text("Automatic uses high-resolution NOAA NEXRAD radar in the U.S. and RainViewer's global composite elsewhere.")
        }
    }

    // MARK: Alerts

    private func alertsSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Toggle("Rain Starting Soon", isOn: Binding(
                get: { model.settings.rainAlertsEnabled },
                set: { enabled in
                    model.settings.rainAlertsEnabled = enabled
                    if enabled { requestNotifications() }
                }
            ))
            Toggle("Severe Weather Alerts", isOn: Binding(
                get: { model.settings.severeAlertsEnabled },
                set: { enabled in
                    model.settings.severeAlertsEnabled = enabled
                    if enabled { requestNotifications() }
                }
            ))
            if model.settings.rainAlertsEnabled || model.settings.severeAlertsEnabled {
                NavigationLink {
                    AlertLocationsView()
                } label: {
                    LabeledContent("Watched Places", value: "\(model.settings.rainAlertLocationIDs.count)")
                }
            }
            if notificationStatus == .denied {
                Button("Notifications are off — open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Ai Sky checks watched places in the background and notifies you when precipitation is about to start or a government alert is issued. iOS decides how often background checks run, so alerts are best-effort — keep Background App Refresh on.")
        }
    }

    private func requestNotifications() {
        Task {
            await NotificationManager.requestAuthorization()
            notificationStatus = await NotificationManager.authorizationStatus()
            BackgroundRefresher.schedule(after: 5 * 60)
        }
    }

    // MARK: Widgets & about

    private var widgetsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Home Screen", systemImage: "apps.iphone")
                    .font(.headline)
                Text("Touch and hold an empty area of your Home Screen, tap Edit → Add Widget, and choose Ai Sky. Pick Conditions, Next Hour, Air Quality, Precipitation or Locations. Touch and hold a widget → Edit Widget to choose which saved place it shows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label("Lock Screen", systemImage: "lock.iphone")
                    .font(.headline)
                    .padding(.top, 4)
                Text("Touch and hold your Lock Screen, tap Customize → Lock Screen, then tap the widget area to add Ai Sky temperature, rain or AQI widgets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Widgets")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            Link("Weather data by Open-Meteo.com (CC BY 4.0)", destination: URL(string: "https://open-meteo.com/")!)
            Link("Alerts: U.S. National Weather Service", destination: URL(string: "https://www.weather.gov/")!)
            Link("Radar: NOAA NEXRAD via Iowa Environmental Mesonet", destination: URL(string: "https://mesonet.agron.iastate.edu/")!)
            Link("Radar: RainViewer", destination: URL(string: "https://www.rainviewer.com/")!)
            if model.repository.weatherKitAvailable {
                Link("Apple Weather data sources", destination: URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!)
            }
        } header: {
            Text("About")
        }
    }
}

/// Choose which places are watched for rain / severe-weather notifications.
private struct AlertLocationsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.forecastLocations) { location in
                let watched = model.settings.rainAlertLocationIDs.contains(location.id)
                Button {
                    if watched {
                        model.settings.rainAlertLocationIDs.removeAll { $0 == location.id }
                    } else {
                        model.settings.rainAlertLocationIDs.append(location.id)
                    }
                } label: {
                    HStack {
                        if location.isCurrentLocation {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                        }
                        Text(location.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if watched {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Watched Places")
    }
}
