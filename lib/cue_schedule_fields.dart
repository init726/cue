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

enum _Field { date, time }

/// 시작 날짜와 시간만 고른다. 날짜나 시간을 누르면 바로 아래에 휠이 펼쳐진다(아이폰 캘린더 방식).
/// 끝나는 시간은 따로 묻지 않고 지금 길이를 유지해 시작 뒤로 붙인다.
class CueScheduleFields extends StatefulWidget {
  const CueScheduleFields({
    super.key,
    required this.start,
    required this.length,
    required this.onChanged,
  });

  final DateTime start;
  final Duration length;
  final void Function(DateTime start, DateTime end) onChanged;

  @override
  State<CueScheduleFields> createState() => _CueScheduleFieldsState();
}

class _CueScheduleFieldsState extends State<CueScheduleFields> {
  _Field? open;

  Duration get length => widget.length > Duration.zero ? widget.length : const Duration(hours: 2);

  void _apply(_Field field, DateTime value) {
    final start = widget.start;
    final next = field == _Field.date
        ? DateTime(value.year, value.month, value.day, start.hour, start.minute)
        : DateTime(start.year, start.month, start.day, value.hour, value.minute);
    widget.onChanged(next, next.add(length));
  }

  @override
  Widget build(BuildContext context) {
    final palette = CuePalette(context);
    Widget pill(_Field field, String text) {
      final selected = open == field;
      return GestureDetector(
        onTap: () => setState(() => open = selected ? null : field),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? palette.mint : palette.border.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(text, style: TextStyle(
            color: selected ? palette.accent : palette.ink,
            fontWeight: FontWeight.w600,
          )),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Text('시작', style: TextStyle(color: palette.ink, fontSize: 16)),
            const Spacer(),
            pill(_Field.date, cueDateLabel(widget.start)),
            const SizedBox(width: 6),
            pill(_Field.time, cueTimeLabel(widget.start)),
          ]),
        ),
        if (open != null)
          CueWheelPicker(
            key: ValueKey(open),
            mode: open == _Field.date ? CupertinoDatePickerMode.date : CupertinoDatePickerMode.time,
            value: widget.start,
            onChanged: (value) => _apply(open!, value),
          ),
      ]),
    );
  }
}
