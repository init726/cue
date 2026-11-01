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
  });

  final String title;
  final List<CueMapStop> stops;
  final bool route;
  final int initial;
  final void Function(CueMapStop stop) onDirections;
  final void Function(CueMapStop stop) onOpenExternal;
  final Future<CueWeather?> Function(CueMapStop stop)? weatherFor;

  @override
  State<CueMapPage> createState() => _CueMapPageState();
}

class _CueMapPageState extends State<CueMapPage> {
  late final pages = PageController(initialPage: widget.initial, viewportFraction: widget.stops.length > 1 ? 0.9 : 1);
  final map = CueMapController();
  late int selected = widget.initial;
  static const panelHeight = 196.0;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void _fromMap(int index) {
    if (index == selected || !mounted) return;
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
              setState(() => selected = index);
              map.select(index);
            },
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.stops.length > 1 ? 6 : 16),
              child: _stopCard(colors, widget.stops[index], index),
            ),
          ),
        ),
      ]),
    );
  }

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
            onPressed: () => widget.onDirections(stop),
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
