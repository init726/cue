import Flutter
import MapKit
import UIKit

/// 앱 안에서 움직일 수 있는 Apple 지도. 일정 장소에 번호 핀을 꽂고, 하루 동선이면 순서대로 선을 잇는다.
/// 핀을 누르면 Flutter에 몇 번째인지 알리고, Flutter가 고른 핀으로 지도를 옮긴다.
final class CueMapFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    CueMapPlatformView(frame: frame, viewId: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class CueAnnotation: MKPointAnnotation {
  var index = 0
}

private final class CueMapPlatformView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let map: MKMapView
  private let channel: FlutterMethodChannel
  private let tint: UIColor
  private let numbered: Bool
  private let bottomInset: CGFloat
  private var annotations: [CueAnnotation] = []
  private var fitted = false

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    map = MKMapView(frame: frame)
    channel = FlutterMethodChannel(name: "cue/map_\(viewId)", binaryMessenger: messenger)
    let argb = UInt32(truncatingIfNeeded: args["tint"] as? Int ?? 0xFF2F5BEA)
    tint = UIColor(red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                   blue: CGFloat(argb & 0xFF) / 255, alpha: 1)
    let markers = args["markers"] as? [[String: Any]] ?? []
    numbered = markers.count > 1
    bottomInset = CGFloat(args["bottomInset"] as? Double ?? 0)
    super.init()
    map.delegate = self
    map.pointOfInterestFilter = .includingAll
    map.showsCompass = true
    map.showsScale = true
    // 위쪽 제목 줄과 아래 카드에 가리지 않도록 지도 여백을 준다. Apple 로고·법적 고지도 카드 위로 올라온다.
    map.layoutMargins = UIEdgeInsets(top: 70, left: 8, bottom: bottomInset, right: 8)
    let status = CLLocationManager().authorizationStatus
    map.showsUserLocation = status == .authorizedWhenInUse || status == .authorizedAlways
    for (index, marker) in markers.enumerated() {
      guard let latitude = marker["latitude"] as? Double, let longitude = marker["longitude"] as? Double else { continue }
      let annotation = CueAnnotation()
      annotation.index = index
      annotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      annotation.title = marker["title"] as? String
      annotation.subtitle = marker["subtitle"] as? String
      annotations.append(annotation)
    }
    map.addAnnotations(annotations)
    if args["route"] as? Bool == true, annotations.count > 1 {
      var coordinates = annotations.map(\.coordinate)
      map.addOverlay(MKPolyline(coordinates: &coordinates, count: coordinates.count))
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "select":
        if let index = call.arguments as? Int, let annotation = self.annotations.first(where: { $0.index == index }) {
          self.map.selectAnnotation(annotation, animated: true)
          self.map.setCenter(annotation.coordinate, animated: true)
        }
        result(nil)
      case "fit":
        self.fit(animated: true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // 화면 크기가 정해진 뒤에 모든 핀이 보이도록 맞춘다.
    DispatchQueue.main.async { [weak self] in
      self?.fit(animated: false)
      if let first = self?.annotations.first(where: { $0.index == args["selected"] as? Int ?? 0 }) {
        self?.map.selectAnnotation(first, animated: false)
      }
    }
  }

  func view() -> UIView { map }

  private func fit(animated: Bool) {
    guard !annotations.isEmpty else { return }
    // layoutMargins가 이미 제목 줄과 아래 카드를 비켜 주므로 핀 둘레 여백만 더한다.
    let padding = UIEdgeInsets(top: 60, left: 48, bottom: 48, right: 48)
    if annotations.count == 1 {
      let region = MKCoordinateRegion(center: annotations[0].coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
      map.setVisibleMapRect(MKMapRect(region), edgePadding: padding, animated: animated)
      return
    }
    let rect = annotations.reduce(MKMapRect.null) { partial, annotation in
      partial.union(MKMapRect(origin: MKMapPoint(annotation.coordinate), size: MKMapSize(width: 1, height: 1)))
    }
    map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    guard let annotation = annotation as? CueAnnotation else { return nil }
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cue") as? MKMarkerAnnotationView
      ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "cue")
    view.annotation = annotation
    view.markerTintColor = tint
    view.glyphText = numbered ? "\(annotation.index + 1)" : nil
    view.glyphImage = numbered ? nil : UIImage(systemName: "star.fill")
    view.displayPriority = .required
    view.titleVisibility = .adaptive
    return view
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let annotation = view.annotation as? CueAnnotation else { return }
    channel.invokeMethod("selected", arguments: annotation.index)
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
    let renderer = MKPolylineRenderer(polyline: line)
    renderer.strokeColor = tint.withAlphaComponent(0.85)
    renderer.lineWidth = 4
    renderer.lineCap = .round
    renderer.lineDashPattern = [1, 9]
    return renderer
  }
}

private extension MKMapRect {
  init(_ region: MKCoordinateRegion) {
    let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                    longitude: region.center.longitude - region.span.longitudeDelta / 2))
    let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                        longitude: region.center.longitude + region.span.longitudeDelta / 2))
    self.init(x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
              width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
  }
}
