import 'dart:async';

import 'package:flutter/material.dart';

import 'cue_route.dart' show CuePalette;

/// 지도 검색으로 확인한 장소. 이름·주소·좌표가 함께 있어 같은 장소를 사용자끼리 하나로 묶을 수 있다.
class CuePlace {
  const CuePlace({
    required this.provider,
    required this.id,
    required this.name,
    required this.address,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
  });

  final String provider;
  final String id;
  final String name;
  final String address;
  final String category;
  final double latitude;
  final double longitude;
  final num? distanceMeters;

  static CuePlace? fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    if (latitude == null || longitude == null || id.isEmpty || name.isEmpty) return null;
    return CuePlace(
      provider: json['provider'] as String? ?? 'kakao',
      id: id,
      name: name,
      address: json['address'] as String? ?? '',
      category: json['category'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      distanceMeters: json['distanceMeters'] as num?,
    );
  }

  /// 서버 저장 요청에 붙이는 장소 연결 정보.
  Map<String, dynamic> toSaveFields() => {
    'placeProvider': provider,
    'placeId': id,
    'placeCategory': category,
    'locationAddress': address,
    'locationLatitude': latitude,
    'locationLongitude': longitude,
  };
}

String cueDistanceLabel(num meters) =>
    meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)}km';

typedef CuePlaceSearch = Future<({bool enabled, List<CuePlace> places})> Function(String query);

/// 장소 이름을 입력하면 지도 검색 결과를 보여주고, 고른 장소를 돌려준다.
/// 지도 검색을 쓸 수 없으면(서버에 키가 없음) 입력한 이름을 그대로 쓰도록 안내한다.
class CuePlaceSearchSheet extends StatefulWidget {
  const CuePlaceSearchSheet({super.key, required this.initialQuery, required this.search});

  final String initialQuery;
  final CuePlaceSearch search;

  @override
  State<CuePlaceSearchSheet> createState() => _CuePlaceSearchSheetState();
}

class _CuePlaceSearchSheetState extends State<CuePlaceSearchSheet> {
  late final controller = TextEditingController(text: widget.initialQuery);
  Timer? debounce;
  List<CuePlace> places = const [];
  bool enabled = true;
  bool searching = false;
  String? error;
  int run = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) _search(widget.initialQuery);
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    final current = ++run;
    if (query.length < 2) {
      setState(() {
        places = const [];
        error = null;
      });
      return;
    }
    setState(() => searching = true);
    try {
      final result = await widget.search(query);
      if (!mounted || current != run) return;
      setState(() {
        enabled = result.enabled;
        places = result.places;
        error = null;
        searching = false;
      });
    } catch (_) {
      if (!mounted || current != run) return;
      setState(() {
        error = '장소를 찾지 못했어요. 잠시 후 다시 시도해 주세요.';
        searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CuePalette(context);
    final typed = controller.text.trim();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('장소 찾기', style: TextStyle(color: palette.ink, fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('지도에 있는 장소를 고르면 주소와 위치가 함께 저장돼요.', style: TextStyle(color: palette.muted, height: 1.45)),
      const SizedBox(height: 14),
      TextField(
        controller: controller,
        autofocus: widget.initialQuery.trim().isEmpty,
        textInputAction: TextInputAction.search,
        onChanged: _changed,
        onSubmitted: _search,
        decoration: InputDecoration(
          hintText: '예: 서울시립미술관, 코엑스',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: searching
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)))
              : null,
        ),
      ),
      const SizedBox(height: 10),
      if (!enabled)
        _hint(palette, Icons.map_outlined, '지도 검색을 아직 쓸 수 없어요. 입력한 이름 그대로 저장할 수 있어요.')
      else if (error != null)
        _hint(palette, Icons.cloud_off_outlined, error!)
      else if (!searching && typed.length >= 2 && places.isEmpty)
        _hint(palette, Icons.search_off, '"$typed"에 맞는 장소가 없어요. 이름을 바꿔 보거나 그대로 써 주세요.'),
      for (final place in places)
        InkWell(
          onTap: () => Navigator.pop(context, place),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.place_outlined, color: palette.accent, size: 21),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(place.name, style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text([
                  if (place.category.isNotEmpty) place.category,
                  if (place.distanceMeters != null) cueDistanceLabel(place.distanceMeters!),
                ].join(' · '), style: TextStyle(color: palette.accent, fontSize: 12)),
                if (place.address.isNotEmpty)
                  Text(place.address, style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4)),
              ])),
            ]),
          ),
        ),
      if (typed.isNotEmpty) ...[
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => Navigator.pop(context, typed),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text('"$typed" 그대로 쓰기'),
        ),
      ],
    ]);
  }

  Widget _hint(CuePalette palette, IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: palette.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(color: palette.muted, fontSize: 13, height: 1.45))),
    ]),
  );
}
