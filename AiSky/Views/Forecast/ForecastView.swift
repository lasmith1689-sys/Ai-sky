import AiSkyKit
import SwiftUI

/// Full forecast for one location.
struct ForecastView: View {
    @Environment(AppModel.self) private var model
    let location: WeatherLocation

    @State private var selectedDay: DailyForecast?
    @State private var selectedAlert: WeatherAlertInfo?
    @State private var presentedSheet: ForecastSheet?

    var body: some View {
        let snapshot = model.weather.snapshot(for: location.id)
        ZStack {
            SkyBackground(
                condition: snapshot?.current.condition ?? .partlyCloudy,
                isDaylight: snapshot?.current.isDaylight ?? true
            )
            .ignoresSafeArea()

            ScrollViewReader { proxy in
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
                .onChange(of: model.pendingSection) { _, _ in
                    scrollToPendingSection(proxy, snapshotLoaded: snapshot != nil)
                }
                .onChange(of: snapshot == nil) { _, _ in
                    scrollToPendingSection(proxy, snapshotLoaded: snapshot != nil)
                    presentPendingSheet(snapshotLoaded: snapshot != nil)
                }
                .onChange(of: model.pendingSheet) { _, _ in
                    presentPendingSheet(snapshotLoaded: snapshot != nil)
                }
                .onAppear {
                    scrollToPendingSection(proxy, snapshotLoaded: snapshot != nil)
                    presentPendingSheet(snapshotLoaded: snapshot != nil)
                }
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
        .sheet(item: $presentedSheet) { sheet in
            let snapshot = model.weather.snapshot(for: location.id)
            switch sheet {
            case .rainHistory:
                RainHistoryView(location: location, snapshot: snapshot)
            case .timeMachine:
                TimeMachineSheet(location: location, timeZone: snapshot?.timeZone ?? .current, date: oneYearAgo(snapshot))
            }
        }
    }

    /// The Time Machine opens on this day last year.
    private func oneYearAgo(_ snapshot: WeatherSnapshot?) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot?.timeZone ?? .current
        return calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    }

    /// Honors deep links like `aisky://forecast/<id>?show=rainHistory`.
    private func presentPendingSheet(snapshotLoaded: Bool) {
        guard let sheet = model.pendingSheet, snapshotLoaded,
              model.selectedLocation?.id == location.id else { return }
        model.pendingSheet = nil
        presentedSheet = sheet
    }

    /// Honors deep links like `aisky://forecast/<id>?section=airQuality` (used by widgets).
    private func scrollToPendingSection(_ proxy: ScrollViewProxy, snapshotLoaded: Bool) {
        guard let section = model.pendingSection, snapshotLoaded,
              model.selectedLocation?.id == location.id else { return }
        model.pendingSection = nil
        Task { @MainActor in
            // Let the page settle before scrolling.
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut) {
                proxy.scrollTo(section, anchor: .top)
            }
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
                    .id(ForecastSection.nextHour)
                HourlyCard(snapshot: snapshot, now: now)
                    .id(ForecastSection.hourly)
                DailyCard(
                    snapshot: snapshot,
                    now: now,
                    onSelect: { selectedDay = $0 },
                    onTimeMachine: { presentedSheet = .timeMachine }
                )
                .id(ForecastSection.daily)
                PrecipitationCard(snapshot: snapshot, now: now) { presentedSheet = .rainHistory }
                    .id(ForecastSection.precipitation)
                if snapshot.airQuality != nil {
                    AirQualityCard(snapshot: snapshot, now: now)
                        .id(ForecastSection.airQuality)
                }
                DetailsGrid(snapshot: snapshot, now: now)
                    .id(ForecastSection.details)
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
