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
