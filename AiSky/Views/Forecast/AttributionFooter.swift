import AiSkyKit
import SwiftUI

/// Data sources, required attributions and freshness.
struct AttributionFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lookTokens) private var t
    let snapshot: WeatherSnapshot
    let now: Date

    @State private var appleAttribution: WeatherAttributionInfo?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(snapshot.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .multilineTextAlignment(.center)
            }

            Text(WeatherFormatter.updatedText(since: snapshot.fetchedAt, now: now))
                .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))

            if snapshot.source == .appleWeather {
                if let appleAttribution {
                    AsyncImage(url: colorScheme == .dark ? appleAttribution.combinedMarkDarkURL : appleAttribution.combinedMarkLightURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(appleAttribution.serviceName)
                    }
                    .frame(height: 14)
                    Link("Data sources & legal", destination: appleAttribution.legalPageURL)
                } else {
                    Text("Weather data by Apple Weather")
                }
            }

            Link(destination: URL(string: "https://open-meteo.com/")!) {
                Text(snapshot.source == .openMeteo
                     ? "Weather & air quality data by Open-Meteo.com (CC BY 4.0)"
                     : "Air quality & precipitation history by Open-Meteo.com (CC BY 4.0)")
            }

            if snapshot.location.isLikelyInUnitedStates && snapshot.source == .openMeteo {
                Text("Alerts from the National Weather Service")
            }
        }
        .font(t.look == .liquid ? .caption : t.font(.text, 12))
        .foregroundStyle(t.ink2)
        .tint(t.ink2)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .task(id: snapshot.source) {
            await loadAttribution()
        }
    }

    private func loadAttribution() async {
        guard snapshot.source == .appleWeather, appleAttribution == nil else { return }
        #if canImport(WeatherKit)
        appleAttribution = try? await WeatherKitProvider.attribution()
        #endif
    }
}
