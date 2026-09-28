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

/// MKMapView wrapper (SwiftUI's `Map` can't host tile overlays) that animates radar frames by
/// keeping every frame's overlay loaded and only showing the current one.
struct RadarMapView: UIViewRepresentable {
    var frames: [RadarFrame]
    var currentFrameID: String?
    var opacity: Double
    var mapStyle: MapStylePreference
    var pins: [RadarPin]
    var focus: MapFocus?
    var onRegionChange: (CLLocationCoordinate2D) -> Void
    var onSelectPin: (String) -> Void

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
        context.coordinator.apply(style: mapStyle, to: mapView)
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
        coordinator.syncOverlays(frames: frames, on: mapView)
        coordinator.showFrame(id: currentFrameID, opacity: opacity)
        coordinator.syncPins(pins, on: mapView)
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

        var parent: RadarMapView
        var lastFocusID: UUID?
        private var appliedStyle: MapStylePreference?
        private var overlays: [String: RadarTileOverlay] = [:]
        private var renderers: [String: MKTileOverlayRenderer] = [:]
        private var visibleFrameID: String?
        private var visibleOpacity: Double = 0
        private var annotations: [String: PinAnnotation] = [:]

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

        func syncOverlays(frames: [RadarFrame], on mapView: MKMapView) {
            let wanted = Set(frames.map(\.id))
            for (id, overlay) in overlays where !wanted.contains(id) {
                mapView.removeOverlay(overlay)
                overlays[id] = nil
                renderers[id] = nil
            }
            for frame in frames where overlays[frame.id] == nil {
                let overlay = RadarTileOverlay(frame: frame)
                overlays[frame.id] = overlay
                mapView.addOverlay(overlay, level: .aboveRoads)
            }
        }

        func showFrame(id: String?, opacity: Double) {
            guard id != visibleFrameID || opacity != visibleOpacity else { return }
            // Show the new frame before hiding the old one to avoid a flash of empty map.
            if let id, let renderer = renderers[id] {
                renderer.alpha = opacity
                renderer.setNeedsDisplay()
            }
            if let previous = visibleFrameID, previous != id, let renderer = renderers[previous] {
                renderer.alpha = 0
                renderer.setNeedsDisplay()
            }
            visibleFrameID = id
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

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? RadarTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
            renderer.alpha = tileOverlay.frame.id == visibleFrameID ? visibleOpacity : 0
            renderers[tileOverlay.frame.id] = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.centerCoordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
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
