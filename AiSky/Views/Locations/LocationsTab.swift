import AiSkyKit
import SwiftUI
import UIKit

/// The location library: device location plus up to 20 saved places.
struct LocationsTab: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: SavedLocation?
    @State private var renameText = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                currentLocationSection
                savedSection
            }
            .navigationTitle("Locations")
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
            } else if model.locationManager.isDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Location access is off — open Settings", systemImage: "location.slash")
                }
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
            }
        } header: {
            Text("My Location")
        }
    }

    private var savedSection: some View {
        Section {
            if model.savedLocations.isEmpty {
                Text("Save up to \(LocationLibrary.maximumLocations) places — home, work, the cabin — and swipe between them in the Forecast tab or pin them to widgets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(model.savedLocations) { saved in
                let location = WeatherLocation(saved: saved)
                Button {
                    model.select(locationID: location.id)
                } label: {
                    LocationRow(location: location, summary: model.weather.summary(for: location.id), formatter: model.formatter)
                }
                .buttonStyle(.plain)
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
                Text("Saved Places")
                Spacer()
                Text("\(model.savedLocations.count) of \(LocationLibrary.maximumLocations)")
            }
        } footer: {
            if !model.canAddLocation {
                Text("Your library is full. Delete a place to add another.")
            }
        }
    }
}

struct LocationRow: View {
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
                            .foregroundStyle(.blue)
                    }
                    Text(location.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let summary {
                    Text(summary.condition.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let summary {
                ConditionIcon(summary.condition, isDaylight: summary.isDaylight)
                    .font(.title2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatter.temperature(summary.temperature))
                        .font(.system(size: 30, weight: .light))
                    if let high = summary.high, let low = summary.low {
                        Text("H:\(formatter.temperature(high)) L:\(formatter.temperature(low))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
