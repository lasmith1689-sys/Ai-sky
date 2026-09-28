import AiSkyKit
import SwiftUI
import UIKit

/// Swipe between the device location and every saved place.
struct ForecastTab: View {
    @Environment(AppModel.self) private var model

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
                    ForEach(locations) { location in
                        ForecastView(location: location)
                            .tag(location.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .top)

                if locations.count > 1 {
                    PageIndicator(locations: locations, selectedID: selection.wrappedValue)
                        .padding(.top, 4)
                }
            }
            .background(Color.black)
        }
    }
}

/// Dots showing which page is visible; the device location gets an arrow like Apple Weather.
private struct PageIndicator: View {
    let locations: [WeatherLocation]
    let selectedID: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(locations) { location in
                let selected = location.id == selectedID
                Group {
                    if location.isCurrentLocation {
                        Image(systemName: "location.fill")
                            .font(.system(size: 7, weight: .bold))
                    } else {
                        Circle().frame(width: 6, height: 6)
                    }
                }
                .foregroundStyle(.white.opacity(selected ? 1 : 0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.15), in: Capsule())
        .accessibilityHidden(true)
    }
}

/// First launch: no permission and no saved places yet.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            SkyBackground(condition: .partlyCloudy, isDaylight: true).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "cloud.sun.rain.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 76))
                Text("Welcome to Ai Sky")
                    .font(.largeTitle.bold())
                Text("Down-to-the-minute rain forecasts, radar, air quality and real-feel temperatures for up to \(LocationLibrary.maximumLocations) places.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 32)
                Spacer()
                VStack(spacing: 12) {
                    if model.locationManager.isDenied {
                        Text("Location access is off. Enable it in Settings to see weather where you are.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8))
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            model.locationManager.requestAuthorization()
                        } label: {
                            Label("Use My Location", systemImage: "location.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Button {
                        model.selectedTab = .locations
                        model.isAddingLocation = true
                    } label: {
                        Label("Search for a Place", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
    }
}
