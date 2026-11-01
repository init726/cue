import 'package:cue/cue_period.dart';
import 'package:cue/cue_period_planner.dart';
import 'package:cue/cue_schedule_agent.dart';
import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CueScheduleItem busy(String title, DateTime start, DateTime end) =>
    CueScheduleItem(id: title, title: title, venue: '', start: start, end: end);

void main() {
  // 2026-11-02는 월요일이다.
  final now = DateTime(2026, 11, 2, 9);
  final exhibition = CuePeriod.fromJson({
    'startDate': '2026-11-01',
    'endDate': '2027-02-28',
    'venue': '서울시립미술관',
    'hours': [
      {'weekdays': [2, 3, 4, 6, 7], 'open': '10:00', 'close': '18:00', 'lastEntry': '17:30'},
      {'weekdays': [5], 'open': '10:00', 'close': '21:00', 'lastEntry': null},
    ],
    'closedWeekdays': [1],
    'closedDates': ['2027-01-01'],
    'visitMinutes': 90,
  })!;

  test('closed days and days outside the period have no visiting window', () {
    expect(exhibition.windowOn(DateTime(2026, 11, 2)), isNull, reason: '월요일 휴관');
    expect(exhibition.windowOn(DateTime(2027, 1, 1)), isNull, reason: '지정 휴관일');
    expect(exhibition.windowOn(DateTime(2027, 3, 1)), isNull, reason: '기간 밖');
    final friday = exhibition.windowOn(DateTime(2026, 11, 6))!;
    expect(friday.close, DateTime(2026, 11, 6, 21));
    expect(friday.printedLastEntry, isFalse);
    final tuesday = exhibition.windowOn(DateTime(2026, 11, 3))!;
    expect(tuesday.latestStart, DateTime(2026, 11, 3, 17, 30));
    expect(tuesday.printedLastEntry, isTrue);
  });

  test('a visit is placed near 2pm around existing plans and stays inside opening hours', () {
    final day = DateTime(2026, 11, 3);
    final lunch = busy('점심 약속', DateTime(2026, 11, 3, 12), DateTime(2026, 11, 3, 15));
    final slot = cueBestVisitOn(exhibition, day, [lunch], now: now)!;
    expect(slot.start, DateTime(2026, 11, 3, 15, 30));
    expect(slot.end, DateTime(2026, 11, 3, 17));
    final late = cueClampVisit(exhibition.windowOn(day)!, DateTime(2026, 11, 3, 17, 30), const Duration(minutes: 90));
    expect(late.start, DateTime(2026, 11, 3, 16, 30), reason: '머무는 시간이 문 닫기 전에 끝나도록 당긴다');
    expect(late.end, DateTime(2026, 11, 3, 18));
  });

  test('quick picks are the earliest free day, the nearest weekend and the last weekend', () {
    final picks = cueSuggestVisits(exhibition, [
      busy('하루 종일 수업', DateTime(2026, 11, 3, 9), DateTime(2026, 11, 3, 20)),
    ], now: now);
    expect(picks.map((pick) => pick.label), ['가장 빠른 빈 날', '이번 주말', '끝나기 전 마지막 주말']);
    expect(picks[0].slot.start, DateTime(2026, 11, 4, 14));
    expect(picks[1].slot.start, DateTime(2026, 11, 7, 14));
    expect(picks[2].slot.start, DateTime(2027, 2, 28, 14));
  });

  test('unknown opening hours fall back to daytime and the note says to check', () {
    final popup = CuePeriod.fromJson({
      'startDate': '2026-11-05', 'endDate': '2026-11-12', 'venue': '성수 S팩토리', 'visitMinutes': 45,
    })!;
    expect(popup.windowOn(DateTime(2026, 11, 5))!.known, isFalse);
    final note = cuePeriodNote(popup, CueTimeSlot(DateTime(2026, 11, 5, 14), DateTime(2026, 11, 5, 14, 45)));
    expect(note, contains('추천 방문 시간 14:00–14:45'));
    expect(note, contains('방문 전에 확인'));
    expect(cuePeriodNote(exhibition, CueTimeSlot(DateTime(2026, 11, 3, 14), DateTime(2026, 11, 3, 15, 30))),
        allOf(contains('화–일 10:00–18:00 (금 ~21:00)'), contains('입장 마감 17:30'), contains('휴관 월요일')));
  });

  testWidgets('long periods use a month calendar and confirm only the visit time', (tester) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CueTimeSlot? confirmed;
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: CuePeriodPlanner(
          period: exhibition,
          busy: [busy('점심 약속', DateTime(2026, 11, 4, 12), DateTime(2026, 11, 4, 15))],
          now: now,
          onConfirm: (slot) => confirmed = slot,
        ),
      )),
    ));
    expect(find.text('2026년 11월'), findsOneWidget);
    expect(find.text('가장 빠른 빈 날'), findsOneWidget);
    expect(find.text('14:00 – 15:30'), findsOneWidget, reason: '첫 추천(11.3 화)이 미리 선택된다');
    await tester.tap(find.text('4'));
    await tester.pump();
    expect(find.text('15:30 – 17:00'), findsOneWidget, reason: '점심 약속을 피해 놓는다');
    await tester.tap(find.text('2시간'));
    await tester.pump();
    expect(find.text('15:30 – 17:30'), findsOneWidget);
    await tester.tap(find.byTooltip('30분 앞으로'));
    await tester.pump();
    expect(find.textContaining('겹쳐요'), findsNothing, reason: '15:00 시작은 점심 약속이 끝난 뒤다');
    await tester.tap(find.byTooltip('30분 앞으로'));
    await tester.pump();
    expect(find.textContaining('점심 약속과(와) 겹쳐요'), findsOneWidget);
    await tester.tap(find.byTooltip('30분 뒤로'));
    await tester.pump();
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pump();
    expect(find.text('2026년 12월'), findsOneWidget);
    await tester.tap(find.text('11.4 (수) 15:00에 가기'));
    expect(confirmed!.start, DateTime(2026, 11, 4, 15));
    expect(confirmed!.end, DateTime(2026, 11, 4, 17));
  });

  testWidgets('short periods use a day strip', (tester) async {
    tester.view.physicalSize = const Size(393, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final popup = CuePeriod.fromJson({
      'startDate': '2026-11-05', 'endDate': '2026-11-12', 'venue': '성수 S팩토리', 'visitMinutes': 45,
      'hours': [{'weekdays': [1, 2, 3, 4, 5, 6, 7], 'open': '11:00', 'close': '20:00'}],
    })!;
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: CuePeriodPlanner(period: popup, busy: const [], now: now, onConfirm: (_) {}),
      )),
    ));
    expect(find.textContaining('년'), findsNothing);
    expect(find.text('목'), findsWidgets);
    expect(find.text('45분'), findsOneWidget);
    expect(find.text('11.5 (목) 14:00에 가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
