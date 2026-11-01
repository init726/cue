import 'package:cue/cue_map_page.dart';
import 'package:cue/cue_upcoming.dart';
import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> event(String title, String venue, int hour, double? latitude) => {
  'title': title, 'venue': venue,
  'startsAt': DateTime(2026, 11, 14, hour).toUtc().toIso8601String(),
  'endsAt': DateTime(2026, 11, 14, hour + 1).toUtc().toIso8601String(),
  'locationLatitude': latitude, 'locationLongitude': latitude == null ? null : 126.97,
};

void main() {
  test('only events with a known position go on the map', () {
    expect(CueMapStop.from(event('a', 'x', 10, 37.56))?.latitude, 37.56);
    expect(CueMapStop.from(event('b', 'y', 11, null)), isNull);
  });

  testWidgets('a day route shows numbered stop cards that page through with directions and map app', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stops = [event('전시 관람', '서울시립미술관', 14, 37.564), event('저녁 공연', '세종문화회관', 19, 37.572)]
        .map(CueMapStop.from).whereType<CueMapStop>().toList();
    final directions = <String>[], external = <String>[];
    await tester.pumpWidget(MaterialApp(theme: cueTheme(Brightness.light), home: CueMapPage(
      title: '11월 14일 동선',
      stops: stops,
      route: true,
      onDirections: (stop) => directions.add(stop.title),
      onOpenExternal: (stop) => external.add(stop.title),
      weatherFor: (stop) async => const CueWeather(available: true, temperature: 12, label: '맑음', icon: 'clear'),
    )));
    await tester.pump();
    expect(find.text('11월 14일 동선'), findsOneWidget);
    expect(find.text('전시 관람'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('맑음 12°'), findsWidgets);
    expect(find.byTooltip('전체 보기'), findsOneWidget);
    await tester.tap(find.text('길찾기').first);
    expect(directions, ['전시 관람']);
    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도 앱').last);
    expect(external, ['저녁 공연']);
  });
}
