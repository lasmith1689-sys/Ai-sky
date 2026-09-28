import AiSkyKit
import MapKit
import SwiftUI

/// Search for a city, address, ZIP code or landmark and save it to the library.
struct AddLocationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = LocationSearchModel()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if search.query.isEmpty {
                    Section {
                        Text("Search for a city, address, ZIP code or landmark. You have \(LocationLibrary.remainingSlots(in: model.savedLocations)) of \(LocationLibrary.maximumLocations) spots left.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let current = model.currentLocation, model.canAddLocation {
                            Button {
                                saveCurrentLocation(current)
                            } label: {
                                Label("Save my current location (\(current.name ?? "here"))", systemImage: "location.fill")
                            }
                        }
                    }
                }
                ForEach(search.results, id: \.self) { completion in
                    Button {
                        Task { await add(completion) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if search.resolvingCompletion == completion {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(search.resolvingCompletion != nil)
                }
            }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City, address or ZIP")
            .onChange(of: search.query) { _, _ in
                search.queryChanged()
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Can't Add Location", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add(_ completion: MKLocalSearchCompletion) async {
        do {
            let location = try await search.resolve(completion)
            try model.addLocation(location)
            model.select(locationID: location.id.uuidString)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveCurrentLocation(_ current: CurrentLocationSnapshot) {
        let location = SavedLocation(
            placeName: current.name ?? "My Place",
            subtitle: current.subtitle,
            latitude: current.latitude,
            longitude: current.longitude,
            timeZoneIdentifier: current.timeZoneIdentifier,
            countryCode: current.countryCode
        )
        do {
            try model.addLocation(location)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
