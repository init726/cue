import 'cue_schedule_agent.dart';

/// 요일별 운영 시간. 시각은 자정부터 지난 분으로 둔다. weekdays는 DateTime.weekday(월=1…일=7)와 같다.
class CueOpenHours {
  const CueOpenHours({required this.weekdays, required this.open, required this.close, this.lastEntry});

  final Set<int> weekdays;
  final int open;
  final int close;
  final int? lastEntry;

  factory CueOpenHours.fromJson(Map<String, dynamic> json) => CueOpenHours(
    weekdays: (json['weekdays'] as List<dynamic>? ?? []).whereType<num>().map((day) => day.toInt()).toSet(),
    open: _minutes(json['open'] as String?) ?? 0,
    close: _minutes(json['close'] as String?) ?? 0,
    lastEntry: _minutes(json['lastEntry'] as String?),
  );
}

int? _minutes(String? value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value ?? '');
  return match == null ? null : int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

DateTime? _date(String? value) {
  final parsed = DateTime.tryParse(value ?? '');
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime cueDay(DateTime value) => DateTime(value.year, value.month, value.day);

/// 하루 동안 방문할 수 있는 범위. latestStart는 입장 마감이 있으면 그 시각, 없으면 문 닫기 30분 전이다.
class CueDayWindow {
  const CueDayWindow({
    required this.open,
    required this.close,
    required this.latestStart,
    required this.known,
    this.printedLastEntry = false,
  });

  final DateTime open;
  final DateTime close;
  final DateTime latestStart;

  /// 안내문에 운영 시간이 없어 기본 시간(10:00–18:00)을 쓴 경우 false다.
  final bool known;

  /// 안내문에 입장 마감 시각이 적혀 있는지.
  final bool printedLastEntry;
}

/// 전시·팝업·박람회처럼 기간 안에 자유롭게 방문하는 행사.
class CuePeriod {
  const CuePeriod({
    required this.startDate,
    required this.endDate,
    required this.venue,
    this.dateText = '',
    this.hoursText = '',
    this.hours = const [],
    this.closedWeekdays = const {},
    this.closedDates = const {},
    this.visitMinutes = 90,
  });

  final DateTime startDate;
  final DateTime endDate;
  final String venue;
  final String dateText;
  final String hoursText;
  final List<CueOpenHours> hours;
  final Set<int> closedWeekdays;
  final Set<DateTime> closedDates;
  final int visitMinutes;

  bool get hoursKnown => hours.isNotEmpty;
  int get lengthDays => endDate.difference(startDate).inDays + 1;

  static CuePeriod? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final start = _date(json['startDate'] as String?);
    final end = _date(json['endDate'] as String?);
    final venue = json['venue'] as String? ?? '';
    if (start == null || end == null || end.isBefore(start) || venue.isEmpty) return null;
    return CuePeriod(
      startDate: start,
      endDate: end,
      venue: venue,
      dateText: json['dateText'] as String? ?? '',
      hoursText: json['hoursText'] as String? ?? '',
      hours: (json['hours'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CueOpenHours.fromJson)
          .where((item) => item.weekdays.isNotEmpty && item.close > item.open)
          .toList(),
      closedWeekdays: (json['closedWeekdays'] as List<dynamic>? ?? []).whereType<num>().map((day) => day.toInt()).toSet(),
      closedDates: (json['closedDates'] as List<dynamic>? ?? []).map((day) => _date(day as String?)).whereType<DateTime>().toSet(),
      visitMinutes: (json['visitMinutes'] as num?)?.toInt() ?? 90,
    );
  }

  /// 그날 방문할 수 있으면 운영 범위를, 기간 밖이거나 휴관이면 null을 돌려준다.
  CueDayWindow? windowOn(DateTime value) {
    final day = cueDay(value);
    if (day.isBefore(startDate) || day.isAfter(endDate)) return null;
    if (closedDates.contains(day) || closedWeekdays.contains(day.weekday)) return null;
    DateTime at(int minutes) => day.add(Duration(minutes: minutes));
    if (!hoursKnown) {
      return CueDayWindow(open: at(600), close: at(1080), latestStart: at(1050), known: false);
    }
    final today = hours.where((item) => item.weekdays.contains(day.weekday)).firstOrNull;
    if (today == null) return null;
    return CueDayWindow(
      open: at(today.open),
      close: at(today.close),
      latestStart: at(today.lastEntry ?? today.close - 30),
      known: true,
      printedLastEntry: today.lastEntry != null,
    );
  }
}

/// 방문 시작 시각을 운영 범위 안으로 맞춘다. 머무는 시간이 운영 시간보다 길면 문 닫는 시각에서 끊는다.
CueTimeSlot cueClampVisit(CueDayWindow window, DateTime start, Duration visit) {
  final latest = window.close.subtract(visit);
  final lastStart = latest.isBefore(window.latestStart) ? latest : window.latestStart;
  var begin = start;
  if (begin.isAfter(lastStart)) begin = lastStart;
  if (begin.isBefore(window.open)) begin = window.open;
  final end = begin.add(visit);
  return CueTimeSlot(begin, end.isAfter(window.close) ? window.close : end);
}

/// 앞뒤 일정과 최소 30분 간격을 두고 머무는 시간 전체를 운영 시간 안에 넣을 수 있는 시각 중
/// 오후 2시에 가장 가까운 시각을 고른다. 오늘이면 1시간 뒤부터 고른다.
CueTimeSlot? cueBestVisitOn(
  CuePeriod period,
  DateTime day,
  List<CueScheduleItem> busy, {
  required DateTime now,
  Duration? visit,
}) {
  final window = period.windowOn(day);
  if (window == null) return null;
  final length = visit ?? Duration(minutes: period.visitMinutes);
  const buffer = Duration(minutes: 30);
  final preferred = cueDay(day).add(const Duration(hours: 14));
  final earliest = now.add(const Duration(hours: 1));
  CueTimeSlot? best;
  for (var start = window.open; !start.isAfter(window.latestStart); start = start.add(const Duration(minutes: 30))) {
    final end = start.add(length);
    if (end.isAfter(window.close) || start.isBefore(earliest)) continue;
    if (busy.any((item) => start.isBefore(item.end.add(buffer)) && end.isAfter(item.start.subtract(buffer)))) continue;
    if (best == null ||
        start.difference(preferred).abs() < best.start.difference(preferred).abs()) {
      best = CueTimeSlot(start, end);
    }
  }
  return best;
}

class CueVisitSuggestion {
  const CueVisitSuggestion(this.label, this.slot);

  final String label;
  final CueTimeSlot slot;
}

/// 빠른 선택 후보: 가장 빠른 빈 날, 가장 가까운 주말, 끝나기 전 마지막 주말. 같은 날은 한 번만 보여준다.
List<CueVisitSuggestion> cueSuggestVisits(
  CuePeriod period,
  List<CueScheduleItem> busy, {
  required DateTime now,
  Duration? visit,
}) {
  final today = cueDay(now);
  final first = period.startDate.isAfter(today) ? period.startDate : today;
  final slots = <CueTimeSlot>[];
  for (var day = first; !day.isAfter(period.endDate) && slots.length < 400; day = DateTime(day.year, day.month, day.day + 1)) {
    final slot = cueBestVisitOn(period, day, busy, now: now, visit: visit);
    if (slot != null) slots.add(slot);
  }
  if (slots.isEmpty) return const [];
  bool weekend(CueTimeSlot slot) => slot.start.weekday >= DateTime.saturday;
  final weekends = slots.where(weekend).toList();
  final picks = <CueVisitSuggestion>[
    CueVisitSuggestion('가장 빠른 빈 날', slots.first),
    if (weekends.isNotEmpty)
      CueVisitSuggestion(
        cueDay(weekends.first.start).difference(today).inDays < 7 ? '이번 주말' : '가장 가까운 주말',
        weekends.first,
      ),
    if (weekends.length > 1 && period.endDate.difference(today).inDays > 14)
      CueVisitSuggestion('끝나기 전 마지막 주말', weekends.last),
  ];
  final days = <DateTime>{};
  return [for (final pick in picks) if (days.add(cueDay(pick.slot.start))) pick];
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _hm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
const _weekdayShort = ['월', '화', '수', '목', '금', '토', '일'];

String cueWeekdayRange(Set<int> days) {
  final sorted = days.toList()..sort();
  if (sorted.length == 7) return '매일';
  final contiguous = sorted.length > 2 && sorted.last - sorted.first == sorted.length - 1;
  return contiguous
      ? '${_weekdayShort[sorted.first - 1]}–${_weekdayShort[sorted.last - 1]}'
      : sorted.map((day) => _weekdayShort[day - 1]).join('·');
}

/// 가장 많은 요일에 쓰는 시간을 기본으로 묶고 다른 요일은 괄호로 덧붙인다.
/// 예: "화–일 10:00–18:00 (금 ~21:00)". 운영 시간을 모르면 빈 문자열이다.
String cueHoursSummary(CuePeriod period) {
  if (period.hours.isEmpty) return '';
  final base = period.hours.reduce((a, b) => b.weekdays.length > a.weekdays.length ? b : a);
  final days = {for (final item in period.hours) ...item.weekdays};
  final others = [
    for (final item in period.hours)
      if (item != base)
        '${cueWeekdayRange(item.weekdays)} ${item.open == base.open ? '' : _hm(item.open)}~${_hm(item.close)}',
  ];
  return '${cueWeekdayRange(days)} ${_hm(base.open)}–${_hm(base.close)}'
      '${others.isEmpty ? '' : ' (${others.join(', ')})'}';
}

String cuePeriodRange(CuePeriod period) =>
    '${period.startDate.month}.${period.startDate.day} – ${period.endDate.month}.${period.endDate.day}';

/// 캘린더 메모에 남길 기간·운영 정보. "추천 방문 시간"이 들어 있으면 동선 화면이 옮길 수 있는 일정으로 본다.
String cuePeriodNote(CuePeriod period, CueTimeSlot visit) {
  final window = period.windowOn(visit.start);
  return [
    '추천 방문 시간 ${_clock(visit.start)}–${_clock(visit.end)}',
    '운영 기간 ${cuePeriodRange(period)}',
    if (period.hoursKnown) '운영 시간 ${cueHoursSummary(period)}' else '운영 시간은 방문 전에 확인해 주세요',
    if (window != null && window.printedLastEntry)
      '입장 마감 ${_clock(window.latestStart)}',
    if (period.closedWeekdays.isNotEmpty) '휴관 ${cueWeekdayRange(period.closedWeekdays)}요일',
  ].join('\n');
}
