import AiSkyKit
import SwiftUI

/// Air Quality Index with the driving pollutant, health guidance, a short forecast and pollen.
struct AirQualityCard: View {
    @Environment(AppModel.self) private var model
    let snapshot: WeatherSnapshot
    let now: Date

    @State private var showsDetails = false

    var body: some View {
        let scale = model.settings.aqiScale
        if let airQuality = snapshot.airQuality, let value = airQuality.index(for: scale) {
            let level = scale.level(for: value)
            WeatherCard(title: "Air Quality", systemImage: "aqi.medium", accessory: scale.shortName) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(value.rounded()))")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.name)
                            .font(.headline)
                        if let pollutant = airQuality.primaryPollutant(for: scale) {
                            Text("Primary pollutant: \(pollutant.symbol)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                ScaleBar(colors: AQILevel.levels(for: scale).map(Palette.aqi), position: min(1, value / scale.gaugeMaximum))
                Text(level.advice)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                forecastRow(airQuality: airQuality, scale: scale)

                DisclosureGroup(isExpanded: $showsDetails) {
                    VStack(spacing: 8) {
                        ForEach(airQuality.pollutants) { reading in
                            PollutantRow(reading: reading, scale: scale)
                        }
                        if !airQuality.pollen.isEmpty {
                            Divider().overlay(.white.opacity(0.2))
                            ForEach(airQuality.pollen) { pollen in
                                HStack {
                                    Label(pollen.type.displayName, systemImage: "leaf.fill")
                                    Spacer()
                                    Text(pollen.level.name)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .font(.callout)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(airQuality.pollen.isEmpty ? "Pollutants" : "Pollutants & Pollen")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(.white)
            }
        }
    }

    @ViewBuilder
    private func forecastRow(airQuality: AirQuality, scale: AQIScale) -> some View {
        let maxima = airQuality.dailyMaxima(for: scale, timeZone: snapshot.timeZone, from: now, days: 5)
        if maxima.count > 1 {
            HStack(spacing: 0) {
                ForEach(maxima, id: \.date) { entry in
                    VStack(spacing: 4) {
                        Text(model.formatter.dayLabel(entry.date, timeZone: snapshot.timeZone, now: now))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(Int(entry.value.rounded()))")
                            .font(.caption.weight(.bold))
                            .frame(minWidth: 34)
                            .padding(.vertical, 3)
                            .background(Palette.aqi(scale.level(for: entry.value)).opacity(0.75), in: Capsule())
                            .foregroundStyle(scale.level(for: entry.value).rank <= 1 ? Color.black : Color.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct PollutantRow: View {
    let reading: PollutantReading
    let scale: AQIScale

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(reading.index(for: scale).map { Palette.aqi(scale.level(for: $0)) } ?? .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(reading.pollutant.symbol)
                    .font(.callout.weight(.semibold))
                Text(reading.pollutant.name)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(concentration)
                    .font(.callout)
                if let index = reading.index(for: scale) {
                    Text("Index \(Int(index.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var concentration: String {
        let value = reading.concentration
        let number = value >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return "\(number) µg/m³"
    }
}
