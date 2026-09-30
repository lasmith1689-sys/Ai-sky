import AiSkyKit
import SwiftUI

/// Air Quality Index with the driving pollutant, health guidance, a short forecast and pollen.
struct AirQualityCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var lookTokens
    let snapshot: WeatherSnapshot
    let now: Date

    @State private var showsDetails = false

    var body: some View {
        let scale = model.settings.aqiScale
        let t = lookTokens.toned(.green)
        if let airQuality = snapshot.airQuality, let value = airQuality.index(for: scale) {
            let level = scale.level(for: value)
            WeatherCard(title: "Air Quality", systemImage: "aqi.medium", accessory: scale.shortName, tone: .green) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(value.rounded()))")
                        .font(t.look == .liquid ? .system(size: 44, weight: .semibold, design: .rounded) : t.font(t.look == .chroma ? .headline : .numberLight, 44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.name)
                            .font(t.look == .liquid ? .headline : t.font(.textStrong, t.bodySize + 1))
                        if let pollutant = airQuality.primaryPollutant(for: scale) {
                            Text("Primary pollutant: \(pollutant.symbol)")
                                .font(t.look == .liquid ? .caption : t.font(.text, 12))
                                .foregroundStyle(t.ink2)
                        }
                    }
                }
                ScaleBar(colors: AQILevel.levels(for: scale).map(Palette.aqi), position: min(1, value / scale.gaugeMaximum))
                Text(level.advice)
                    .font(t.look == .liquid ? .footnote : t.font(.text, t.bodySize - 1))
                    .foregroundStyle(t.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                forecastRow(airQuality: airQuality, scale: scale, t: t)

                DisclosureGroup(isExpanded: $showsDetails) {
                    VStack(spacing: 8) {
                        ForEach(airQuality.pollutants) { reading in
                            PollutantRow(reading: reading, scale: scale)
                        }
                        if !airQuality.pollen.isEmpty {
                            LookRule()
                            ForEach(airQuality.pollen) { pollen in
                                HStack {
                                    Label(pollen.type.displayName, systemImage: "leaf.fill")
                                    Spacer()
                                    Text(pollen.level.name)
                                        .foregroundStyle(t.ink2)
                                }
                                .font(t.look == .liquid ? .callout : t.font(.text, t.bodySize))
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(airQuality.pollen.isEmpty ? "Pollutants" : "Pollutants & Pollen")
                        .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, t.bodySize))
                }
                .tint(t.ink)
            }
        }
    }

    @ViewBuilder
    private func forecastRow(airQuality: AirQuality, scale: AQIScale, t: LookTokens) -> some View {
        let maxima = airQuality.dailyMaxima(for: scale, timeZone: snapshot.timeZone, from: now, days: 5)
        if maxima.count > 1 {
            HStack(spacing: 0) {
                ForEach(maxima, id: \.date) { entry in
                    let entryLevel = scale.level(for: entry.value)
                    VStack(spacing: 4) {
                        Text(model.formatter.dayLabel(entry.date, timeZone: snapshot.timeZone, now: now))
                            .font(t.look == .liquid ? .caption2 : t.font(.label, 10))
                            .foregroundStyle(t.ink2)
                        Text("\(Int(entry.value.rounded()))")
                            .font(t.look == .liquid ? .caption.weight(.bold) : t.font(.textStrong, 12))
                            .frame(minWidth: 34)
                            .padding(.vertical, 3)
                            .background(Palette.aqi(entryLevel).opacity(0.85), in: Capsule())
                            .foregroundStyle(entryLevel.rank <= 1 ? Color.black : Color.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct PollutantRow: View {
    @Environment(\.lookTokens) private var t
    let reading: PollutantReading
    let scale: AQIScale

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(reading.index(for: scale).map { Palette.aqi(scale.level(for: $0)) } ?? .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(reading.pollutant.symbol)
                    .font(t.look == .liquid ? .callout.weight(.semibold) : t.font(.textStrong, t.bodySize))
                Text(reading.pollutant.name)
                    .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                    .foregroundStyle(t.ink2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(concentration)
                    .font(t.look == .liquid ? .callout : t.font(.number, t.bodySize))
                if let index = reading.index(for: scale) {
                    Text("Index \(Int(index.rounded()))")
                        .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                        .foregroundStyle(t.ink2)
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
