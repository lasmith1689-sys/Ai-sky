import AiSkyKit
import SwiftUI

/// Everything a look's forecast sections need, computed once per render.
struct ForecastContext {
    let location: WeatherLocation
    let snapshot: WeatherSnapshot
    let now: Date
    let formatter: WeatherFormatter
    let settings: AppSettings
    let tokens: LookTokens
    let onSelectDay: (DailyForecast) -> Void
    let onTimeMachine: () -> Void

    var timeZone: TimeZone { snapshot.timeZone }
    var current: CurrentConditions { snapshot.conditions(at: now) }
    var today: DailyForecast? { snapshot.day(containing: now) }
    var window: NextHourWindow { NextHourWindow(forecast: snapshot.nextHour, now: now) }

    /// Clock label in the look's style (24-hour for Instrument and Obsidian).
    func clock(_ date: Date) -> String {
        LookClock.time(date, timeZone: timeZone, tokens: tokens, formatter: formatter)
    }

    /// "4:10" without AM/PM on a 12-hour phone, for sentences.
    func shortClock(_ date: Date) -> String {
        let time = formatter.time(date, timeZone: timeZone)
        return time
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: " AM", with: "")
            .replacingOccurrences(of: " PM", with: "")
    }

    func hourLabel(_ date: Date) -> String {
        LookClock.hour(date, timeZone: timeZone, tokens: tokens, formatter: formatter)
    }

    func temperature(_ celsius: Double) -> String { formatter.temperature(celsius) }

    /// Whole degrees without the degree sign.
    func degrees(_ celsius: Double) -> String {
        let value = Int(formatter.temperatureValue(celsius).rounded())
        return value == 0 ? "0" : String(value)
    }

    /// Whether `hour` is the current hour.
    func isNow(_ hour: HourlyForecast) -> Bool {
        hour.date <= now && now.timeIntervalSince(hour.date) < 3600
    }

    func isToday(_ day: DailyForecast) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(day.date, inSameDayAs: now)
    }

    /// The next `limit` hours, starting with the current one.
    func hours(_ limit: Int) -> [HourlyForecast] {
        snapshot.upcomingHours(from: now, limit: limit)
    }

    func days(_ limit: Int = 10) -> [DailyForecast] {
        snapshot.upcomingDays(from: now, limit: limit)
    }

    /// Sunrise and sunset times between `start` and `end`.
    func sunEvents(from start: Date, to end: Date) -> [(date: Date, rising: Bool)] {
        snapshot.daily.flatMap { day -> [(date: Date, rising: Bool)] in
            var events: [(date: Date, rising: Bool)] = []
            if let sunrise = day.sunrise { events.append((sunrise, true)) }
            if let sunset = day.sunset { events.append((sunset, false)) }
            return events
        }
        .filter { $0.date > max(start, now) && $0.date < end }
        .sorted { $0.date < $1.date }
    }
}

/// Full forecast for one location, laid out by the selected look.
struct ForecastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let location: WeatherLocation
    var page = 0
    var pageCount = 1

    @State private var selectedDay: DailyForecast?
    @State private var selectedAlert: WeatherAlertInfo?
    @State private var presentedSheet: ForecastSheet?

    var body: some View {
        let snapshot = model.weather.snapshot(for: location.id)
        // The sky Liquid draws behind the page; its cards follow it (light glass on blue skies,
        // a dark sheen on gray ones).
        let sky = snapshot?.current.condition ?? .partlyCloudy
        let daylight = snapshot?.current.isDaylight ?? true
        ZStack {
            LookPageBackground(condition: sky, isDaylight: daylight)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    // Re-render every minute so "now" based content (next hour, updated time) stays current.
                    TimelineView(.everyMinute) { context in
                        content(snapshot: snapshot, now: context.date)
                    }
                    .padding(.horizontal, t.gutter)
                    .padding(.top, pageCount > 1 ? 16 : 6)
                    .padding(.bottom, t.look == .liquid ? 96 : 32)
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
                    presentPendingSheet(snapshot: snapshot)
                }
                .onChange(of: model.pendingSheet) { _, _ in
                    presentPendingSheet(snapshot: snapshot)
                }
                .onAppear {
                    scrollToPendingSection(proxy, snapshotLoaded: snapshot != nil)
                    presentPendingSheet(snapshot: snapshot)
                }
            }

            StatusBarScrim()
        }
        .lookSky(sky, isDaylight: daylight)
        .foregroundStyle(t.ink)
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
    private func presentPendingSheet(snapshot: WeatherSnapshot?) {
        guard let snapshot, model.selectedLocation?.id == location.id else { return }
        #if DEBUG
        // CI smoke test: `-AiSkyScreen dayDetail` opens the first forecast day.
        if model.debugOpensDayDetail, let day = snapshot.upcomingDays(from: Date(), limit: 1).first {
            model.debugOpensDayDetail = false
            selectedDay = day
            return
        }
        #endif
        guard let sheet = model.pendingSheet else { return }
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
        VStack(spacing: t.sectionSpacing) {
            if let snapshot {
                let context = ForecastContext(
                    location: location,
                    snapshot: snapshot,
                    now: now,
                    formatter: model.formatter,
                    settings: model.settings,
                    tokens: t.onSky(snapshot.current.condition, isDaylight: snapshot.current.isDaylight),
                    onSelectDay: { selectedDay = $0 },
                    onTimeMachine: { presentedSheet = .timeMachine }
                )
                LookHero(context: context)

                ForEach(snapshot.alerts.filter { $0.isActive(at: now) }) { alert in
                    AlertBanner(alert: alert) { selectedAlert = alert }
                }
                LookNextHour(context: context)
                    .id(ForecastSection.nextHour)
                LookHourly(context: context)
                    .id(ForecastSection.hourly)
                LookDaily(context: context)
                    .id(ForecastSection.daily)
                HourlyChartCard(snapshot: snapshot, now: now)
                PrecipitationCard(snapshot: snapshot, now: now) { presentedSheet = .rainHistory }
                    .id(ForecastSection.precipitation)
                if snapshot.airQuality != nil {
                    AirQualityCard(snapshot: snapshot, now: now)
                        .id(ForecastSection.airQuality)
                }
                DetailsGrid(snapshot: snapshot, now: now)
                    .id(ForecastSection.details)
                AttributionFooter(snapshot: snapshot, now: now)
            } else {
                LookHeroPlaceholder(location: location, now: now)
                if let error = model.weather.error(for: location.id) {
                    ErrorCard(message: error) {
                        Task { await model.refresh(location, force: true) }
                    }
                } else {
                    ProgressView()
                        .tint(t.ink2)
                        .padding(.top, 40)
                }
            }
        }
    }
}

struct ErrorCard: View {
    @Environment(\.lookTokens) private var t
    let message: String
    let retry: () -> Void

    var body: some View {
        WeatherCard(title: "Couldn't load weather", systemImage: "exclamationmark.triangle.fill") {
            Text(message)
                .font(t.font(.text, t.bodySize))
                .foregroundStyle(t.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: retry)
                .buttonStyle(LookButtonStyle())
        }
    }
}

// MARK: - Look dispatch

/// Header and hero: the part of the forecast where the looks differ most.
struct LookHero: View {
    let context: ForecastContext

    var body: some View {
        switch context.tokens.look {
        case .liquid: LiquidHero(context: context)
        case .obsidian: ObsidianHero(context: context)
        case .instrument: InstrumentHero(context: context)
        case .editorial: EditorialHero(context: context)
        case .horizon: HorizonHero(context: context)
        case .chroma: ChromaHero(context: context)
        }
    }
}

struct LookNextHour: View {
    let context: ForecastContext

    var body: some View {
        switch context.tokens.look {
        case .liquid: LiquidNextHour(context: context)
        case .obsidian: ObsidianNextHour(context: context)
        case .instrument: InstrumentNextHour(context: context)
        case .editorial: EditorialNextHour(context: context)
        case .horizon: HorizonNextHour(context: context)
        case .chroma: ChromaNextHour(context: context)
        }
    }
}

struct LookHourly: View {
    let context: ForecastContext

    var body: some View {
        switch context.tokens.look {
        case .liquid: LiquidHourly(context: context)
        case .obsidian: ObsidianHourly(context: context)
        case .instrument: InstrumentHourly(context: context)
        case .editorial: EditorialHourly(context: context)
        case .horizon: HorizonTimeline(context: context)
        case .chroma: ChromaHourly(context: context)
        }
    }
}

struct LookDaily: View {
    let context: ForecastContext

    var body: some View {
        switch context.tokens.look {
        case .liquid: LiquidDaily(context: context)
        case .obsidian: ObsidianDaily(context: context)
        case .instrument: InstrumentDaily(context: context)
        case .editorial: EditorialDaily(context: context)
        case .horizon: HorizonDaily(context: context)
        case .chroma: ChromaDaily(context: context)
        }
    }
}

/// Header with an empty reading while the first forecast loads.
struct LookHeroPlaceholder: View {
    @Environment(\.lookTokens) private var t
    let location: WeatherLocation
    let now: Date

    var body: some View {
        VStack(alignment: t.look == .liquid ? .center : .leading, spacing: 8) {
            HStack(spacing: 6) {
                if location.isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(location.name)
                    .font(t.look == .liquid ? .title2.weight(.semibold) : t.font(.textStrong, 18))
                    .lineLimit(1)
            }
            Text("--°")
                .font(t.font(.display, 96, relativeTo: .largeTitle))
                .foregroundStyle(t.ink3)
                .redacted(reason: .placeholder)
        }
        .frame(maxWidth: .infinity, alignment: t.look == .liquid ? .center : .leading)
        .padding(.top, 12)
        .accessibilityLabel("Loading weather for \(location.name)")
    }
}
