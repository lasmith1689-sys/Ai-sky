import AiSkyKit
import SwiftUI

/// Dark Sky's signature minute-by-minute precipitation graph.
struct NextHourCard: View {
    @Environment(AppModel.self) private var model
    let snapshot: WeatherSnapshot
    let now: Date

    var body: some View {
        let summary = NextHourSummarizer.summarize(snapshot.nextHour, now: now)
        WeatherCard(title: "Next Hour", systemImage: "clock.fill", accessory: resolutionLabel) {
            Text(summary.text)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let nextHour = snapshot.nextHour, summary.state != .unavailable {
                if summary.isPrecipitationExpected {
                    MinutePrecipitationChart(forecast: nextHour, now: now)
                        .frame(height: 120)
                        .padding(.top, 4)
                } else {
                    MinutePrecipitationChart(forecast: nextHour, now: now, showsGuides: false)
                        .frame(height: 44)
                        .opacity(0.6)
                }
                if let rate = snapshot.current.precipitationIntensity, rate >= 0.05 {
                    Text("Now: \(PrecipitationIntensity(millimetersPerHour: rate).displayName.lowercased()) \(snapshot.current.condition.precipitationKind.noun), \(model.formatter.precipitationRate(rate))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    private var resolutionLabel: String? {
        guard let nextHour = snapshot.nextHour else { return nil }
        return nextHour.isMinuteByMinute ? "Minute by minute" : "15-minute data"
    }
}
