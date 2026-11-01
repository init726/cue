import 'package:cue/cue_travel_estimator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('cue/routes');

  // Android처럼 경로 채널이 없는 기기에서도 오류 대신 '모름'으로 돌려줘야 저장 흐름이 계속된다.
  test('a platform without the route channel returns null instead of throwing', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final estimator = CueTravelEstimator();
    expect(await estimator.estimate(from: '서울시립미술관', to: '국립현대미술관', departureAt: DateTime(2026, 11, 1, 15)), isNull);
    expect(await estimator.geocode('서울시립미술관'), isNull);
  });

  test('route errors from the platform also return null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'NO_ROUTE'));
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final estimator = CueTravelEstimator();
    expect(await estimator.estimate(from: '서울시립미술관', to: '국립현대미술관', departureAt: DateTime(2026, 11, 1, 15)), isNull);
    expect(await estimator.geocode('서울시립미술관'), isNull);
  });

  test('the same venue needs no travel and skips the platform', () async {
    final estimate = await CueTravelEstimator()
        .estimate(from: '서울시립미술관 ', to: '서울시립미술관', departureAt: DateTime(2026, 11, 1, 15));
    expect(estimate?.minutes, 0);
  });
}
