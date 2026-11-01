import 'package:geolocator/geolocator.dart';

/// 추천에 쓸 대략적인 현재 위치. 동네를 알아낼 만큼만(약 100m) 읽고, 서버에는 약 1km 단위로 저장된다.
class CueLocator {
  const CueLocator();

  /// ask가 false면 이미 허용된 경우에만 읽고 권한을 묻지 않는다(앱을 열 때 조용히 갱신할 때).
  Future<({double latitude, double longitude})?> current({bool ask = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && ask) permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return null;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)),
      );
      double rounded(double value) => (value * 1000).round() / 1000;
      return (latitude: rounded(position.latitude), longitude: rounded(position.longitude));
    } catch (_) {
      return null;
    }
  }

  /// 권한을 영구히 거절한 경우 설정 앱으로 안내한다.
  Future<bool> deniedForever() async {
    try {
      return await Geolocator.checkPermission() == LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
}
