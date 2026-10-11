import AiSkyKit
import MapKit
import SwiftUI
import UIKit

/// A saved place shown on the radar map.
struct RadarPin: Identifiable, Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let temperatureText: String?
    let tintHex: UInt32

    static func == (lhs: RadarPin, rhs: RadarPin) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.temperatureText == rhs.temperatureText
            && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// A request to move the map; a new `id` triggers the move.
struct MapFocus: Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let span: Double

    static func == (lhs: MapFocus, rhs: MapFocus) -> Bool { lhs.id == rhs.id }
}

/// MKMapView wrapper (SwiftUI's `Map` can't host custom overlays) with one radar overlay that
/// draws the current frame from `RadarTileStore`.
struct RadarMapView: UIViewRepresentable {
    var store: RadarTileStore
    var frames: [RadarFrame]
    var currentFrame: RadarFrame?
    var currentIndex: Int
    var opacity: Double
    var mapStyle: MapStylePreference
    var pins: [RadarPin]
    var focus: MapFocus?
    /// A touched-and-held spot, shown with its own marker.
    var spot: CLLocationCoordinate2D?
    var onRegionChange: (CLLocationCoordinate2D) -> Void
    var onSelectPin: (String) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinReuseID)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.spotReuseID)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        mapView.addGestureRecognizer(longPress)
        context.coordinator.apply(style: mapStyle, to: mapView)
        context.coordinator.installRadar(on: mapView)
        if let focus {
            mapView.setRegion(Self.region(for: focus), animated: false)
            context.coordinator.lastFocusID = focus.id
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.apply(style: mapStyle, to: mapView)
        coordinator.showFrame(currentFrame, opacity: opacity)
        store.setFrames(frames, currentIndex: currentIndex)
        coordinator.syncPins(pins, on: mapView)
        coordinator.syncSpot(spot, on: mapView)
        if let focus, focus.id != coordinator.lastFocusID {
            coordinator.lastFocusID = focus.id
            mapView.setRegion(Self.region(for: focus), animated: true)
        }
    }

    static func region(for focus: MapFocus) -> MKCoordinateRegion {
        MKCoordinateRegion(center: focus.coordinate, span: MKCoordinateSpan(latitudeDelta: focus.span, longitudeDelta: focus.span))
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pinReuseID = "pin"
        static let spotReuseID = "spot"

        var parent: RadarMapView
        var lastFocusID: UUID?
        private var appliedStyle: MapStylePreference?
        private let radarOverlay = RadarOverlay()
        private var radarRenderer: RadarOverlayRenderer?
        private var visibleFrame: RadarFrame?
        private var visibleOpacity: Double = 0
        private var annotations: [String: PinAnnotation] = [:]
        private var spotAnnotation: MKPointAnnotation?

        init(parent: RadarMapView) {
            self.parent = parent
        }

        func apply(style: MapStylePreference, to mapView: MKMapView) {
            guard style != appliedStyle else { return }
            appliedStyle = style
            switch style {
            case .muted:
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            case .standard:
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            case .hybrid:
                mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            case .satellite:
                mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
            }
        }

        /// Adds the single radar overlay, under the map's labels, and routes tile arrivals to its renderer.
        func installRadar(on mapView: MKMapView) {
            mapView.addOverlay(radarOverlay, level: .aboveRoads)
            parent.store.onTileLoaded = { [weak self] frameID, key in
                self?.radarRenderer?.tileDidLoad(frameID: frameID, key: key)
            }
        }

        func showFrame(_ frame: RadarFrame?, opacity: Double) {
            guard frame != visibleFrame || opacity != visibleOpacity else { return }
            visibleFrame = frame
            if let radarRenderer {
                if radarRenderer.alpha != opacity {
                    radarRenderer.alpha = opacity
                    radarRenderer.setNeedsDisplay()
                }
                radarRenderer.show(frame)
            }
            visibleOpacity = opacity
        }

        func syncPins(_ pins: [RadarPin], on mapView: MKMapView) {
            let wanted = Set(pins.map(\.id))
            for (id, annotation) in annotations where !wanted.contains(id) {
                mapView.removeAnnotation(annotation)
                annotations[id] = nil
            }
            for pin in pins {
                if let existing = annotations[pin.id] {
                    if existing.pin != pin {
                        mapView.removeAnnotation(existing)
                        let replacement = PinAnnotation(pin: pin)
                        annotations[pin.id] = replacement
                        mapView.addAnnotation(replacement)
                    }
                } else {
                    let annotation = PinAnnotation(pin: pin)
                    annotations[pin.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        func syncSpot(_ coordinate: CLLocationCoordinate2D?, on mapView: MKMapView) {
            guard let coordinate else {
                if let spotAnnotation {
                    mapView.removeAnnotation(spotAnnotation)
                    self.spotAnnotation = nil
                }
                return
            }
            if let spotAnnotation {
                if spotAnnotation.coordinate.latitude != coordinate.latitude || spotAnnotation.coordinate.longitude != coordinate.longitude {
                    spotAnnotation.coordinate = coordinate
                }
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                spotAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            parent.onLongPress(mapView.convert(point, toCoordinateFrom: mapView))
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let radarOverlay = overlay as? RadarOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = RadarOverlayRenderer(overlay: radarOverlay, store: parent.store)
            renderer.alpha = visibleOpacity
            renderer.show(visibleFrame)
            radarRenderer = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let visible = mapView.visibleMapRect
            parent.store.setVisibleRect(minX: visible.minX, minY: visible.minY, maxX: visible.maxX, maxY: visible.maxY)
            parent.onRegionChange(mapView.centerCoordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation === spotAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.spotReuseID, for: annotation)
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = .systemOrange
                    marker.glyphImage = UIImage(systemName: "drop.fill")
                    marker.displayPriority = .required
                    marker.canShowCallout = false
                    marker.animatesWhenAdded = true
                }
                return view
            }
            guard let annotation = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.pinReuseID, for: annotation)
            if let marker = view as? MKMarkerAnnotationView {
                marker.markerTintColor = UIColor(Palette.color(hex: annotation.pin.tintHex))
                if let text = annotation.pin.temperatureText {
                    marker.glyphText = text
                } else {
                    marker.glyphImage = UIImage(systemName: "mappin")
                }
                marker.titleVisibility = .adaptive
                marker.displayPriority = .required
                marker.canShowCallout = true
                marker.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let annotation = view.annotation as? PinAnnotation {
                parent.onSelectPin(annotation.pin.id)
            }
        }
    }
}

final class PinAnnotation: NSObject, MKAnnotation {
    let pin: RadarPin

    init(pin: RadarPin) {
        self.pin = pin
    }

    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.name }
    var subtitle: String? { pin.temperatureText.map { "Now \($0)" } }
}
