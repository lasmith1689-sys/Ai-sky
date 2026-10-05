import AiSkyKit
import SwiftUI
import UIKit

/// Swipe between the device location and every saved place.
struct ForecastTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t

    var body: some View {
        let locations = model.forecastLocations
        if locations.isEmpty {
            WelcomeView()
        } else {
            let selection = Binding<String>(
                get: {
                    if let id = model.selectedLocationID, locations.contains(where: { $0.id == id }) {
                        return id
                    }
                    return locations[0].id
                },
                set: { model.select(locationID: $0, showForecast: false) }
            )
            ZStack(alignment: .top) {
                TabView(selection: selection) {
                    ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                        ForecastView(location: location, page: index, pageCount: locations.count)
                            .tag(location.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Liquid's sky runs under the floating system tab bar.
                .ignoresSafeArea(edges: t.look == .liquid ? .all : .top)

                if locations.count > 1 {
                    LookPageIndicator(locations: locations, selectedID: selection.wrappedValue)
                        .padding(.top, 2)
                }
            }
            .background(t.background.ignoresSafeArea())
        }
    }
}

/// First launch: no permission and no saved places yet.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t

    var body: some View {
        ZStack {
            LookPageBackground().ignoresSafeArea()
            VStack(alignment: t.look == .liquid ? .center : .leading, spacing: 18) {
                Spacer()
                if t.look == .liquid {
                    Image(systemName: "cloud.sun.rain.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 76))
                } else {
                    Text("Ai Sky")
                        .lookLabel(t, color: t.ink2)
                }
                Text("Welcome to Ai Sky")
                    .font(t.font(t.look == .instrument || t.look == .obsidian ? .numberLight : .headline, 34, relativeTo: .largeTitle))
                    .multilineTextAlignment(t.look == .liquid ? .center : .leading)
                Text("Down-to-the-minute rain forecasts, radar, air quality and real-feel temperatures for up to \(LocationLibrary.maximumLocations) places.")
                    .font(t.font(.text, 16))
                    .multilineTextAlignment(t.look == .liquid ? .center : .leading)
                    .foregroundStyle(t.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                VStack(spacing: 12) {
                    if model.locationManager.isAuthorized {
                        HStack(spacing: 10) {
                            ProgressView().tint(t.ink)
                            Text("Finding your location…")
                                .font(t.font(.textStrong, 16))
                        }
                        .padding(.bottom, 8)
                    } else if model.locationManager.isDenied {
                        Text("Location access is off. Enable it in Settings to see weather where you are.")
                            .font(t.font(.text, 13))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(t.ink2)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(LookButtonStyle(kind: .secondary, fullWidth: true))
                    } else {
                        Button {
                            model.locationManager.requestAuthorization()
                        } label: {
                            Label("Use My Location", systemImage: "location.fill")
                        }
                        .buttonStyle(LookButtonStyle(kind: .primary, fullWidth: true))
                    }
                    Button {
                        model.selectedTab = .locations
                        model.isAddingLocation = true
                    } label: {
                        Label("Search for a Place", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(LookButtonStyle(kind: .secondary, fullWidth: true))
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, max(t.gutter, 24))
            .foregroundStyle(t.ink)
        }
    }
}
