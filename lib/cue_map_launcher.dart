import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// 지도를 열 앱. web은 앱이 하나도 없을 때 쓰는 카카오맵 웹이다.
enum CueMapApp { kakao, naver, apple, web }

extension CueMapAppLabel on CueMapApp {
  String get label => switch (this) {
    CueMapApp.kakao => '카카오맵',
    CueMapApp.naver => '네이버 지도',
    CueMapApp.apple => 'Apple 지도',
    CueMapApp.web => '웹 브라우저',
  };

  static CueMapApp? parse(String? value) =>
      CueMapApp.values.where((app) => app.name == value).firstOrNull;
}

/// 지도에 띄울 대상. 좌표가 없으면 이름으로 검색한다.
class CueMapTarget {
  const CueMapTarget({required this.name, this.latitude, this.longitude, this.kakaoPlaceId});

  final String name;
  final double? latitude;
  final double? longitude;
  final String? kakaoPlaceId;

  bool get hasPoint => latitude != null && longitude != null;
}

const _appName = 'com.hanoo.cue';

/// 앱마다 장소 보기(directions=false)와 대중교통 길찾기(directions=true) 주소를 만든다.
Uri cueMapLink(CueMapApp app, CueMapTarget target, {bool directions = false}) {
  final name = target.name.trim().isEmpty ? '목적지' : target.name.trim();
  final point = target.hasPoint ? '${target.latitude},${target.longitude}' : null;
  switch (app) {
    case CueMapApp.kakao:
      if (directions && point != null) return Uri.parse('kakaomap://route?ep=$point&by=PUBLICTRANSIT');
      if (target.kakaoPlaceId != null) return Uri.parse('kakaomap://place?id=${target.kakaoPlaceId}');
      if (point != null) return Uri.parse('kakaomap://look?p=$point');
      return Uri.parse('kakaomap://search?q=${Uri.encodeQueryComponent(name)}');
    case CueMapApp.naver:
      if (directions && point != null) {
        return Uri.parse('nmap://route/public?dlat=${target.latitude}&dlng=${target.longitude}'
            '&dname=${Uri.encodeQueryComponent(name)}&appname=$_appName');
      }
      if (point != null) {
        return Uri.parse('nmap://place?lat=${target.latitude}&lng=${target.longitude}'
            '&name=${Uri.encodeQueryComponent(name)}&appname=$_appName');
      }
      return Uri.parse('nmap://search?query=${Uri.encodeQueryComponent(name)}&appname=$_appName');
    case CueMapApp.apple:
      if (directions && point != null) return Uri.https('maps.apple.com', '/', {'daddr': point, 'dirflg': 'r'});
      if (point != null) return Uri.https('maps.apple.com', '/', {'ll': point, 'q': name});
      return Uri.https('maps.apple.com', '/', {'q': name});
    case CueMapApp.web:
      if (directions && point != null) {
        return Uri.parse('https://map.kakao.com/link/to/${Uri.encodeComponent(name.replaceAll(',', ' '))},$point');
      }
      if (target.kakaoPlaceId != null) return Uri.parse('https://place.map.kakao.com/${target.kakaoPlaceId}');
      return Uri.https('map.kakao.com', '/', {'q': name});
  }
}

/// 이 기기에서 열 수 있는 지도 앱. Apple 지도는 iOS에 항상 있다. 웹은 늘 마지막에 둔다.
Future<List<CueMapApp>> cueInstalledMapApps() async {
  Future<bool> can(String scheme) async {
    try {
      return await canLaunchUrl(Uri.parse('$scheme://'));
    } catch (_) {
      return false;
    }
  }

  return [
    if (await can('kakaomap')) CueMapApp.kakao,
    if (await can('nmap')) CueMapApp.naver,
    if (Platform.isIOS) CueMapApp.apple,
    CueMapApp.web,
  ];
}

/// 고른 앱으로 연다. 앱이 열리지 않으면 웹으로 다시 시도한다.
Future<bool> cueLaunchMap(CueMapApp app, CueMapTarget target, {bool directions = false}) async {
  final mode = app == CueMapApp.web ? LaunchMode.externalApplication : LaunchMode.externalNonBrowserApplication;
  try {
    if (await launchUrl(cueMapLink(app, target, directions: directions), mode: mode)) return true;
  } catch (_) {
    // 앱이 지워졌거나 주소를 처리하지 못하면 웹으로 넘어간다.
  }
  if (app == CueMapApp.web) return false;
  return launchUrl(cueMapLink(CueMapApp.web, target, directions: directions), mode: LaunchMode.externalApplication);
}
