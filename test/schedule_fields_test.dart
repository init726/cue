import 'package:cue/cue_schedule_fields.dart';
import 'package:cue/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('start and end rows open inline wheels and keep the length when the start moves', (tester) async {
    var start = DateTime(2026, 11, 7, 14);
    var end = DateTime(2026, 11, 7, 16);
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: CueScheduleFields(start: start, end: end, onChanged: (s, e) => setState(() {
          start = s;
          end = e;
        })),
      ))),
    ));
    expect(find.text('11월 7일 (토)'), findsNWidgets(2));
    expect(find.text('14:00'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);

    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    final picker = tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(picker.mode, CupertinoDatePickerMode.time);
    picker.onDateTimeChanged(DateTime(2026, 11, 7, 15, 30));
    await tester.pump();
    expect(start, DateTime(2026, 11, 7, 15, 30));
    expect(end, DateTime(2026, 11, 7, 17, 30), reason: '2시간 길이를 유지한다');

    await tester.tap(find.text('1시간 30분'));
    await tester.pump();
    expect(end, DateTime(2026, 11, 7, 17));

    await tester.tap(find.text('17:00'));
    await tester.pumpAndSettle();
    tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(DateTime(2026, 11, 7, 15));
    await tester.pump();
    expect(find.text('종료 시간이 시작 시간보다 늦어야 해요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
