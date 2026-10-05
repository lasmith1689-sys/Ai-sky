import AiSkyKit
import SwiftUI
import UIKit
import UserNotifications

struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                lookSection
                unitsSection(model: model)
                dataSection(model: model)
                radarSection(model: model)
                alertsSection(model: model)
                widgetsSection
                aboutSection
            }
            .font(t.look == .liquid ? .body : t.font(.text, 16))
            .foregroundStyle(t.ink)
            .lookList(t)
            .overlay(alignment: .top) {
                if t.look != .liquid { StatusBarScrim() }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(t.look == .liquid ? .large : .inline)
            .toolbar(t.look == .liquid ? .automatic : .hidden, for: .navigationBar)
            .task {
                notificationStatus = await NotificationManager.authorizationStatus()
            }
        }
    }

    // MARK: Look

    private var lookSection: some View {
        Section {
            LookPicker()
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .lookRow(t)
        } header: {
            VStack(alignment: .leading, spacing: 18) {
                if t.look != .liquid {
                    LookScreenTitle(title: "Settings")
                        .padding(.top, 8)
                }
                SettingsHeader(title: "Look")
            }
            .textCase(nil)
        } footer: {
            SettingsFooter(text: "Every look shows the same forecast. Widgets follow the look you pick.")
        }
    }

    // MARK: Units

    private func unitsSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Picker("Temperature", selection: $model.settings.units.temperature) {
                ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
            }
            .lookRow(t)
            Picker("Wind Speed", selection: $model.settings.units.windSpeed) {
                ForEach(WindSpeedUnit.allCases) { Text($0.symbol).tag($0) }
            }
            .lookRow(t)
            Picker("Precipitation", selection: $model.settings.units.precipitation) {
                ForEach(PrecipitationUnit.allCases) { Text($0.displayName).tag($0) }
            }
            .lookRow(t)
            Picker("Pressure", selection: $model.settings.units.pressure) {
                ForEach(PressureUnit.allCases) { Text($0.symbol).tag($0) }
            }
            .lookRow(t)
            Picker("Distance", selection: $model.settings.units.distance) {
                ForEach(DistanceUnit.allCases) { Text($0.symbol).tag($0) }
            }
            .lookRow(t)
            Button("Use Regional Defaults") {
                model.settings.units = UnitPreferences.defaults(for: .autoupdatingCurrent)
            }
            .foregroundStyle(t.accent)
            .lookRow(t)
        } header: {
            SettingsHeader(title: "Units")
        }
    }

    // MARK: Data

    private func dataSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Picker("Forecast Source", selection: $model.settings.dataSource) {
                ForEach(DataSourcePreference.allCases) { Text($0.displayName).tag($0) }
            }
            .lookRow(t)
            Picker("Air Quality Index", selection: $model.settings.aqiScale) {
                ForEach(AQIScale.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .lookRow(t)
        } header: {
            SettingsHeader(title: "Weather Data")
        } footer: {
            SettingsFooter(text: dataSourceFooter(model: model))
        }
    }

    private func dataSourceFooter(model: AppModel) -> String {
        if let message = model.repository.weatherKitStatusMessage(model.settings) {
            return message
        }
        if model.repository.weatherKitAvailable {
            return "Apple Weather (the technology behind Dark Sky) provides minute-by-minute rain forecasts and government alerts. Open-Meteo supplies air quality and rainfall history."
        }
        return "Forecasts come from Open-Meteo's high-resolution models (15-minute precipitation, feels-like, air quality). To add Apple Weather's minute-by-minute rain forecasts, enable WeatherKit (see the README)."
    }

    // MARK: Radar

    private func radarSection(model: AppModel) -> some View {
        @Bindable var model = model
        return Section {
            Picker("Radar Source", selection: $model.settings.radarSource) {
                ForEach(RadarSourcePreference.allCases) { Text($0.displayName).tag($0) }
            }
            .lookRow(t)
            Picker("Map Style", selection: $model.settings.radarMapStyle) {
                ForEach(MapStylePreference.allCases) { Text($0.displayName).tag($0) }
            }
            .lookRow(t)
            VStack(alignment: .leading) {
                Text("Opacity: \(Int(model.settings.radarOpacity * 100))%")
                Slider(value: $model.settings.radarOpacity, in: 0.3...1.0)
                    .tint(t.controlTint ?? Palette.color(hex: 0x0A84FF))
            }
            .lookRow(t)
            VStack(alignment: .leading) {
                Text("Animation Speed: \(String(format: "%.1f", model.settings.radarSpeed)) frames/sec")
                Slider(value: $model.settings.radarSpeed, in: 1...6, step: 0.5)
                    .tint(t.controlTint ?? Palette.color(hex: 0x0A84FF))
            }
            .lookRow(t)
        } header: {
            SettingsHeader(title: "Radar")
        } footer: {
            SettingsFooter(text: "Automatic uses high-resolution NOAA NEXRAD radar in the U.S. and RainViewer's global composite elsewhere.")
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
            .tint(t.controlTint ?? .green)
            .lookRow(t)
            Toggle("Severe Weather Alerts", isOn: Binding(
                get: { model.settings.severeAlertsEnabled },
                set: { enabled in
                    model.settings.severeAlertsEnabled = enabled
                    if enabled { requestNotifications() }
                }
            ))
            .tint(t.controlTint ?? .green)
            .lookRow(t)
            if model.settings.rainAlertsEnabled || model.settings.severeAlertsEnabled {
                NavigationLink {
                    AlertLocationsView()
                } label: {
                    LabeledContent("Watched Places", value: "\(model.settings.rainAlertLocationIDs.count)")
                }
                .lookRow(t)
            }
            if notificationStatus == .denied {
                Button("Notifications are off. Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(t.accent)
                .lookRow(t)
            }
        } header: {
            SettingsHeader(title: "Notifications")
        } footer: {
            SettingsFooter(text: "Ai Sky checks watched places in the background and notifies you when precipitation is about to start or a government alert is issued. iOS decides how often background checks run, so alerts are best-effort. Keep Background App Refresh on.")
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
                    .font(t.look == .liquid ? .headline : t.font(.textStrong, 16))
                Text("Touch and hold an empty area of your Home Screen, tap Edit, then Add Widget, and choose Ai Sky. Pick Conditions, Next Hour, Air Quality, Precipitation or Locations. Touch and hold a widget, then Edit Widget, to choose which saved place it shows.")
                    .font(t.look == .liquid ? .callout : t.font(.text, 14))
                    .foregroundStyle(t.ink2)
                Label("Lock Screen", systemImage: "lock.iphone")
                    .font(t.look == .liquid ? .headline : t.font(.textStrong, 16))
                    .padding(.top, 4)
                Text("Touch and hold your Lock Screen, tap Customize, then Lock Screen, then tap the widget area to add Ai Sky temperature, rain or AQI widgets.")
                    .font(t.look == .liquid ? .callout : t.font(.text, 14))
                    .foregroundStyle(t.ink2)
            }
            .padding(.vertical, 4)
            .lookRow(t)
        } header: {
            SettingsHeader(title: "Widgets")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                .lookRow(t)
            Group {
                Link("Weather data by Open-Meteo.com (CC BY 4.0)", destination: URL(string: "https://open-meteo.com/")!)
                Link("Alerts: U.S. National Weather Service", destination: URL(string: "https://www.weather.gov/")!)
                Link("Radar: NOAA NEXRAD via Iowa Environmental Mesonet", destination: URL(string: "https://mesonet.agron.iastate.edu/")!)
                Link("Radar: RainViewer", destination: URL(string: "https://www.rainviewer.com/")!)
                if model.repository.weatherKitAvailable {
                    Link("Apple Weather data sources", destination: URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!)
                }
            }
            .foregroundStyle(t.accent)
            .lookRow(t)
            NavigationLink {
                FontLicensesView()
            } label: {
                Text("Typefaces and Licenses")
            }
            .lookRow(t)
        } header: {
            SettingsHeader(title: "About")
        }
    }
}

/// Section title in the look's label style.
struct SettingsHeader: View {
    @Environment(\.lookTokens) private var t
    let title: String

    var body: some View {
        if t.look == .liquid {
            Text(title)
        } else {
            Text(title)
                .lookLabel(t, color: t.ink2)
        }
    }
}

struct SettingsFooter: View {
    @Environment(\.lookTokens) private var t
    let text: String

    var body: some View {
        Text(text)
            .font(t.look == .liquid ? .footnote : t.font(.text, 12))
            .foregroundStyle(t.ink2)
    }
}

/// Choose which places are watched for rain / severe-weather notifications.
private struct AlertLocationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t

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
                                .foregroundStyle(t.accent)
                        }
                        Text(location.name)
                            .foregroundStyle(t.ink)
                        Spacer()
                        if watched {
                            Image(systemName: "checkmark")
                                .foregroundStyle(t.accent)
                        }
                    }
                }
                .lookRow(t)
                .accessibilityAddTraits(watched ? .isSelected : [])
            }
        }
        .font(t.look == .liquid ? .body : t.font(.text, 16))
        .lookList(t)
        .lookNavigationTitle("Watched Places")
    }
}

/// The bundled typefaces and their SIL Open Font License texts.
private struct FontLicensesView: View {
    @Environment(\.lookTokens) private var t

    private let families: [(name: String, file: String, looks: String)] = [
        ("Barlow and Barlow Condensed", "Barlow-OFL", "Instrument"),
        ("Geist and Geist Mono", "Geist-OFL", "Obsidian"),
        ("Newsreader", "Newsreader-OFL", "Editorial"),
        ("Instrument Sans", "InstrumentSans-OFL", "Editorial"),
        ("Manrope", "Manrope-OFL", "Horizon"),
        ("Bricolage Grotesque", "BricolageGrotesque-OFL", "Chroma '74"),
        ("DM Mono", "DMMono-OFL", "Chroma '74"),
    ]

    var body: some View {
        List {
            Section {
                Text("Liquid uses the system font, SF Pro. The other looks bundle these typefaces under the SIL Open Font License 1.1.")
                    .font(t.look == .liquid ? .footnote : t.font(.text, 13))
                    .foregroundStyle(t.ink2)
                    .lookRow(t)
            }
            ForEach(families, id: \.name) { family in
                NavigationLink {
                    ScrollView {
                        Text(licenseText(family.file))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(t.ink)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .lookScreen(t)
                    .lookNavigationTitle(family.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.name)
                        Text(family.looks)
                            .font(t.look == .liquid ? .caption : t.font(.text, 12))
                            .foregroundStyle(t.ink2)
                    }
                }
                .lookRow(t)
            }
        }
        .font(t.look == .liquid ? .body : t.font(.text, 16))
        .lookList(t)
        .lookNavigationTitle("Typefaces")
    }

    private func licenseText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "SIL Open Font License 1.1"
        }
        return text
    }
}
