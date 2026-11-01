import 'package:cue/cue_schedule_fields.dart';
import 'package:cue/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only the start is asked and the end follows with the same length', (tester) async {
    var start = DateTime(2026, 11, 7, 14);
    var end = DateTime(2026, 11, 7, 16);
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: CueScheduleFields(start: start, length: end.difference(start), onChanged: (s, e) => setState(() {
          start = s;
          end = e;
        })),
      ))),
    ));
    expect(find.text('시작'), findsOneWidget);
    expect(find.text('종료'), findsNothing);
    expect(find.text('11월 7일 (토)'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);

    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(picker.mode, CupertinoDatePickerMode.time);
    picker.onDateTimeChanged(DateTime(2026, 11, 7, 15, 30));
    await tester.pump();
    expect(start, DateTime(2026, 11, 7, 15, 30));
    expect(end, DateTime(2026, 11, 7, 17, 30), reason: '2시간 길이를 유지한다');

    await tester.tap(find.text('11월 7일 (토)'));
    await tester.pumpAndSettle();
    tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(DateTime(2026, 11, 9));
    await tester.pump();
    expect(start, DateTime(2026, 11, 9, 15, 30));
    expect(end, DateTime(2026, 11, 9, 17, 30));
    expect(tester.takeException(), isNull);
  });
}
