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
  });
}
