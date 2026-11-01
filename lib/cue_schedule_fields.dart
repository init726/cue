import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'cue_route.dart' show CuePalette;

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
String cueDateLabel(DateTime value) => '${value.month}월 ${value.day}일 (${_weekdays[value.weekday - 1]})';
String cueTimeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String cueDurationLabel(Duration value) {
  final minutes = value.inMinutes;
  if (minutes < 60) return '$minutes분';
  return minutes % 60 == 0 ? '${minutes ~/ 60}시간' : '${minutes ~/ 60}시간 ${minutes % 60}분';
}

/// 아이폰 시계·캘린더처럼 스크롤 휠로 시간을 고른다. 휠은 분 단위 간격에 맞춘 시각에서 시작해야 한다.
class CueWheelPicker extends StatelessWidget {
  const CueWheelPicker({
    super.key,
    required this.mode,
    required this.value,
    required this.onChanged,
    this.minuteInterval = 5,
    this.minimum,
    this.maximum,
  });

  final CupertinoDatePickerMode mode;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final int minuteInterval;
  final DateTime? minimum;
  final DateTime? maximum;

  @override
  Widget build(BuildContext context) {
    final palette = CuePalette(context);
    var initial = value.copyWith(minute: value.minute - value.minute % minuteInterval, second: 0, millisecond: 0, microsecond: 0);
    if (minimum != null && initial.isBefore(minimum!)) initial = minimum!;
    if (maximum != null && initial.isAfter(maximum!)) initial = maximum!;
    return SizedBox(
      height: 200,
      child: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: Theme.of(context).brightness,
          textTheme: CupertinoTextThemeData(
            dateTimePickerTextStyle: TextStyle(fontSize: 21, color: palette.ink),
          ),
        ),
        child: CupertinoDatePicker(
          mode: mode,
          initialDateTime: initial,
          minuteInterval: minuteInterval,
          use24hFormat: true,
          minimumDate: minimum,
          maximumDate: maximum,
          dateOrder: DatePickerDateOrder.ymd,
          onDateTimeChanged: onChanged,
        ),
      ),
    );
  }
}

enum _Field { startDate, startTime, endDate, endTime }

/// 시작·종료 줄의 날짜나 시간을 누르면 바로 아래에 휠이 펼쳐진다(아이폰 캘린더의 새 이벤트 화면 방식).
/// 시작을 옮기면 길이를 유지한 채 종료도 함께 옮긴다.
class CueScheduleFields extends StatefulWidget {
  const CueScheduleFields({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
    this.durations = const [60, 90, 120, 180],
  });

  final DateTime start;
  final DateTime end;
  final void Function(DateTime start, DateTime end) onChanged;
  final List<int> durations;

  @override
  State<CueScheduleFields> createState() => _CueScheduleFieldsState();
}

class _CueScheduleFieldsState extends State<CueScheduleFields> {
  _Field? open;

  Duration get length {
    final value = widget.end.difference(widget.start);
    return value > Duration.zero ? value : const Duration(hours: 1);
  }

  void _apply(_Field field, DateTime value) {
    final start = widget.start, end = widget.end;
    switch (field) {
      case _Field.startDate:
        final next = DateTime(value.year, value.month, value.day, start.hour, start.minute);
        widget.onChanged(next, next.add(length));
      case _Field.startTime:
        final next = DateTime(start.year, start.month, start.day, value.hour, value.minute);
        widget.onChanged(next, next.add(length));
      case _Field.endDate:
        widget.onChanged(start, DateTime(value.year, value.month, value.day, end.hour, end.minute));
      case _Field.endTime:
        widget.onChanged(start, DateTime(end.year, end.month, end.day, value.hour, value.minute));
    }
  }

  void _toggle(_Field field) => setState(() => open = open == field ? null : field);

  @override
  Widget build(BuildContext context) {
    final palette = CuePalette(context);
    final invalid = !widget.end.isAfter(widget.start);
    Widget pill(_Field field, String text, {bool error = false}) {
      final selected = open == field;
      return GestureDetector(
        onTap: () => _toggle(field),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? palette.mint : palette.border.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(text, style: TextStyle(
            color: error ? const Color(0xFFE5484D) : selected ? palette.accent : palette.ink,
            fontWeight: FontWeight.w600,
            decoration: error ? TextDecoration.lineThrough : null,
          )),
        ),
      );
    }

    Widget row(String label, _Field date, _Field time, DateTime value, {bool error = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Text(label, style: TextStyle(color: palette.ink, fontSize: 16)),
        const Spacer(),
        pill(date, cueDateLabel(value), error: error),
        const SizedBox(width: 6),
        pill(time, cueTimeLabel(value), error: error),
      ]),
    );

    Widget wheel(_Field field) => CueWheelPicker(
      key: ValueKey(field),
      mode: field == _Field.startDate || field == _Field.endDate
          ? CupertinoDatePickerMode.date : CupertinoDatePickerMode.time,
      value: field == _Field.startDate || field == _Field.startTime ? widget.start : widget.end,
      onChanged: (value) => _apply(field, value),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Column(children: [
          row('시작', _Field.startDate, _Field.startTime, widget.start),
          if (open == _Field.startDate || open == _Field.startTime) wheel(open!),
          Divider(height: 1, indent: 14, color: palette.border),
          row('종료', _Field.endDate, _Field.endTime, widget.end, error: invalid),
          if (open == _Field.endDate || open == _Field.endTime) wheel(open!),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final minutes in widget.durations)
          ChoiceChip(
            label: Text(cueDurationLabel(Duration(minutes: minutes))),
            selected: !invalid && widget.end.difference(widget.start).inMinutes == minutes,
            showCheckmark: false,
            onSelected: (_) => widget.onChanged(widget.start, widget.start.add(Duration(minutes: minutes))),
          ),
      ]),
      if (invalid) ...[
        const SizedBox(height: 8),
        const Text('종료 시간이 시작 시간보다 늦어야 해요.', style: TextStyle(color: Color(0xFFE5484D), fontSize: 13)),
      ],
    ]);
  }
}
