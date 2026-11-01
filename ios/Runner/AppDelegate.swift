import Flutter
import UIKit
import MapKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let shareChannel = FlutterMethodChannel(name: "cue/shared", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    shareChannel.setMethodCallHandler { call, result in
      guard call.method == "takeSharedFile" else { result(FlutterMethodNotImplemented); return }
      let defaults = UserDefaults(suiteName: "group.com.hanoo.cue")
      let path = defaults?.string(forKey: "pendingSharePath")
      defaults?.removeObject(forKey: "pendingSharePath")
      result(path)
    }
    let routeChannel = FlutterMethodChannel(name: "cue/routes", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    routeChannel.setMethodCallHandler { call, result in
      if call.method == "geocode",
         let args = call.arguments as? [String: Any],
         let place = args["place"] as? String {
        CLGeocoder().geocodeAddressString(place) { marks, error in
          guard error == nil, let coordinate = marks?.first?.location?.coordinate else {
            result(FlutterError(code: "GEOCODE", message: "장소를 지도에서 찾지 못했어요.", details: nil))
            return
          }
          result(["latitude": coordinate.latitude, "longitude": coordinate.longitude])
        }
        return
      }
      if call.method == "snapshot",
         let args = call.arguments as? [String: Any],
         let latitude = args["latitude"] as? Double,
         let longitude = args["longitude"] as? Double,
         let width = args["width"] as? Double,
         let height = args["height"] as? Double {
        self.snapshot(latitude: latitude, longitude: longitude, size: CGSize(width: width, height: height),
                      dark: args["dark"] as? Bool ?? false, pin: UInt32(args["pin"] as? Int ?? 0xFF2F5BEA), result: result)
        return
      }
      guard call.method == "estimateTravel",
            let args = call.arguments as? [String: Any],
            let from = args["from"] as? String,
            let to = args["to"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let departure = (args["departureAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
      self.estimateTravel(from: from, to: to, departure: departure, result: result)
    }
  }

  // 행사 장소 주변 지도를 이미지로 그리고 가운데에 앱 색 핀을 얹는다. 지도 자체는 Apple 지도를 쓴다.
  private func snapshot(latitude: Double, longitude: Double, size: CGSize, dark: Bool, pin: UInt32, result: @escaping FlutterResult) {
    let options = MKMapSnapshotter.Options()
    let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    options.region = MKCoordinateRegion(center: center, latitudinalMeters: 900, longitudinalMeters: 900)
    options.size = size
    options.scale = UIScreen.main.scale
    options.pointOfInterestFilter = .includingAll
    options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    MKMapSnapshotter(options: options).start { snapshot, error in
      guard let snapshot = snapshot, error == nil else {
        result(FlutterError(code: "SNAPSHOT", message: "지도를 그리지 못했어요.", details: nil))
        return
      }
      let color = UIColor(red: CGFloat((pin >> 16) & 0xFF) / 255, green: CGFloat((pin >> 8) & 0xFF) / 255,
                          blue: CGFloat(pin & 0xFF) / 255, alpha: 1)
      let image = UIGraphicsImageRenderer(size: size, format: {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        return format
      }()).image { _ in
        snapshot.image.draw(at: .zero)
        let point = snapshot.point(for: center)
        UIColor.black.withAlphaComponent(0.18).setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 7, width: 18, height: 18)).fill()
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)).fill()
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - 7.5, y: point.y - 7.5, width: 15, height: 15)).fill()
      }
      guard let data = image.pngData() else {
        result(FlutterError(code: "SNAPSHOT", message: "지도를 그리지 못했어요.", details: nil))
        return
      }
      result(FlutterStandardTypedData(bytes: data))
    }
  }

  private func estimateTravel(from: String, to: String, departure: Date, result: @escaping FlutterResult) {
    let geocoder = CLGeocoder()
    geocoder.geocodeAddressString(from) { fromMarks, fromError in
      guard fromError == nil, let source = fromMarks?.first?.location else {
        result(FlutterError(code: "GEOCODE_FROM", message: "출발지를 지도에서 찾지 못했어요.", details: nil))
        return
      }
      geocoder.geocodeAddressString(to) { toMarks, toError in
        guard toError == nil, let destination = toMarks?.first?.location else {
          result(FlutterError(code: "GEOCODE_TO", message: "도착지를 지도에서 찾지 못했어요.", details: nil))
          return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.departureDate = departure
        request.transportType = .transit
        MKDirections(request: request).calculateETA { response, error in
          guard error == nil, let response else {
            result(FlutterError(code: "NO_ROUTE", message: "대중교통 경로를 계산하지 못했어요.", details: nil))
            return
          }
          result([
            "minutes": Int(ceil(response.expectedTravelTime / 60.0)),
            "distanceMeters": Int(response.distance)
          ])
        }
      }
    }
  }
}
