import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('camera splash and dark theme setting', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({'cue_onboarding_completed': true});
    await tester.pumpWidget(const CueApp());
    expect(find.text('사진 한 장에서 시작되는 일정'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('행사 안내를\n캘린더에 저장하세요'), findsOneWidget);
    await tester.tap(find.text('설정').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('내 데이터'), findsOneWidget);
    expect(find.text('기본 알림'), findsNothing);
    expect(find.text('내 관심사 기록 초기화'), findsNothing);
    await tester.tap(find.text('화면 테마'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('다크'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(cueThemeMode.value, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(CueHome))).brightness, Brightness.dark);
    expect((await SharedPreferences.getInstance()).getString('theme_mode'), 'dark');
    await tester.tap(find.text('설정으로'));
    await tester.pumpAndSettle();
    expect(find.text('캘린더와 알림'), findsOneWidget);
    expect(find.text('다크'), findsOneWidget);
  });
}
