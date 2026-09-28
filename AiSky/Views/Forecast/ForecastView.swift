import AiSkyKit
import SwiftUI

/// Full forecast for one location.
struct ForecastView: View {
    @Environment(AppModel.self) private var model
    let location: WeatherLocation

    @State private var selectedDay: DailyForecast?
    @State private var selectedAlert: WeatherAlertInfo?

    var body: some View {
        let snapshot = model.weather.snapshot(for: location.id)
        ZStack {
            SkyBackground(
                condition: snapshot?.current.condition ?? .partlyCloudy,
                isDaylight: snapshot?.current.isDaylight ?? true
            )
            .ignoresSafeArea()

            ScrollView {
                // Re-render every minute so "now" based content (next hour, updated time) stays current.
                TimelineView(.everyMinute) { context in
                    content(snapshot: snapshot, now: context.date)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await model.refresh(location, force: true)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .task(id: location.id) {
            await model.refresh(location)
        }
        .sheet(item: $selectedDay) { day in
            if let snapshot {
                DayDetailView(snapshot: snapshot, day: day)
            }
        }
        .sheet(item: $selectedAlert) { alert in
            AlertDetailView(alert: alert)
        }
    }

    @ViewBuilder
    private func content(snapshot: WeatherSnapshot?, now: Date) -> some View {
        VStack(spacing: 14) {
            CurrentHeaderView(location: location, snapshot: snapshot, now: now)

            if let snapshot {
                ForEach(snapshot.alerts.filter { $0.isActive(at: now) }) { alert in
                    AlertBanner(alert: alert) { selectedAlert = alert }
                }
                NextHourCard(snapshot: snapshot, now: now)
                HourlyCard(snapshot: snapshot, now: now)
                DailyCard(snapshot: snapshot, now: now) { selectedDay = $0 }
                PrecipitationCard(snapshot: snapshot, now: now)
                if snapshot.airQuality != nil {
                    AirQualityCard(snapshot: snapshot, now: now)
                }
                DetailsGrid(snapshot: snapshot, now: now)
                AttributionFooter(snapshot: snapshot, now: now)
            } else if let error = model.weather.error(for: location.id) {
                ErrorCard(message: error) {
                    Task { await model.refresh(location, force: true) }
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 60)
            }
        }
    }
}

struct ErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        WeatherCard(title: "Couldn't load weather", systemImage: "exclamationmark.triangle.fill") {
            Text(message)
                .font(.callout)
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
        }
    }
}
