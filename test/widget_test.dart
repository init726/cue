import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch opens the main screen and asks age and interests on the first recommendation visit', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CueApp());
    expect(find.text('사진 한 장에서 시작되는 일정'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    // 설명 화면 없이 바로 메인으로 들어가고, 서버가 없어도 막히지 않는다.
    expect(find.text('Cue 시작하기'), findsNothing);
    expect(find.text('포스터 촬영하기'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('cue_onboarding_completed'), isTrue);
    expect(prefs.getBool('cue_onboarding_synced'), isFalse);

    // 추천 탭을 처음 열면 튜토리얼이 한 번 뜬다.
    await tester.tap(find.text('추천').last);
    for (var i = 0; i < 12; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('맞춤 추천을 시작해 볼까요?'), findsOneWidget);
    await tester.tap(find.text('20대'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('어떤 행사를 좋아하세요?'), findsOneWidget);
    for (final topic in ['영화', '음악']) {
      await tester.ensureVisible(find.text(topic).last);
      await tester.tap(find.text(topic).last);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('추천 받기'));
    await tester.tap(find.text('추천 받기'));
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('어떤 행사를 좋아하세요?'), findsNothing);
    expect(prefs.getBool('cue_recommend_tutorial_seen'), isTrue);
    expect(prefs.getString('cue_onboarding_age_band'), '20s');
    expect(prefs.getStringList('cue_onboarding_topics'), unorderedEquals(['영화', '음악']));
  });

  testWidgets('home offers camera, gallery and documents side by side', (tester) async {
    SharedPreferences.setMockInitialValues({'cue_onboarding_completed': true});
    await tester.pumpWidget(const CueApp());
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('포스터 촬영하기'), findsOneWidget);
    expect(find.text('사진첩'), findsOneWidget);
    expect(find.text('PDF·한글'), findsOneWidget);
    expect(find.text('저장 전에 Cue가 먼저 확인해요'), findsNothing);
    expect(find.textContaining('다음 일정의 지도와 그 시간 날씨'), findsOneWidget);
    expect(find.text('사용 방법'), findsNothing);
    expect(find.text('내 일정'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
  });
}
