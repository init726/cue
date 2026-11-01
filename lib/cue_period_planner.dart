import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cue_period.dart';
import 'cue_route.dart' show CuePalette;
import 'cue_schedule_agent.dart';
import 'cue_schedule_fields.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _dayLabel(DateTime value) => '${value.month}.${value.day} (${_weekdays[value.weekday - 1]})';

/// 기간형 행사의 방문 날짜와 시간을 고르는 화면.
/// 기간이 2주 이하면 날짜 띠, 더 길면 월 달력을 쓰고, 고른 날의 운영 시간 막대 위에 내 일정과 방문 시간을 겹쳐 보여준다.
class CuePeriodPlanner extends StatefulWidget {
  const CuePeriodPlanner({
    super.key,
    required this.period,
    required this.busy,
    required this.now,
    required this.onConfirm,
    this.initial,
  });

  final CuePeriod period;
  final List<CueScheduleItem> busy;
  final DateTime now;
  final ValueChanged<CueTimeSlot> onConfirm;
  final CueTimeSlot? initial;

  @override
  State<CuePeriodPlanner> createState() => _CuePeriodPlannerState();
}

class _CuePeriodPlannerState extends State<CuePeriodPlanner> {
  late Duration visit = Duration(minutes: widget.period.visitMinutes);
  late final List<CueVisitSuggestion> suggestions =
      cueSuggestVisits(widget.period, widget.busy, now: widget.now);
  late final DateTime firstDay = widget.period.startDate.isAfter(cueDay(widget.now))
      ? widget.period.startDate : cueDay(widget.now);
  late DateTime month;
  DateTime? day;
  DateTime? start;
  bool wheelOpen = false;

  CuePeriod get period => widget.period;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null && period.windowOn(initial.start) != null) {
      visit = initial.end.difference(initial.start);
      day = cueDay(initial.start);
      start = initial.start;
    } else if (suggestions.isNotEmpty) {
      day = cueDay(suggestions.first.slot.start);
      start = suggestions.first.slot.start;
    }
    final shown = day ?? firstDay;
    month = DateTime(shown.year, shown.month);
  }

  bool _selectable(DateTime value) {
    final window = period.windowOn(value);
    if (window == null || value.isBefore(firstDay)) return false;
    return window.latestStart.isAfter(widget.now);
  }

  int _busyCount(DateTime value) => widget.busy.where((item) => cueDay(item.start) == value).length;

  CueTimeSlot? get slot {
    final window = day == null ? null : period.windowOn(day!);
    if (window == null || start == null) return null;
    return cueClampVisit(window, start!, visit);
  }

  void _pickDay(DateTime value) => setState(() {
    day = value;
    month = DateTime(value.year, value.month);
    start = cueBestVisitOn(period, value, widget.busy, now: widget.now, visit: visit)?.start ??
        value.add(const Duration(hours: 14));
  });

  /// 휠에서 고를 수 있는 마지막 시작 시각. 입장 마감과 머무는 시간이 끝나는 시각 중 이른 쪽을 따른다.
  DateTime _lastStart(CueDayWindow window) {
    final byClose = window.close.subtract(visit);
    final last = byClose.isBefore(window.latestStart) ? byClose : window.latestStart;
    return last.isBefore(window.open) ? window.open : last;
  }

  void _shift(int minutes) => setState(() {
    final current = slot;
    if (current != null) start = current.start.add(Duration(minutes: minutes));
  });

  void _moveTo(double dx, double width, CueDayWindow window) {
    final span = window.close.difference(window.open).inMinutes;
    final minute = (dx / width * span - visit.inMinutes / 2).clamp(0, span).toDouble();
    setState(() => start = window.open.add(Duration(minutes: (minute / 30).round() * 30)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = CuePalette(context);
    final window = day == null ? null : period.windowOn(day!);
    final chosen = slot;
    final overlaps = chosen == null ? const <CueScheduleItem>[]
        : widget.busy.where((item) => cueSchedulesOverlap(chosen.start, chosen.end, item)).toList();
    final hours = cueHoursSummary(period);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('언제 갈까요?', style: TextStyle(color: palette.ink, fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('${cuePeriodRange(period)} · ${hours.isEmpty ? '운영 시간 미확인' : hours}',
          style: TextStyle(color: palette.muted, height: 1.45)),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final suggestion in suggestions) _suggestionChip(palette, suggestion),
        ]),
      ],
      const SizedBox(height: 16),
      if (period.endDate.difference(firstDay).inDays < 14) _strip(palette) else _month(palette),
      if (window != null && chosen != null) ...[
        const SizedBox(height: 18),
        Text('${_dayLabel(day!)} · ${_clock(window.open)}–${_clock(window.close)} 운영',
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        _timeline(palette, window, chosen),
        const SizedBox(height: 12),
        Row(children: [
          IconButton.outlined(
            onPressed: chosen.start.isAfter(window.open) ? () => _shift(-30) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: '30분 앞으로',
          ),
          Expanded(child: GestureDetector(
            onTap: () => setState(() => wheelOpen = !wheelOpen),
            child: Column(children: [
              Text('${_clock(chosen.start)} – ${_clock(chosen.end)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.ink, fontSize: 22, fontWeight: FontWeight.w800)),
              Text(wheelOpen ? '닫기' : '눌러서 시작 시간 고르기',
                  style: TextStyle(color: palette.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          )),
          IconButton.outlined(
            onPressed: chosen.end.isBefore(window.close) && chosen.start.isBefore(window.latestStart)
                ? () => _shift(30) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: '30분 뒤로',
          ),
        ]),
        if (wheelOpen)
          CueWheelPicker(
            key: ValueKey(day),
            mode: CupertinoDatePickerMode.time,
            value: chosen.start,
            minuteInterval: 30,
            minimum: window.open,
            maximum: _lastStart(window),
            onChanged: (value) => setState(() => start = value),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final minutes in {60, 90, 120, 180, period.visitMinutes}.toList()..sort())
            ChoiceChip(
              label: Text(cueDurationLabel(Duration(minutes: minutes))),
              selected: visit.inMinutes == minutes,
              showCheckmark: false,
              onSelected: (_) => setState(() => visit = Duration(minutes: minutes)),
            ),
        ]),
        const SizedBox(height: 12),
        if (overlaps.isNotEmpty)
          _note(palette, Icons.event_busy_outlined, '${overlaps.first.title}과(와) 겹쳐요. 막대를 눌러 옮겨 보세요.', warn: true),
        if (!window.known)
          _note(palette, Icons.info_outline, '안내문에 운영 시간이 없어 10:00–18:00으로 가정했어요. 방문 전에 확인해 주세요.', warn: true),
        if (window.printedLastEntry)
          _note(palette, Icons.login_rounded, '입장 마감 ${_clock(window.latestStart)}'),
        if (chosen.end.difference(chosen.start) < visit)
          _note(palette, Icons.timelapse_outlined, '문 닫는 시간까지 ${chosen.end.difference(chosen.start).inMinutes}분만 머물 수 있어요.'),
      ] else ...[
        const SizedBox(height: 14),
        _note(palette, Icons.event_outlined, '방문할 날짜를 골라 주세요.'),
      ],
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: chosen == null ? null : () => widget.onConfirm(chosen),
          child: Text(chosen == null ? '날짜를 골라 주세요' : '${_dayLabel(chosen.start)} ${_clock(chosen.start)}에 가기'),
        ),
      ),
    ]);
  }

  Widget _suggestionChip(CuePalette palette, CueVisitSuggestion suggestion) {
    final selected = slot?.start == suggestion.slot.start;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        day = cueDay(suggestion.slot.start);
        month = DateTime(day!.year, day!.month);
        start = suggestion.slot.start;
        visit = suggestion.slot.end.difference(suggestion.slot.start);
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.mint : palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(suggestion.label, style: TextStyle(color: palette.accent, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${_dayLabel(suggestion.slot.start)} ${_clock(suggestion.slot.start)}',
              style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _dayCell(CuePalette palette, DateTime value, {required bool strip}) {
    final selectable = _selectable(value);
    final selected = day == value;
    final closing = !value.isBefore(period.endDate.subtract(const Duration(days: 6)));
    final busy = _busyCount(value);
    final color = selected ? (palette.dark ? const Color(0xFF101214) : Colors.white)
        : !selectable ? palette.muted.withValues(alpha: 0.4)
        : closing ? palette.warn : palette.ink;
    return InkWell(
      onTap: selectable ? () => _pickDay(value) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: strip ? 50 : null,
        height: strip ? 66 : 46,
        margin: strip ? const EdgeInsets.only(right: 6) : const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: selected ? palette.accent : strip ? palette.surface : null,
          borderRadius: BorderRadius.circular(12),
          border: strip && !selected ? Border.all(color: palette.border) : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (strip) Text(_weekdays[value.weekday - 1], style: TextStyle(color: color, fontSize: 12)),
          Text('${value.day}', style: TextStyle(
            color: color, fontWeight: FontWeight.w700,
            decoration: !selectable && period.windowOn(value) == null && !value.isBefore(firstDay) &&
                !value.isAfter(period.endDate) ? TextDecoration.lineThrough : null,
          )),
          const SizedBox(height: 3),
          Container(width: 5, height: 5, decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: busy == 0 || !selectable ? Colors.transparent : selected ? color : palette.muted,
          )),
        ]),
      ),
    );
  }

  Widget _strip(CuePalette palette) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (var value = firstDay; !value.isAfter(period.endDate);
          value = DateTime(value.year, value.month, value.day + 1))
        _dayCell(palette, value, strip: true),
    ]),
  );

  Widget _month(CuePalette palette) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 1; i < first.weekday; i++) null,
      for (var i = 1; i <= days; i++) DateTime(month.year, month.month, i),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final canBack = DateTime(firstDay.year, firstDay.month).isBefore(month);
    final canForward = DateTime(period.endDate.year, period.endDate.month).isAfter(month);
    return Column(children: [
      Row(children: [
        Expanded(child: Text('${month.year}년 ${month.month}월',
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w800, fontSize: 16))),
        IconButton(
          onPressed: canBack ? () => setState(() => month = DateTime(month.year, month.month - 1)) : null,
          icon: const Icon(Icons.chevron_left_rounded), tooltip: '이전 달'),
        IconButton(
          onPressed: canForward ? () => setState(() => month = DateTime(month.year, month.month + 1)) : null,
          icon: const Icon(Icons.chevron_right_rounded), tooltip: '다음 달'),
      ]),
      Row(children: [
        for (final name in _weekdays)
          Expanded(child: Center(child: Text(name, style: TextStyle(color: palette.muted, fontSize: 12)))),
      ]),
      const SizedBox(height: 4),
      for (var row = 0; row < cells.length; row += 7)
        Row(children: [
          for (final value in cells.sublist(row, row + 7))
            Expanded(child: value == null ? const SizedBox(height: 49) : _dayCell(palette, value, strip: false)),
        ]),
      const SizedBox(height: 6),
      Row(children: [
        _legend(palette, palette.muted, '일정 있음'),
        const SizedBox(width: 14),
        _legend(palette, palette.warn, '마지막 주'),
        const SizedBox(width: 14),
        Text('취소선 휴관', style: TextStyle(color: palette.muted, fontSize: 12)),
      ]),
    ]);
  }

  Widget _legend(CuePalette palette, Color color, String label) => Row(children: [
    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(color: palette.muted, fontSize: 12)),
  ]);

  Widget _timeline(CuePalette palette, CueDayWindow window, CueTimeSlot chosen) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final span = window.close.difference(window.open).inMinutes;
      double x(DateTime value) =>
          (value.difference(window.open).inMinutes / span).clamp(0.0, 1.0) * width;
      final busy = widget.busy.where((item) =>
          item.start.isBefore(window.close) && item.end.isAfter(window.open));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTapDown: (details) => _moveTo(details.localPosition.dx, width, window),
          onHorizontalDragUpdate: (details) => _moveTo(details.localPosition.dx, width, window),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              for (final item in busy)
                Positioned(
                  left: x(item.start), width: (x(item.end) - x(item.start)).clamp(4.0, width),
                  top: 6, bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(color: palette.warnSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(item.title, maxLines: 1, overflow: TextOverflow.clip,
                        style: TextStyle(color: palette.warn, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              Positioned(
                left: x(chosen.start), width: (x(chosen.end) - x(chosen.start)).clamp(8.0, width),
                top: 4, bottom: 4,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(9)),
                  child: Text('방문', maxLines: 1, overflow: TextOverflow.clip,
                      style: TextStyle(color: palette.dark ? const Color(0xFF101214) : Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 5),
        Row(children: [
          Text(_clock(window.open), style: TextStyle(color: palette.muted, fontSize: 12)),
          const Spacer(),
          Text(_clock(window.close), style: TextStyle(color: palette.muted, fontSize: 12)),
        ]),
      ]);
    },
  );

  Widget _note(CuePalette palette, IconData icon, String text, {bool warn = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 17, color: warn ? palette.warn : palette.muted),
      const SizedBox(width: 7),
      Expanded(child: Text(text, style: TextStyle(color: warn ? palette.warn : palette.muted, fontSize: 13, height: 1.4))),
    ]),
  );
}
