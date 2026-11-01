import 'package:cue/cue_event_identity.dart';
import 'package:cue/cue_place_search.dart';
import 'package:cue/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const museum = CuePlace(provider: 'kakao', id: '8217196', name: '서울시립미술관 서소문본관',
    address: '서울 중구 덕수궁길 61', category: '미술관', latitude: 37.564123, longitude: 126.973456, distanceMeters: 420);


void main() {
  testWidgets('map results show category, distance and address and return the picked place', (tester) async {
    final queries = <String>[];
    Object? picked;
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async => picked = await showModalBottomSheet<Object>(context: context, isScrollControlled: true,
            builder: (_) => CuePlaceSearchSheet(initialQuery: '시립미술관', search: (query) async {
              queries.add(query);
              return (enabled: true, places: [museum]);
            })),
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(queries, ['시립미술관']);
    expect(find.text('미술관 · 420m'), findsOneWidget);
    expect(find.text('서울 중구 덕수궁길 61'), findsOneWidget);
    await tester.tap(find.text('서울시립미술관 서소문본관'));
    await tester.pumpAndSettle();
    expect(picked, same(museum));
    expect(museum.toSaveFields(), containsPair('placeId', '8217196'));
  });

  testWidgets('without a map key the typed name can still be used', (tester) async {
    Object? picked;
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async => picked = await showModalBottomSheet<Object>(context: context, isScrollControlled: true,
            builder: (_) => CuePlaceSearchSheet(initialQuery: '우리 동네 책방',
                search: (_) async => (enabled: false, places: <CuePlace>[]))),
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('지도 검색을 아직 쓸 수 없어요'), findsOneWidget);
    await tester.tap(find.text('"우리 동네 책방" 그대로 쓰기'));
    await tester.pumpAndSettle();
    expect(picked, '우리 동네 책방');
  });

  testWidgets('cards show up to three keyword tags, a verified address and a map link', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      theme: cueTheme(Brightness.light),
      home: Scaffold(body: CueEventIdentity(
        title: '빛의 정원', venue: '서울시립미술관', category: '미술 전시', startsAt: DateTime(2026, 11, 3, 14),
        tags: const ['현대미술', '미술 전시', '#무료', '식물', '도시'],
        placeDetail: '서울 중구 덕수궁길 61 · 미술관',
        onOpenMap: () => opened++,
      )),
    ));
    expect(find.text('#현대미술'), findsOneWidget);
    expect(find.text('#무료'), findsOneWidget);
    expect(find.text('#식물'), findsOneWidget);
    expect(find.text('#도시'), findsNothing, reason: '최대 세 개');
    expect(find.text('#미술 전시'), findsNothing, reason: '종류와 같은 태그는 빼요');
    expect(find.text('서울 중구 덕수궁길 61 · 미술관'), findsOneWidget);
    await tester.tap(find.text('지도'));
    expect(opened, 1);
    expect(cueMapUri(placeUrl: 'https://place.map.kakao.com/8217196', venue: 'x').toString(),
        'https://place.map.kakao.com/8217196');
    expect(cueMapUri(venue: '우리 동네 책방').host, 'map.kakao.com');
  });
}
