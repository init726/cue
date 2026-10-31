class CueScheduleItem {
  const CueScheduleItem({
    required this.id,
    required this.title,
    required this.venue,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final String venue;
  final DateTime start;
  final DateTime end;
}

class CueTimeSlot {
  const CueTimeSlot(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

String _plain(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^0-9a-zㄱ-ㆎ가-힣]'), '');

bool cueSchedulesOverlap(DateTime start, DateTime end, CueScheduleItem other) =>
    start.isBefore(other.end) && end.isAfter(other.start);

bool cueLooksLikeDuplicate(
  String title,
  String venue,
  DateTime start,
  DateTime end,
  CueScheduleItem other,
) {
  final leftTitle = _plain(title);
  final rightTitle = _plain(other.title);
  final shorter = leftTitle.length < rightTitle.length ? leftTitle : rightTitle;
  final titlesMatch =
      leftTitle == rightTitle ||
      (shorter.length >= 6 &&
          (leftTitle.contains(rightTitle) || rightTitle.contains(leftTitle)));
  if (leftTitle.isEmpty || !titlesMatch) {
    return false;
  }
  final sameStart =
      start.difference(other.start).abs() <= const Duration(minutes: 10);
  final sameEnd =
      end.difference(other.end).abs() <= const Duration(minutes: 10);
  if (!sameStart || !sameEnd) return false;
  final leftVenue = _plain(venue);
  final rightVenue = _plain(other.venue);
  return leftVenue.isEmpty || rightVenue.isEmpty || leftVenue == rightVenue;
}

/// 같은 날 08:00~22:00 안에서 30분 단위의 가까운 빈 시간을 찾는다.
/// 행사 시간이 고정일 수 있으므로 이 결과는 자동 적용하지 않고 사용자에게 선택지로만 보여준다.
List<CueTimeSlot> cueNearestFreeSlots(
  DateTime preferredStart,
  DateTime preferredEnd,
  List<CueScheduleItem> busy, {
  int count = 3,
  DateTime? now,
}) {
  final duration = preferredEnd.difference(preferredStart);
  if (duration <= Duration.zero || duration > const Duration(hours: 12)) {
    return const [];
  }
  var dayStart = DateTime(
    preferredStart.year,
    preferredStart.month,
    preferredStart.day,
    8,
  );
  final dayEnd = DateTime(
    preferredStart.year,
    preferredStart.month,
    preferredStart.day,
    22,
  );
  final current = now ?? DateTime.now();
  if (current.year == preferredStart.year &&
      current.month == preferredStart.month &&
      current.day == preferredStart.day &&
      current.isAfter(dayStart)) {
    final remainder = current.minute % 30;
    final needsNextHalfHour =
        remainder != 0 || current.second != 0 || current.millisecond != 0;
    dayStart = DateTime(
      current.year,
      current.month,
      current.day,
      current.hour,
      current.minute +
          (needsNextHalfHour ? (remainder == 0 ? 30 : 30 - remainder) : 0),
    );
  }
  final slots = <CueTimeSlot>[];
  for (
    var cursor = dayStart;
    !cursor.add(duration).isAfter(dayEnd);
    cursor = cursor.add(const Duration(minutes: 30))
  ) {
    final end = cursor.add(duration);
    if (cursor == preferredStart) continue;
    if (busy.any((item) => cueSchedulesOverlap(cursor, end, item))) continue;
    slots.add(CueTimeSlot(cursor, end));
  }
  slots.sort((a, b) {
    final aDistance = a.start.difference(preferredStart).abs();
    final bDistance = b.start.difference(preferredStart).abs();
    final distance = aDistance.compareTo(bDistance);
    if (distance != 0) return distance;
    // 같은 거리면 원래 시간 이후를 먼저 제안해 이미 지나간 이동을 줄인다.
    final aAfter = a.start.isAfter(preferredStart);
    final bAfter = b.start.isAfter(preferredStart);
    if (aAfter != bAfter) return aAfter ? -1 : 1;
    return a.start.compareTo(b.start);
  });
  return slots.take(count).toList();
}

/// "본관 3층", "교내 강당"처럼 사용자는 알지만 지도나 외부인은 찾기 어려운 장소를 찾는다.
bool cueVenueNeedsContext(String venue) {
  final value = venue.trim();
  if (value.isEmpty) return true;
  final internal = RegExp(
    r'교내|캠퍼스|본관|별관|강당|시청각실|학생회관|동아리실|체육관|운동장|공학관|과학관|인문관|사회관|강의실|\d{2,4}호',
  ).hasMatch(value);
  if (!internal) return false;
  final hasAnchor = RegExp(
    r'대학교|대학|고등학교|중학교|초등학교|학교|\b[ㄱ-ㆎ가-힣]+(?:로|길)\s*\d+',
  ).hasMatch(value);
  return !hasAnchor;
}
