import AiSkyKit
import SwiftUI

/// Translucent rounded card used for every section of the forecast.
struct WeatherCard<Content: View>: View {
    let title: String
    let systemImage: String
    var accessory: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title.uppercased(), systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let accessory {
                    Text(accessory)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Small square tile for the details grid (humidity, wind, UV...).
struct DetailTile<Accessory: View>: View {
    let title: String
    let systemImage: String
    let value: String
    var detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Text(value)
                .font(.title.weight(.medium))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            accessory()
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension DetailTile where Accessory == EmptyView {
    init(title: String, systemImage: String, value: String, detail: String? = nil) {
        self.init(title: title, systemImage: systemImage, value: value, detail: detail) { EmptyView() }
    }
}

/// Horizontal gradient bar with a marker, used for AQI and UV scales.
struct ScaleBar: View {
    let colors: [Color]
    /// 0...1 position of the marker.
    let position: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                    .frame(width: 9, height: 9)
                    .offset(x: max(0, min(proxy.size.width - 9, proxy.size.width * position - 4.5)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) {
        self = Palette.color(hex: hex)
    }
}
