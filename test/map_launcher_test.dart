import 'package:cue/cue_map_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const place = CueMapTarget(name: '덕수궁돌담길', latitude: 37.5658, longitude: 126.9751, kakaoPlaceId: '8217196');
  const typed = CueMapTarget(name: '우리 동네 책방');

  test('each map app opens the place, its point, or a search', () {
    expect(cueMapLink(CueMapApp.kakao, place).toString(), 'kakaomap://place?id=8217196');
    expect(cueMapLink(CueMapApp.kakao, const CueMapTarget(name: 'x', latitude: 1, longitude: 2)).toString(),
        'kakaomap://look?p=1.0,2.0');
    expect(cueMapLink(CueMapApp.kakao, typed).toString(), startsWith('kakaomap://search?q='));
    expect(cueMapLink(CueMapApp.naver, place).toString(), contains('nmap://place?lat=37.5658&lng=126.9751'));
    expect(cueMapLink(CueMapApp.naver, place).toString(), contains('appname=com.hanoo.cue'));
    expect(cueMapLink(CueMapApp.apple, place).queryParameters, {'ll': '37.5658,126.9751', 'q': '덕수궁돌담길'});
    expect(cueMapLink(CueMapApp.web, place).toString(), 'https://place.map.kakao.com/8217196');
    expect(cueMapLink(CueMapApp.web, typed).host, 'map.kakao.com');
  });

  test('directions start from the current position by public transit', () {
    expect(cueMapLink(CueMapApp.kakao, place, directions: true).toString(),
        'kakaomap://route?ep=37.5658,126.9751&by=PUBLICTRANSIT');
    expect(cueMapLink(CueMapApp.naver, place, directions: true).toString(), startsWith('nmap://route/public?dlat=37.5658'));
    expect(cueMapLink(CueMapApp.apple, place, directions: true).queryParameters, {'daddr': '37.5658,126.9751', 'dirflg': 'r'});
    expect(cueMapLink(CueMapApp.web, place, directions: true).toString(),
        startsWith('https://map.kakao.com/link/to/'));
    expect(CueMapAppLabel.parse('naver'), CueMapApp.naver);
    expect(CueMapAppLabel.parse('unknown'), isNull);
  });
}
