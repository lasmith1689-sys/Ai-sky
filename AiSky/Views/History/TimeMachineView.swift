import AiSkyKit
import SwiftUI

/// Dark Sky's Time Machine: the weather on any date since 1940, or up to two weeks ahead.
/// Push it inside a `NavigationStack` (see ``TimeMachineSheet``).
struct TimeMachineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let location: WeatherLocation
    let calendar: Calendar

    @State private var date: Date
    @State private var day: HistoricalDay?
    @State private var errorMessage: String?
    @State private var isLoading = false

    init(location: WeatherLocation, timeZone: TimeZone, date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.location = location
        self.calendar = calendar
        _date = State(initialValue: calendar.startOfDay(for: date))
    }

    var body: some View {
        ZStack {
            LookPageBackground(condition: day?.summary?.condition ?? .partlyCloudy, isDaylight: true)
                .ignoresSafeArea()
                .animation(.easeInOut, value: day?.summary?.condition)
            ScrollView {
                VStack(alignment: .leading, spacing: t.sectionSpacing) {
                    dateControls
                    jumpChips
                    content
                }
                .padding(.horizontal, t.gutter)
                .padding(.vertical, 16)
            }
        }
        .foregroundStyle(t.ink)
        .lookNavigationTitle("Time Machine")
        .task(id: date) {
            await load()
        }
    }

    // MARK: Controls

    private var earliest: Date { WeatherHistoryClient.earliestDate(calendar: calendar) }
    private var latest: Date { WeatherHistoryClient.latestDate(today: Date(), calendar: calendar) }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.formatter.longDate(date, timeZone: calendar.timeZone))
                    .font(t.look == .liquid ? .title3.weight(.semibold) : t.font(.headline, 20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(relativeDescription)
                    .font(t.look == .liquid ? .caption : t.font(.text, 12))
                    .foregroundStyle(t.ink2)
            }
            HStack(spacing: 10) {
                stepButton(systemImage: "chevron.left", days: -1)
                    .disabled(date <= earliest)
                Spacer(minLength: 0)
                DatePicker("Date", selection: dateBinding, in: earliest...latest, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.timeZone, calendar.timeZone)
                Spacer(minLength: 0)
                stepButton(systemImage: "chevron.right", days: 1)
                    .disabled(date >= latest)
            }
        }
        .padding(t.surfaceStyle == .hairline ? 0 : 12)
        .padding(.bottom, t.surfaceStyle == .hairline ? 12 : 0)
        .lookSurface(t, radius: t.cardRadius)
        .overlay(alignment: .bottom) {
            if t.surfaceStyle == .hairline { LookRule(strong: true) }
        }
    }

    /// The picker keeps a time of day; always store local midnight.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { date = calendar.startOfDay(for: $0) }
        )
    }

    private func stepButton(systemImage: String, days: Int) -> some View {
        Button {
            move(days: days)
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(t.ink)
                .frame(width: 34, height: 34)
                .background(t.look == .liquid ? Color.white.opacity(0.14) : t.surfaceAlt, in: Circle())
                .overlay(Circle().strokeBorder(t.surfaceStyle == .hairline ? t.line : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(days < 0 ? "Previous day" : "Next day")
    }

    private func move(days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: date) else { return }
        date = min(max(next, earliest), latest)
    }

    /// "On this day" shortcuts.
    private var jumpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                jumpChip("Today", years: 0)
                jumpChip("1 year ago", years: 1)
                jumpChip("10 years ago", years: 10)
                jumpChip("25 years ago", years: 25)
                jumpChip("50 years ago", years: 50)
            }
        }
    }

    private func jumpChip(_ title: String, years: Int) -> some View {
        Button {
            let today = calendar.startOfDay(for: Date())
            date = max(calendar.date(byAdding: .year, value: -years, to: today) ?? today, earliest)
        } label: {
            Text(title)
                .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                .foregroundStyle(t.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(t.look == .liquid ? Color.white.opacity(0.14) : t.surfaceAlt, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var relativeDescription: String {
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow (forecast)"
        case -1: return "Yesterday"
        case 2...: return "In \(days) days (forecast)"
        default:
            let years = calendar.dateComponents([.year], from: date, to: today).year ?? 0
            if years >= 1 { return years == 1 ? "1 year ago" : "\(years) years ago" }
            return "\(-days) days ago"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let day, calendar.isDate(day.date, inSameDayAs: date) {
            DayDetailContent(
                day: day.summary,
                hours: day.hours,
                timeZone: day.timeZone,
                isPast: !day.isForecast && !day.isToday
            )
            Label(day.sourceDescription, systemImage: "info.circle")
                .font(t.look == .liquid ? .caption : t.font(.text, 12))
                .foregroundStyle(t.ink2)
        } else if let errorMessage, !isLoading {
            ErrorCard(message: errorMessage) {
                Task { await load() }
            }
        } else {
            ProgressView()
                .tint(t.ink2)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    private func load() async {
        let requested = date
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await WeatherHistoryStore.shared.day(for: location, date: requested, calendar: calendar)
            guard requested == date else { return }
            day = result
        } catch is CancellationError {
            return
        } catch {
            guard requested == date else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// Presents the Time Machine on its own, e.g. from the 10-day forecast.
struct TimeMachineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let location: WeatherLocation
    let timeZone: TimeZone
    let date: Date

    var body: some View {
        NavigationStack {
            TimeMachineView(location: location, timeZone: timeZone, date: date)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
