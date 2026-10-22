import 'package:cue/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch asks one choice and starts without the server', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CueApp());
    expect(find.text('사진 한 장에서 시작되는 일정'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Cue 시작하기'), findsOneWidget);
    expect(find.text('사용 방법'), findsOneWidget);
    expect(find.text('관심사 기반 행사 추천'), findsOneWidget);
    // 테마·알림·일정 길이는 설정으로 옮겨 첫 화면에서 고르지 않는다.
    expect(find.text('기본 알림'), findsNothing);
    expect(find.text('종료 시간이 없는 일정'), findsNothing);
    expect(find.text('포스터 촬영하기'), findsNothing);
    // 테스트 환경에는 서버가 없지만 시작은 막히지 않아야 한다.
    await tester.ensureVisible(find.text('시작하기'));
    await tester.tap(find.text('시작하기'));
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('포스터 촬영하기'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('cue_onboarding_synced'), isFalse);
  });

  testWidgets('home offers camera, gallery and documents side by side', (tester) async {
    SharedPreferences.setMockInitialValues({'cue_onboarding_completed': true});
    await tester.pumpWidget(const CueApp());
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('포스터 촬영하기'), findsOneWidget);
    expect(find.text('사진첩'), findsOneWidget);
    expect(find.text('PDF·한글'), findsOneWidget);
    expect(find.text('사용 방법'), findsNothing);
    expect(find.text('내 일정'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
  });
}
