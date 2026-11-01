import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cue_colors.dart';
import 'cue_upcoming.dart';

/// 지도에 꽂을 일정 하나.
class CueMapStop {
  const CueMapStop({required this.event, required this.latitude, required this.longitude});

  final Map<String, dynamic> event;
  final double latitude;
  final double longitude;

  String get title => event['title'] as String? ?? '';
  String get venue => event['venue'] as String? ?? '';
  DateTime? get start => DateTime.tryParse(event['startsAt'] as String? ?? '')?.toLocal();

  /// 좌표가 있는 일정만 지도에 올린다.
  static CueMapStop? from(Map<String, dynamic> event) {
    final latitude = (event['locationLatitude'] as num?)?.toDouble();
    final longitude = (event['locationLongitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    return CueMapStop(event: event, latitude: latitude, longitude: longitude);
  }
}

String _clock(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

/// iOS의 Apple 지도를 앱 화면에 넣는다. 확대·이동·현재 위치가 되고, 핀을 누르면 onSelected로 알린다.
/// iOS가 아니면(또는 테스트) 지도를 그리지 않고 빈 면을 둔다.
class CueMapView extends StatefulWidget {
  const CueMapView({
    super.key,
    required this.stops,
    required this.onSelected,
    this.route = false,
    this.selected = 0,
    this.bottomInset = 0,
    this.controller,
  });

  final List<CueMapStop> stops;
  final ValueChanged<int> onSelected;
  final bool route;
  final int selected;
  final double bottomInset;
  final CueMapController? controller;

  static bool get supported => !kIsWeb && Platform.isIOS;

  @override
  State<CueMapView> createState() => _CueMapViewState();
}

/// Flutter 쪽에서 지도를 움직일 때 쓴다.
class CueMapController {
  MethodChannel? _channel;

  Future<void> select(int index) async => _channel?.invokeMethod('select', index);
  Future<void> fit() async => _channel?.invokeMethod('fit');

  /// 현재 위치에서 index번 핀까지 경로를 그린다. mode는 walking, automobile, auto(걸어서 25분 넘으면 자동차).
  Future<CueRoute> route(int index, String mode) async {
    final channel = _channel;
    if (channel == null) throw const CueRouteException('지도를 준비하는 중이에요.');
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('route', {'index': index, 'mode': mode});
      return CueRoute(mode: result?['mode'] as String? ?? mode, minutes: result?['minutes'] as int? ?? 0,
          meters: result?['meters'] as int? ?? 0);
    } on PlatformException catch (error) {
      throw CueRouteException(error.code == 'NO_LOCATION'
          ? '현재 위치를 쓸 수 없어요. 설정에서 위치 접근을 허용해 주세요.'
          : '이 경로를 찾지 못했어요.');
    }
  }

  Future<void> clearRoute() async => _channel?.invokeMethod('clearRoute');
}

class CueRoute {
  const CueRoute({required this.mode, required this.minutes, required this.meters});

  final String mode;
  final int minutes;
  final int meters;

  String get label {
    final time = minutes >= 60 ? '${minutes ~/ 60}시간 ${minutes % 60}분' : '$minutes분';
    final distance = meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)}km' : '${meters}m';
    return '${mode == 'automobile' ? '자동차' : '도보'} $time · $distance';
  }
}

class CueRouteException implements Exception {
  const CueRouteException(this.message);
  final String message;
}

class _CueMapViewState extends State<CueMapView> {
  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    if (!CueMapView.supported) return ColoredBox(color: colors.surfaceMuted);
    return UiKitView(
      viewType: 'cue/map',
      creationParams: {
        'tint': colors.primary.toARGB32(),
        'route': widget.route,
        'selected': widget.selected,
        'bottomInset': widget.bottomInset,
        'markers': [
          for (final stop in widget.stops)
            {
              'latitude': stop.latitude,
              'longitude': stop.longitude,
              'title': stop.title,
              'subtitle': [if (stop.start != null) _clock(stop.start!), stop.venue].where((part) => part.isNotEmpty).join(' · '),
            },
        ],
      },
      creationParamsCodec: const StandardMessageCodec(),
      // 지도 화면에서는 끌기·확대를 모두 지도가 받는다.
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
      onPlatformViewCreated: (id) {
        final channel = MethodChannel('cue/map_$id');
        channel.setMethodCallHandler((call) async {
          if (call.method == 'selected' && call.arguments is int) widget.onSelected(call.arguments as int);
        });
        widget.controller?._channel = channel;
      },
    );
  }
}

/// 전체 화면 지도. 아래 카드를 넘기면 그 일정으로 지도가 옮겨 가고, 핀을 누르면 카드가 따라온다.
class CueMapPage extends StatefulWidget {
  const CueMapPage({
    super.key,
    required this.title,
    required this.stops,
    required this.onDirections,
    required this.onOpenExternal,
    this.weatherFor,
    this.route = false,
    this.initial = 0,
    this.startWithDirections = false,
  });

  final String title;
  final List<CueMapStop> stops;
  final bool route;
  final int initial;
  final void Function(CueMapStop stop) onDirections;
  final void Function(CueMapStop stop) onOpenExternal;
  final Future<CueWeather?> Function(CueMapStop stop)? weatherFor;

  /// 열자마자 현재 위치에서 가는 길을 그린다(다가오는 일정의 '길찾기').
  final bool startWithDirections;

  @override
  State<CueMapPage> createState() => _CueMapPageState();
}

class _CueMapPageState extends State<CueMapPage> {
  late final pages = PageController(initialPage: widget.initial, viewportFraction: widget.stops.length > 1 ? 0.9 : 1);
  final map = CueMapController();
  late int selected = widget.initial;
  static const panelHeight = 196.0;

  // 길찾기 중이면 아래 카드가 경로 정보를 보여준다.
  bool directing = false;
  bool routing = false;
  CueRoute? route;
  String? routeError;

  @override
  void initState() {
    super.initState();
    if (widget.startWithDirections) {
      // 지도가 만들어진 뒤에 경로를 그린다.
      WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(
          const Duration(milliseconds: 600), () => mounted ? _directions('auto') : null));
    }
  }

  Future<void> _directions(String mode) async {
    setState(() {
      directing = true;
      routing = true;
      routeError = null;
    });
    try {
      final value = await map.route(selected, mode);
      if (mounted) setState(() => route = value);
    } on CueRouteException catch (error) {
      if (mounted) setState(() => routeError = error.message);
    } finally {
      if (mounted) setState(() => routing = false);
    }
  }

  void _closeDirections() {
    setState(() {
      directing = false;
      route = null;
      routeError = null;
    });
    map.clearRoute();
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void _fromMap(int index) {
    if (index == selected || !mounted) return;
    if (directing) _closeDirections();
    setState(() => selected = index);
    pages.animateToPage(index, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(children: [
        Positioned.fill(child: CueMapView(
          stops: widget.stops,
          route: widget.route,
          selected: widget.initial,
          bottomInset: panelHeight + padding.bottom,
          controller: map,
          onSelected: _fromMap,
        )),
        Positioned(
          top: padding.top + 8,
          left: 16,
          right: 16,
          child: Row(children: [
            _round(colors, Icons.arrow_back, '뒤로', () => Navigator.pop(context)),
            const SizedBox(width: 10),
            Flexible(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)]),
              child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.ink, fontWeight: FontWeight.w800)),
            )),
            const Spacer(),
            if (widget.stops.length > 1) _round(colors, Icons.zoom_out_map, '전체 보기', map.fit),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: padding.bottom + 12,
          height: panelHeight - 12,
          child: PageView.builder(
            controller: pages,
            itemCount: widget.stops.length,
            onPageChanged: (index) {
              if (directing) _closeDirections();
              setState(() => selected = index);
              map.select(index);
            },
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.stops.length > 1 ? 6 : 16),
              child: directing && index == selected
                  ? _directionsCard(colors, widget.stops[index])
                  : _stopCard(colors, widget.stops[index], index),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _modeChip(CueColors colors, String mode, String label, IconData icon) {
    final active = route?.mode == mode;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: active ? colors.accentText : colors.muted),
      label: Text(label),
      selected: active,
      showCheckmark: false,
      onSelected: routing ? null : (_) => _directions(mode),
    );
  }

  Widget _directionsCard(CueColors colors, CueMapStop stop) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('현재 위치 → ${stop.venue.isEmpty ? stop.title : stop.venue}', maxLines: 1,
            overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.muted, fontSize: 13))),
        GestureDetector(onTap: _closeDirections, child: Icon(Icons.close, size: 20, color: colors.muted)),
      ]),
      const SizedBox(height: 6),
      Text(routing ? '경로를 찾는 중…' : routeError ?? route?.label ?? '',
          maxLines: 2,
          style: TextStyle(color: routeError == null ? colors.ink : colors.danger,
              fontSize: routeError == null ? 20 : 14, fontWeight: FontWeight.w800)),
      const Spacer(),
      Row(children: [
        _modeChip(colors, 'walking', '도보', Icons.directions_walk),
        const SizedBox(width: 6),
        _modeChip(colors, 'automobile', '자동차', Icons.directions_car_outlined),
        const Spacer(),
        TextButton.icon(
          onPressed: () => widget.onDirections(stop),
          icon: const Icon(Icons.directions_transit_outlined, size: 18),
          label: const Text('대중교통'),
        ),
      ]),
    ]),
  );

  Widget _round(CueColors colors, IconData icon, String tooltip, VoidCallback onTap) => Material(
    color: colors.surface,
    shape: const CircleBorder(),
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: 0.3),
    child: IconButton(onPressed: onTap, icon: Icon(icon, color: colors.ink), tooltip: tooltip),
  );

  Widget _stopCard(CueColors colors, CueMapStop stop, int index) {
    final start = stop.start;
    final weather = widget.weatherFor?.call(stop);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (widget.stops.length > 1) ...[
            Container(
              width: 24, height: 24, alignment: Alignment.center,
              decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
              child: Text('${index + 1}', style: TextStyle(color: colors.onPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(stop.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.ink, fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 4),
        Text([if (start != null) '${start.month}.${start.day} ${_clock(start)}', stop.venue].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.muted, fontSize: 13)),
        if (weather != null)
          FutureBuilder<CueWeather?>(
            future: weather,
            builder: (context, snapshot) {
              final value = snapshot.data;
              if (value == null || !value.available) return const SizedBox(height: 6);
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(value.iconData, size: 17, color: colors.accentText),
                  const SizedBox(width: 5),
                  Text(value.summary, style: TextStyle(color: colors.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              );
            },
          ),
        const Spacer(),
        Row(children: [
          Expanded(child: FilledButton.icon(
            // 앱 안 지도에서 경로를 그린다. iOS가 아니면 지도 앱 길찾기로 넘긴다.
            onPressed: CueMapView.supported ? () => _directions('auto') : () => widget.onDirections(stop),
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('길찾기'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => widget.onOpenExternal(stop),
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text('지도 앱'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
        ]),
      ]),
    );
  }
}
