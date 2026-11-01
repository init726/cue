import 'package:cue/cue_upcoming.dart';
import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(theme: cueTheme(Brightness.light),
    home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: child)));

void main() {
  final event = {
    'title': '덕수궁 야간 국악 산책',
    'venue': '덕수궁돌담길',
    'startsAt': DateTime(2026, 11, 14, 19).toUtc().toIso8601String(),
    'endsAt': DateTime(2026, 11, 14, 21).toUtc().toIso8601String(),
    'locationLatitude': 37.5658,
    'locationLongitude': 126.9751,
  };

  testWidgets('the next event shows when, where, a map, its weather and directions', (tester) async {
    var directions = 0, schedule = 0;
    await tester.pumpWidget(host(CueUpcomingCard(
      event: event,
      now: DateTime(2026, 11, 11, 9),
      moreCount: 2,
      weather: Future.value(CueWeather.fromJson({'available': true, 'temperature': 11, 'label': '비', 'icon': 'rain',
        'precipitationProbability': 60})),
      onOpenMap: () {},
      onDirections: () => directions++,
      onOpenSchedule: () => schedule++,
    )));
    await tester.pump();
    expect(find.text('3일 후 · 11.14 (토) 19:00'), findsOneWidget);
    expect(find.text('비 11° · 강수 60%'), findsOneWidget);
    expect(find.byType(CueMapSnapshot), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('지도에서 보기'), findsOneWidget, reason: '테스트에는 지도 채널이 없어 안내로 대신한다');
    await tester.tap(find.text('길찾기'));
    await tester.tap(find.text('이후 2개 더보기'));
    expect([directions, schedule], [1, 1]);
  });

  testWidgets('far-off events explain when weather appears and unknown venues offer a map search', (tester) async {
    await tester.pumpWidget(host(CueUpcomingCard(
      event: {...event, 'locationLatitude': null, 'locationLongitude': null},
      now: DateTime(2026, 11, 14, 20),
      weather: null,
      onOpenMap: () {},
      onDirections: null,
      onOpenSchedule: () {},
    )));
    expect(find.textContaining('진행 중'), findsOneWidget);
    expect(find.text('장소 위치를 아직 몰라요. 지도에서 찾아볼까요?'), findsOneWidget);
    expect(find.text('길찾기'), findsNothing);
    await tester.pumpWidget(host(CueUpcomingCard(
      event: event, now: DateTime(2026, 10, 1), weather: Future.value(const CueWeather(available: false)),
      onOpenMap: () {}, onDirections: () {}, onOpenSchedule: () {})));
    await tester.pump();
    expect(find.text('날씨는 2주 전부터 보여드려요'), findsOneWidget);
  });

  testWidgets('without plans the card shows today in the activity area', (tester) async {
    await tester.pumpWidget(host(CueTodayCard(region: '서울 중구 명동',
        weather: Future.value(const CueWeather(available: true, temperature: 14, label: '맑음', icon: 'clear')),
        onUseLocation: () {})));
    await tester.pump();
    expect(find.text('서울 중구 명동 · 맑음 14°'), findsOneWidget);
  });
}
