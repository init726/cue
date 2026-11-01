import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cue_colors.dart';

/// 서버 /v1/weather 응답. 예보 범위(약 16일) 밖이면 available이 false다.
class CueWeather {
  const CueWeather({required this.available, this.temperature, this.label = '', this.icon = '', this.precipitationProbability});

  final bool available;
  final int? temperature;
  final String label;
  final String icon;
  final int? precipitationProbability;

  factory CueWeather.fromJson(Map<String, dynamic> json) => CueWeather(
    available: json['available'] == true,
    temperature: (json['temperature'] as num?)?.round(),
    label: json['label'] as String? ?? '',
    icon: json['icon'] as String? ?? '',
    precipitationProbability: (json['precipitationProbability'] as num?)?.round(),
  );

  IconData get iconData => switch (icon) {
    'clear' => Icons.wb_sunny_outlined,
    'partly' => Icons.wb_cloudy_outlined,
    'fog' => Icons.foggy,
    'rain' => Icons.umbrella_outlined,
    'snow' => Icons.ac_unit,
    'storm' => Icons.thunderstorm_outlined,
    _ => Icons.cloud_outlined,
  };

  /// 예: "비 11° · 강수 60%". 강수 확률이 낮으면 생략한다.
  String get summary => [
    '$label $temperature°',
    if ((precipitationProbability ?? 0) >= 30) '강수 $precipitationProbability%',
  ].join(' · ');
}

/// 행사 장소 주변 지도 이미지. iOS는 Apple 지도로 그리고, 그리지 못하면 지도 열기 안내를 보여준다.
class CueMapSnapshot extends StatefulWidget {
  const CueMapSnapshot({super.key, required this.latitude, required this.longitude, this.height = 150, this.onTap});

  final double latitude;
  final double longitude;
  final double height;
  final VoidCallback? onTap;

  static const _channel = MethodChannel('cue/routes');
  static final _cache = <String, Uint8List>{};

  @override
  State<CueMapSnapshot> createState() => _CueMapSnapshotState();
}

class _CueMapSnapshotState extends State<CueMapSnapshot> {
  Future<Uint8List?>? image;
  String? key;

  Future<Uint8List?> _load(double width, CueColors colors) async {
    final cacheKey = '${widget.latitude},${widget.longitude},${width.round()},${widget.height.round()},${colors.dark}';
    final cached = CueMapSnapshot._cache[cacheKey];
    if (cached != null) return cached;
    try {
      final bytes = await CueMapSnapshot._channel.invokeMethod<Uint8List>('snapshot', {
        'latitude': widget.latitude,
        'longitude': widget.longitude,
        'width': width,
        'height': widget.height,
        'dark': colors.dark,
        'pin': colors.primary.toARGB32(),
      });
      if (bytes != null) CueMapSnapshot._cache[cacheKey] = bytes;
      return bytes;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final nextKey = '${widget.latitude},${widget.longitude},${width.round()},${colors.dark}';
      if (key != nextKey) {
        key = nextKey;
        image = _load(width, colors);
      }
      return GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: FutureBuilder<Uint8List?>(
              future: image,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                return Container(
                  color: colors.surfaceMuted,
                  alignment: Alignment.center,
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.map_outlined, color: colors.muted, size: 20),
                          const SizedBox(width: 6),
                          Text('지도에서 보기', style: TextStyle(color: colors.muted, fontSize: 13)),
                        ]),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

/// 스캔 탭의 "다가오는 일정" 카드: 다음 일정의 시간·장소 지도·그 시각 날씨·길찾기.
class CueUpcomingCard extends StatelessWidget {
  const CueUpcomingCard({
    super.key,
    required this.event,
    required this.now,
    required this.weather,
    required this.onOpenMap,
    required this.onDirections,
    required this.onOpenSchedule,
    this.moreCount = 0,
  });

  final Map<String, dynamic> event;
  final DateTime now;
  final Future<CueWeather?>? weather;
  final VoidCallback onOpenMap;
  final VoidCallback? onDirections;
  final VoidCallback onOpenSchedule;
  final int moreCount;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String _when(DateTime start) {
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(start.year, start.month, start.day).difference(today).inDays;
    final clock = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final relative = start.isBefore(now) ? '진행 중' : days == 0 ? '오늘' : days == 1 ? '내일' : '$days일 후';
    return '$relative · ${start.month}.${start.day} (${_weekdays[start.weekday - 1]}) $clock';
  }

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    final start = DateTime.parse(event['startsAt'] as String).toLocal();
    final latitude = (event['locationLatitude'] as num?)?.toDouble();
    final longitude = (event['locationLongitude'] as num?)?.toDouble();
    final venue = event['venue'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('다가오는 일정', style: TextStyle(color: colors.accentText, fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (moreCount > 0)
            GestureDetector(
              onTap: onOpenSchedule,
              child: Text('이후 $moreCount개 더보기', style: TextStyle(color: colors.muted, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 8),
        Text(event['title'] as String? ?? '', style: TextStyle(color: colors.ink, fontSize: 19,
            fontWeight: FontWeight.w800, height: 1.3)),
        const SizedBox(height: 4),
        Text(_when(start), style: TextStyle(color: colors.muted, fontSize: 13)),
        if (venue.isNotEmpty)
          Text(venue, style: TextStyle(color: colors.muted, fontSize: 13, height: 1.5)),
        const SizedBox(height: 12),
        if (latitude != null && longitude != null)
          CueMapSnapshot(latitude: latitude, longitude: longitude, onTap: onOpenMap)
        else
          GestureDetector(
            onTap: onOpenMap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.map_outlined, color: colors.muted, size: 19),
                const SizedBox(width: 8),
                Expanded(child: Text('장소 위치를 아직 몰라요. 지도에서 찾아볼까요?',
                    style: TextStyle(color: colors.muted, fontSize: 13))),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FutureBuilder<CueWeather?>(
            future: weather,
            builder: (context, snapshot) {
              final value = snapshot.data;
              if (weather == null) return const SizedBox.shrink();
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Text('날씨 확인 중', style: TextStyle(color: colors.muted, fontSize: 13));
              }
              // 불러오지 못했으면(null) 조용히 숨기고, 예보 범위 밖일 때만 안내한다.
              if (value == null) return const SizedBox.shrink();
              if (!value.available) {
                return Text('날씨는 2주 전부터 보여드려요', style: TextStyle(color: colors.muted, fontSize: 13));
              }
              return Row(children: [
                Icon(value.iconData, color: colors.accentText, size: 20),
                const SizedBox(width: 6),
                Flexible(child: Text(value.summary, style: TextStyle(color: colors.ink, fontSize: 14,
                    fontWeight: FontWeight.w700))),
              ]);
            },
          )),
          if (onDirections != null)
            FilledButton.icon(
              onPressed: onDirections,
              icon: const Icon(Icons.directions_outlined, size: 18),
              label: const Text('길찾기'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
        ]),
      ]),
    );
  }
}

/// 다가오는 일정이 없을 때: 활동 지역의 지금 날씨와 다음 행동 안내.
class CueTodayCard extends StatelessWidget {
  const CueTodayCard({super.key, required this.region, required this.weather, required this.onUseLocation});

  final String region;
  final Future<CueWeather?>? weather;
  final VoidCallback? onUseLocation;

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('오늘', style: TextStyle(color: colors.accentText, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (weather != null)
          FutureBuilder<CueWeather?>(
            future: weather,
            builder: (context, snapshot) {
              final value = snapshot.data;
              final text = value == null || !value.available ? '$region 날씨 확인 중' : '$region · ${value.summary}';
              return Row(children: [
                Icon(value?.iconData ?? Icons.cloud_outlined, color: colors.accentText, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: TextStyle(color: colors.ink, fontSize: 17, fontWeight: FontWeight.w800))),
              ]);
            },
          )
        else
          Row(children: [
            Icon(Icons.near_me_outlined, color: colors.accentText, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('현재 위치를 쓰면 오늘 날씨와 근처 행사를 보여드려요.',
                style: TextStyle(color: colors.ink, fontSize: 14, height: 1.45))),
            if (onUseLocation != null) TextButton(onPressed: onUseLocation, child: const Text('사용')),
          ]),
        const SizedBox(height: 8),
        Text('포스터를 저장하면 다음 일정의 지도와 그 시간 날씨를 여기서 보여드려요.',
            style: TextStyle(color: colors.muted, fontSize: 13, height: 1.45)),
      ]),
    );
  }
}
