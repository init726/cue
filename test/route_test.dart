import 'package:cue/cue_route.dart';
import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> event(String id, String start, String end, {String venue = '서울시립미술관', String description = ''}) => {
  'id': id,
  'title': '행사 $id',
  'venue': venue,
  'category': '전시',
  'startsAt': DateTime.parse(start).toUtc().toIso8601String(),
  'endsAt': DateTime.parse(end).toUtc().toIso8601String(),
  'description': description,
};

void main() {
  final now = DateTime(2026, 10, 24, 12);
  final events = [
    event('a', '2026-10-24T14:00:00', '2026-10-24T16:00:00'),
    event('b', '2026-10-24T16:10:00', '2026-10-24T17:00:00', venue: '국립현대미술관'),
    event('c', '2026-10-24T17:00:00', '2026-10-24T18:00:00', venue: '국립현대미술관'),
    event('d', '2026-10-25T15:00:00', '2026-10-25T17:00:00', venue: '예술의전당'),
    event('e', '2026-10-25T16:00:00', '2026-10-25T18:00:00', venue: '세종문화회관',
        description: '추천 방문 시간 14:00~16:00'),
    event('old', '2026-10-01T10:00:00', '2026-10-01T11:00:00'),
  ];

  test('stops group by day, overlaps become forks and gaps are judged', () {
    final days = buildRoute(events);
    expect(days.map((day) => day.date), [DateTime(2026, 10, 1), DateTime(2026, 10, 24), DateTime(2026, 10, 25)]);
    final saturday = days[1];
    expect(saturday.clusters.every((cluster) => !cluster.fork), isTrue);
    expect(saturday.links.map((link) => link.kind), [LinkKind.tight, LinkKind.sameVenue]);
    expect(saturday.links.first.gap, const Duration(minutes: 10));
    final sunday = days[2];
    expect(sunday.clusters.single.fork, isTrue);
    expect(sunday.clusters.single.end, DateTime(2026, 10, 25, 18));
    expect(sunday.stops.last.flexible, isTrue);
  });

  test('next cue is the first stop that has not ended', () {
    final days = buildRoute(events);
    final next = nextCue(days, now)!;
    expect(next.stop.id, 'a');
    expect(next.inProgress, isFalse);
    expect(next.remaining, 4);
    expect(nextCue(days, DateTime(2026, 10, 24, 15))!.inProgress, isTrue);
    expect(countdown(DateTime(2026, 10, 24, 14), now), '2시간 후');
    expect(countdown(DateTime(2026, 10, 25, 15), now), '내일 15:00');
    expect(countdown(DateTime(2026, 10, 28, 15), now), '4일 후');
    expect(nextCue(days, DateTime(2027)), isNull);
  });

  testWidgets('route view draws the day line on a phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final edited = <String>[];
    final kept = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: RouteView(events: events, now: now, onEdit: (e) => edited.add(e['id']), onCancel: (_) {},
              onKeep: (keep, drop) => kept.addAll([keep['id'], for (final e in drop) '-${e['id']}'])),
        ),
      ),
    ));
    expect(find.text('NEXT CUE · 2시간 후'), findsOneWidget);
    expect(find.text('이어서 큐 4개가 더 있어요'), findsOneWidget);
    expect(find.text('간격 10분 · 이동이 빠듯해요'), findsOneWidget);
    expect(find.text('같은 장소에서 바로 이어져요'), findsOneWidget);
    expect(find.textContaining('시간이 겹쳐요'), findsOneWidget);
    expect(find.text('방문 시간 조정 가능'), findsOneWidget);
    expect(find.text('A길'), findsOneWidget);
    expect(find.text('B길'), findsOneWidget);
    expect(find.text('지난 일정 1개'), findsOneWidget);
    await tester.ensureVisible(find.text('B길로 가기'));
    await tester.tap(find.text('B길로 가기'));
    expect(kept, ['e', '-d']);
    await tester.ensureVisible(find.text('행사 b'));
    await tester.tap(find.text('행사 b'));
    await tester.pump();
    await tester.ensureVisible(find.text('수정'));
    await tester.tap(find.text('수정'));
    expect(edited, ['b']);
  });
}
