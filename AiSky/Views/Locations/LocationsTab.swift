import AiSkyKit
import SwiftUI
import UIKit

/// The location library: device location plus up to 20 saved places.
struct LocationsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    @State private var renaming: SavedLocation?
    @State private var renameText = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                currentLocationSection
                savedSection
            }
            .font(t.look == .liquid ? .body : t.font(.text, 16))
            .lookList(t)
            .overlay(alignment: .top) {
                if t.look != .liquid { StatusBarScrim() }
            }
            .navigationTitle(t.look == .liquid ? "Places" : "")
            .navigationBarTitleDisplayMode(t.look == .liquid ? .large : .inline)
            .toolbarBackground(t.look == .liquid ? Color.clear : t.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(model.savedLocations.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.isAddingLocation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!model.canAddLocation)
                    .accessibilityLabel("Add location")
                }
            }
            .refreshable {
                await model.refreshLibrarySummaries(force: true)
            }
            .task {
                await model.refreshLibrarySummaries()
            }
            .sheet(isPresented: $model.isAddingLocation) {
                AddLocationView()
            }
            .alert("Rename Location", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let renaming {
                        model.renameLocation(id: renaming.id, to: renameText)
                    }
                    renaming = nil
                }
                Button("Reset", role: .destructive) {
                    if let renaming {
                        model.renameLocation(id: renaming.id, to: nil)
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Give this place a nickname like “Home” or “Cabin”.")
            }
        }
    }

    @ViewBuilder
    private var currentLocationSection: some View {
        Section {
            if model.showsCurrentLocation, let current = model.currentLocation {
                let location = WeatherLocation.current(current)
                Button {
                    model.select(locationID: location.id)
                } label: {
                    LocationRow(location: location, summary: model.weather.summary(for: location.id), formatter: model.formatter)
                }
                .buttonStyle(.plain)
                .lookRow(t)
            } else if model.locationManager.isDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Location access is off. Open Settings", systemImage: "location.slash")
                }
                .lookRow(t)
            } else {
                Button {
                    if model.locationManager.canRequestAuthorization {
                        model.locationManager.requestAuthorization()
                    } else {
                        Task { await model.locationManager.refresh() }
                    }
                } label: {
                    Label(model.locationManager.isUpdating ? "Finding your location…" : "Use My Location", systemImage: "location.fill")
                }
                .lookRow(t)
            }
        } header: {
            VStack(alignment: .leading, spacing: 18) {
                if t.look != .liquid {
                    LookScreenTitle(title: "Places")
                }
                SettingsHeader(title: "My Location")
            }
            .textCase(nil)
        }
    }

    private var savedSection: some View {
        Section {
            if model.savedLocations.isEmpty {
                Text("Save up to \(LocationLibrary.maximumLocations) places (home, work, the cabin) and swipe between them in the Forecast tab or pin them to widgets.")
                    .font(t.look == .liquid ? .callout : t.font(.text, 15))
                    .foregroundStyle(t.ink2)
                    .padding(.vertical, 6)
                    .lookRow(t)
            }
            ForEach(model.savedLocations) { saved in
                let location = WeatherLocation(saved: saved)
                Button {
                    model.select(locationID: location.id)
                } label: {
                    LocationRow(location: location, summary: model.weather.summary(for: location.id), formatter: model.formatter)
                }
                .buttonStyle(.plain)
                .lookRow(t)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        model.removeLocations(ids: [saved.id])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        renameText = saved.customName ?? saved.placeName
                        renaming = saved
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    Button {
                        renameText = saved.customName ?? saved.placeName
                        renaming = saved
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        model.select(locationID: location.id, showForecast: false)
                        model.selectedTab = .radar
                    } label: {
                        Label("Show on Radar", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button(role: .destructive) {
                        model.removeLocations(ids: [saved.id])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete { model.removeLocations(at: $0) }
            .onMove { model.moveLocations(from: $0, to: $1) }
        } header: {
            HStack {
                SettingsHeader(title: "Saved Places")
                Spacer()
                SettingsHeader(title: "\(model.savedLocations.count) of \(LocationLibrary.maximumLocations)")
            }
        } footer: {
            if !model.canAddLocation {
                SettingsFooter(text: "Your library is full. Delete a place to add another.")
            }
        }
    }
}

struct LocationRow: View {
    @Environment(\.lookTokens) private var t
    let location: WeatherLocation
    let summary: LocationWeatherSummary?
    let formatter: WeatherFormatter

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if location.isCurrentLocation {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundStyle(t.look == .instrument ? t.now : t.ink2)
                    }
                    Text(location.name)
                        .font(t.look == .liquid ? .headline : t.font(.textStrong, 17))
                        .foregroundStyle(t.ink)
                        .lineLimit(1)
                }
                Text(secondaryText)
                    .font(t.look == .liquid ? .caption : t.font(.text, 12))
                    .foregroundStyle(t.ink2)
                    .lineLimit(1)
                if let summary {
                    Text(summary.condition.description)
                        .font(t.look == .liquid ? .caption : t.font(.text, 12))
                        .foregroundStyle(t.ink2)
                }
            }
            Spacer()
            if let summary {
                Group {
                    if t.look == .liquid {
                        ConditionIcon(summary.condition, isDaylight: summary.isDaylight)
                    } else {
                        OutlineConditionIcon(summary.condition, isDaylight: summary.isDaylight)
                            .foregroundStyle(t.ink2)
                    }
                }
                .font(.title2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatter.temperature(summary.temperature))
                        .font(t.look == .liquid ? .system(size: 30, weight: .light) : t.font(t.look == .chroma ? .headline : .numberLight, 30))
                        .foregroundStyle(t.ink)
                    if let high = summary.high, let low = summary.low {
                        Text("H:\(formatter.temperature(high)) L:\(formatter.temperature(low))")
                            .font(t.look == .liquid ? .caption : t.font(.number, 12))
                            .foregroundStyle(t.ink2)
                    }
                }
                .frame(minWidth: 70, alignment: .trailing)
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var secondaryText: String {
        let timeZone = summary?.timeZone ?? location.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
        var parts: [String] = []
        if let timeZone, timeZone.identifier != TimeZone.current.identifier {
            parts.append(formatter.time(Date(), timeZone: timeZone))
        }
        if let subtitle = location.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
