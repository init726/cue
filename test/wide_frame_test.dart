import 'package:cue/cue_wide_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Rect> _contentRect(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: CueWideFrame(child: SizedBox(key: Key('content'), height: 100))),
  ));
  return tester.getRect(find.byKey(const Key('content')));
}

void main() {
  testWidgets('wide screens keep the phone layout centered at a fixed width', (tester) async {
    final rect = await _contentRect(tester, const Size(1194, 834));
    expect(rect.width, CueWideFrame.maxContentWidth);
    expect(rect.center.dx, closeTo(1194 / 2, 0.5));
  });

  testWidgets('phone screens use the full width', (tester) async {
    final rect = await _contentRect(tester, const Size(393, 852));
    expect(rect.width, 393);
  });
}
