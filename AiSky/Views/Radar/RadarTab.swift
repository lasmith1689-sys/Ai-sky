import AiSkyKit
import CoreLocation
import SwiftUI

/// Full-screen animated precipitation radar.
struct RadarTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    @State private var radar = RadarViewModel()
    @State private var focus: MapFocus?
    @State private var center: CLLocationCoordinate2D?
    @State private var spot: RadarSpot?
    @State private var spotSheet: ForecastSheet?
    @AppStorage("radarSpotHintSeen") private var spotHintSeen = false

    var body: some View {
        ZStack {
            RadarMapView(
                frames: radar.frames,
                currentFrameID: radar.currentFrame?.id,
                opacity: model.settings.radarOpacity,
                mapStyle: model.settings.radarMapStyle,
                pins: pins,
                focus: focus,
                spot: spot?.coordinate,
                onRegionChange: { coordinate in
                    center = coordinate
                    Task { await reloadIfSourceChanged(for: coordinate) }
                },
                onSelectPin: { id in
                    model.select(locationID: id)
                },
                onLongPress: { coordinate in
                    dropSpot(at: coordinate)
                }
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                topBar
                Spacer()
                if let message = radar.errorMessage {
                    Text(message)
                        .font(t.look == .liquid ? .footnote : t.font(.text, 13))
                        .foregroundStyle(t.ink)
                        .padding(10)
                        .lookPanel(t, radius: 12)
                }
                if let spot {
                    SpotCard(
                        spot: spot,
                        onShow: { spotSheet = $0 },
                        onClose: { withAnimation { self.spot = nil } }
                    )
                    .id(spot.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !spotHintSeen {
                    Label("Touch and hold the map for rainfall history anywhere", systemImage: "hand.tap")
                        .font(t.look == .liquid ? .caption : t.font(.text, 12))
                        .foregroundStyle(t.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .lookPanel(t, radius: 999)
                }
                RadarControls(radar: radar, speed: model.settings.radarSpeed)
            }
            .padding(12)
        }
        .task {
            let start = startingCoordinate
            if focus == nil {
                focus = MapFocus(coordinate: start, span: 4)
            }
            #if DEBUG
            if Self.debugDropsSpot, spot == nil {
                dropSpot(at: start)
            }
            #endif
            await radar.load(preference: model.settings.radarSource, latitude: start.latitude, longitude: start.longitude)
            radar.startAutoRefresh { [model] in
                let point = center ?? start
                return (model.settings.radarSource, point.latitude, point.longitude)
            }
        }
        .onDisappear {
            radar.pause()
            radar.stopAutoRefresh()
        }
        .sheet(item: $spotSheet) { sheet in
            if let spot {
                switch sheet {
                case .rainHistory:
                    RainHistoryView(location: spot.weatherLocation, snapshot: nil)
                case .timeMachine:
                    TimeMachineSheet(location: spot.weatherLocation, timeZone: spot.timeZone, date: spot.yesterday)
                }
            }
        }
        .onChange(of: model.settings.radarSource) { _, newValue in
            let point = center ?? startingCoordinate
            Task { await radar.load(preference: newValue, latitude: point.latitude, longitude: point.longitude, force: true) }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        @Bindable var model = model
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if t.look == .liquid || t.surfaceStyle == .block {
                    Text(radar.source.displayName)
                        .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 15))
                } else {
                    Text(radar.source.displayName)
                        .lookLabel(t, size: 12, color: t.ink)
                }
                Text(radar.source == .noaa ? "U.S. base reflectivity" : "Global composite · past 2 hr")
                    .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                    .foregroundStyle(t.ink2)
            }
            .foregroundStyle(t.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .lookPanel(t, radius: 12)

            Spacer()

            VStack(spacing: 8) {
                Menu {
                    Picker("Radar", selection: $model.settings.radarSource) {
                        ForEach(RadarSourcePreference.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker("Map", selection: $model.settings.radarMapStyle) {
                        ForEach(MapStylePreference.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker("Opacity", selection: $model.settings.radarOpacity) {
                        Text("Light (50%)").tag(0.5)
                        Text("Medium (75%)").tag(0.75)
                        Text("Solid (90%)").tag(0.9)
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .mapButtonStyle(t)
                }
                .accessibilityLabel("Radar and map options")
                Button {
                    focus = MapFocus(coordinate: startingCoordinate, span: 4)
                } label: {
                    Image(systemName: "location.fill")
                        .mapButtonStyle(t)
                }
                .accessibilityLabel("Center on selected location")
                Button {
                    let point = center ?? startingCoordinate
                    Task { await radar.load(preference: model.settings.radarSource, latitude: point.latitude, longitude: point.longitude, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .mapButtonStyle(t)
                }
                .accessibilityLabel("Reload radar")
            }
        }
    }

    private var startingCoordinate: CLLocationCoordinate2D {
        if let location = model.selectedLocation {
            return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        }
        return CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35) // Center of the contiguous U.S.
    }

    private var pins: [RadarPin] {
        let formatter = model.formatter
        return model.forecastLocations.map { location in
            let summary = model.weather.summary(for: location.id)
            return RadarPin(
                id: location.id,
                name: location.name,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                temperatureText: summary.map { formatter.temperature($0.temperature) },
                tintHex: location.isCurrentLocation ? 0x0A84FF : 0x5E5CE6
            )
        }
    }

    #if DEBUG
    /// CI smoke test: `-AiSkyScreen radarSpot` opens the radar with a spot dropped on the selected place.
    private static var debugDropsSpot: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AiSkyScreen"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "radarSpot"
    }
    #endif

    /// Precip-style "rain totals anywhere on the map": touch and hold to inspect a spot.
    private func dropSpot(at coordinate: CLLocationCoordinate2D) {
        let dropped = RadarSpot(coordinate: coordinate)
        spotHintSeen = true
        withAnimation { spot = dropped }
        Task {
            let resolved = await dropped.resolvingPlace()
            if spot?.id == dropped.id {
                spot = resolved
            }
        }
    }

    private func reloadIfSourceChanged(for coordinate: CLLocationCoordinate2D) async {
        guard model.settings.radarSource == .automatic else { return }
        let resolved = RadarService.resolve(.automatic, latitude: coordinate.latitude, longitude: coordinate.longitude)
        if resolved != radar.source {
            await radar.load(preference: .automatic, latitude: coordinate.latitude, longitude: coordinate.longitude, force: true)
        }
    }
}

/// Play / scrub controls and the color legend.
private struct RadarControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let radar: RadarViewModel
    let speed: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button {
                    radar.togglePlayback(speed: speed)
                } label: {
                    Image(systemName: radar.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(t.controlTint ?? t.accent)
                        .frame(width: 36, height: 36)
                }
                .disabled(radar.frames.count < 2)
                .accessibilityLabel(radar.isPlaying ? "Pause" : "Play")

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeLabel)
                        .font(t.look == .liquid ? .headline.monospacedDigit() : t.font(.textStrong, 17).monospacedDigit())
                    Text(relativeLabel)
                        .font(t.look == .liquid ? .caption : t.font(.text, 12))
                        .foregroundStyle(t.ink2)
                }
                Spacer()
                if radar.isLoading {
                    ProgressView()
                }
                Button("Now") { radar.showLatest() }
                    .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 15))
                    .foregroundStyle(t.controlTint ?? t.accent)
                    .disabled(radar.frames.isEmpty)
            }

            if radar.frames.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(radar.frameIndex) },
                        set: { newValue in
                            radar.pause()
                            radar.frameIndex = Int(newValue.rounded())
                        }
                    ),
                    in: 0...Double(radar.frames.count - 1),
                    step: 1
                )
            }

            RadarLegend(source: radar.source)
        }
        .foregroundStyle(t.ink)
        .padding(14)
        .lookPanel(t, radius: 18)
    }

    private var timeLabel: String {
        guard let frame = radar.currentFrame else { return "Loading radar…" }
        let timeZone = model.selectedLocation?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        return model.formatter.time(frame.time, timeZone: timeZone)
    }

    private var relativeLabel: String {
        guard let frame = radar.currentFrame else { return " " }
        let minutes = Int((frame.time.timeIntervalSinceNow / 60).rounded())
        if frame.isForecast { return "Forecast +\(max(0, minutes)) min" }
        if minutes >= -5 { return "Latest" }
        return "\(-minutes) min ago"
    }
}

/// Reflectivity color scale matching each source's palette.
struct RadarLegend: View {
    @Environment(\.lookTokens) private var t
    let source: RadarSource

    var body: some View {
        VStack(spacing: 3) {
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            HStack {
                Text("Light")
                Spacer()
                Text("Moderate")
                Spacer()
                Text("Heavy")
                Spacer()
                Text("Extreme")
            }
            .font(t.look == .liquid ? .system(size: 9, weight: .medium) : t.font(.label, 9, fixed: true))
            .foregroundStyle(t.ink2)
            Link(source.attribution, destination: source.attributionURL)
                .font(t.look == .liquid ? .system(size: 9) : t.font(.text, 9, fixed: true))
                .foregroundStyle(t.ink2)
        }
    }

    private var colors: [Color] {
        switch source {
        case .noaa:
            // NWS reflectivity: greens → yellow → red → magenta.
            return [0x04E9E7, 0x019FF4, 0x02FD02, 0x01C501, 0xFDF802, 0xFD9500, 0xFD0000, 0xBC0000, 0xF800FD].map(Color.init(hex:))
        case .rainViewer:
            // RainViewer "Universal Blue".
            return [0x88DDEE, 0x0099CC, 0x0077AA, 0x005588, 0xFFEE00, 0xFFAA00, 0xFF4400, 0xC10000, 0xFFAAFF].map(Color.init(hex:))
        }
    }
}

private extension Image {
    func mapButtonStyle(_ t: LookTokens) -> some View {
        self
            .font(.body.weight(.semibold))
            .foregroundStyle(t.look == .liquid ? Color.primary : t.ink)
            .frame(width: 44, height: 44)
            .lookPanel(t, radius: 12)
    }
}
