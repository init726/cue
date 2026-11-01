import 'package:cue/cue_schedule_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CueScheduleItem item(
    String title,
    String start,
    String end, {
    String venue = '강당',
  }) => CueScheduleItem(
    id: title,
    title: title,
    venue: venue,
    start: DateTime.parse(start),
    end: DateTime.parse(end),
  );

  test('같은 행사와 시간·장소는 중복으로 판단한다', () {
    final saved = item(
      '성남동 커피 페스티벌',
      '2026-11-01 14:00',
      '2026-11-01 16:00',
      venue: '성남동 공원',
    );
    expect(
      cueLooksLikeDuplicate(
        '성남동 커피페스티벌',
        '성남동 공원',
        DateTime(2026, 11, 1, 14),
        DateTime(2026, 11, 1, 16),
        saved,
      ),
      isTrue,
    );
    expect(
      cueLooksLikeDuplicate(
        '2026 성남동 커피 페스티벌',
        '성남동 공원',
        DateTime(2026, 11, 1, 14),
        DateTime(2026, 11, 1, 16),
        saved,
      ),
      isTrue,
    );
    expect(
      cueLooksLikeDuplicate(
        '다른 행사',
        '성남동 공원',
        DateTime(2026, 11, 1, 14),
        DateTime(2026, 11, 1, 16),
        saved,
      ),
      isFalse,
    );
  });

  test('겹친 시간을 피해 가까운 빈 시간을 제안한다', () {
    final busy = [item('기존 일정', '2026-11-01 14:00', '2026-11-01 16:00')];
    final slots = cueNearestFreeSlots(
      DateTime(2026, 11, 1, 14),
      DateTime(2026, 11, 1, 16),
      busy,
      now: DateTime(2026, 10, 31, 9),
    );
    expect(slots, isNotEmpty);
    expect(slots.first.start, DateTime(2026, 11, 1, 16));
    expect(
      slots.every(
        (slot) => !cueSchedulesOverlap(slot.start, slot.end, busy.single),
      ),
      isTrue,
    );
  });

  test('교내 장소는 학교 이름이 없으면 확인한다', () {
    expect(cueVenueNeedsContext('본관 3층 시청각실'), isTrue);
    expect(cueVenueNeedsContext('한국대학교 본관 3층 시청각실'), isFalse);
    expect(cueVenueNeedsContext('서울 코엑스 A홀'), isFalse);
    expect(cueVenueNeedsContext('서울시립미술관 서소문본관 2층'), isFalse);
    expect(cueVenueNeedsContext('국립중앙박물관 별관 강당'), isFalse);
  });

  test('이동 시간과 도착 여유를 포함해 배치 가능성을 판단한다', () {
    final previous = item('수업', '2026-11-01 10:00', '2026-11-01 11:00');
    final next = item('약속', '2026-11-01 14:00', '2026-11-01 15:00');
    final impossible = cueAssessPlacement(
      start: DateTime(2026, 11, 1, 11, 30),
      end: DateTime(2026, 11, 1, 13, 30),
      previous: previous,
      next: next,
      travelFromPreviousMinutes: 25,
      travelToNextMinutes: 40,
      arrivalBufferMinutes: 15,
    );
    expect(impossible.canArrive, isFalse);
    expect(impossible.canReachNext, isFalse);
  });
}
