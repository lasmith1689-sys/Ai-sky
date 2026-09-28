import AiSkyKit
import SwiftUI

/// Tappable banner for a government weather alert.
struct AlertBanner: View {
    let alert: WeatherAlertInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.alert(alert.severity))
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.headline)
                    Text(alert.source)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.alert(alert.severity).opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Palette.alert(alert.severity).opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AlertDetailView: View {
    @Environment(\.dismiss) private var dismiss
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
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(alert.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
