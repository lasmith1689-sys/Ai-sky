import AiSkyKit
import SwiftUI

/// Tappable banner for a government weather alert.
struct AlertBanner: View {
    @Environment(\.lookTokens) private var t
    let alert: WeatherAlertInfo
    let action: () -> Void

    var body: some View {
        let color = Palette.alert(alert.severity)
        let radius = t.surfaceStyle == .hairline ? 0 : t.tileRadius
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(t.look == .liquid ? .headline : t.font(.textStrong, t.bodySize + 1))
                        .foregroundStyle(t.ink)
                    Text(alert.source)
                        .font(t.look == .liquid ? .caption : t.font(.text, 12))
                        .foregroundStyle(t.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(t.ink3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(t.colorScheme == .light ? 0.14 : 0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(color.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AlertDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lookTokens) private var t
    let alert: WeatherAlertInfo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(alert.severity.rawValue.capitalized, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.alert(alert.severity))
                    if let headline = alert.headline {
                        Text(headline)
                            .font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let region = alert.region {
                            LabeledContent("Area", value: region)
                        }
                        if let effective = alert.effective {
                            LabeledContent("From") { Text(effective, format: .dateTime.weekday().hour().minute()) }
                        }
                        if let expires = alert.expires {
                            LabeledContent("Until") { Text(expires, format: .dateTime.weekday().hour().minute()) }
                        }
                        LabeledContent("Issued by", value: alert.source)
                    }
                    .font(.subheadline)
                    if let details = alert.details {
                        Text(details)
                    }
                    if let instruction = alert.instruction {
                        Text("What to do")
                            .font(.headline)
                        Text(instruction)
                    }
                    if let url = alert.detailsURL {
                        Link(destination: url) {
                            Label("Full alert text", systemImage: "safari")
                        }
                    }
                }
                .font(t.look == .liquid ? .body : t.font(.text, t.bodySize + 1))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lookScreen(t)
            .lookNavigationTitle(alert.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
