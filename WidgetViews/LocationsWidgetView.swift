import AiSkyKit
import SwiftUI
import WidgetKit

struct LocationsWidgetView: View {
    @Environment(\.widgetInkMode) private var mode
    let entry: LocationsEntry

    var body: some View {
        let formatter = entry.settings.formatter
        let t = LookTokens.tokens(for: entry.settings.look).adapted(to: mode)
        VStack(spacing: 0) {
            if entry.rows.isEmpty {
                Text("Add places in Ai Sky to see them here.")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(Array(entry.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle().fill(t.line).frame(height: 1)
                }
                Link(destination: URL(string: "aisky://forecast/\(row.location.id)")!) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            WidgetLocationName(location: row.location)
                                .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 14))
                                .widgetAccentable()
                            if let summary = row.summary {
                                Text(summary.condition.description)
                                    .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                                    .foregroundStyle(t.ink2)
                            }
                        }
                        Spacer()
                        if let summary = row.summary {
                            WidgetConditionIcon(condition: summary.condition, isDaylight: summary.isDaylight, tokens: t)
                                .font(.body)
                            Text(formatter.temperature(summary.temperature))
                                .font(t.look == .liquid ? .title3.weight(.medium) : t.font(.display, 22))
                                .frame(minWidth: 40, alignment: .trailing)
                                .widgetAccentable()
                            if let high = summary.high, let low = summary.low {
                                Text("\(formatter.temperature(high)) / \(formatter.temperature(low))")
                                    .font(t.look == .liquid ? .caption2 : t.font(.number, 11))
                                    .foregroundStyle(t.ink2)
                                    .frame(width: 58, alignment: .trailing)
                            }
                        } else {
                            Text("--")
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(t.ink)
        .containerBackground(for: .widget) {
            LookWidgetBackground(
                tokens: t,
                condition: entry.rows.first?.summary?.condition ?? .partlyCloudy,
                isDaylight: entry.rows.first?.summary?.isDaylight ?? true
            )
        }
    }
}
