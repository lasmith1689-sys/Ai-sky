import AiSkyKit
import SwiftUI

/// Location name, big temperature, condition, feels-like and today's range.
struct CurrentHeaderView: View {
    @Environment(AppModel.self) private var model
    let location: WeatherLocation
    let snapshot: WeatherSnapshot?
    let now: Date

    var body: some View {
        let formatter = model.formatter
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if location.isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.caption)
                }
                Text(location.name)
                    .font(.title.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if location.isCurrentLocation {
                Text("My Location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let snapshot {
                let current = snapshot.conditions(at: now)
                let today = snapshot.day(containing: now)

                Text(formatter.temperature(current.temperature))
                    .font(.system(size: 96, weight: .thin))
                    .contentTransition(.numericText())
                    .padding(.leading, 24) // optically center, ignoring the degree sign
                    .accessibilityLabel("Temperature \(formatter.temperature(current.temperature, includeUnit: true))")

                HStack(spacing: 6) {
                    ConditionIcon(current.condition, isDaylight: current.isDaylight)
                    Text(current.condition.description)
                }
                .font(.title3.weight(.medium))

                Text("Feels like \(formatter.temperature(current.apparentTemperature))")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                if let today {
                    Text("H:\(formatter.temperature(today.high))  L:\(formatter.temperature(today.low))")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text(headline(snapshot))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
            } else {
                Text("--°")
                    .font(.system(size: 96, weight: .thin))
                    .redacted(reason: .placeholder)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    /// Dark Sky style: lead with imminent precipitation, otherwise summarize the day.
    private func headline(_ snapshot: WeatherSnapshot) -> String {
        let nextHour = NextHourSummarizer.summarize(snapshot.nextHour, now: now)
        if nextHour.isPrecipitationExpected {
            return nextHour.text
        }
        return ForecastNarrator.daySummary(hours: snapshot.hourly, now: now, timeZone: snapshot.timeZone, formatter: model.formatter)
    }
}
