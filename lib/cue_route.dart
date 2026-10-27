import 'package:flutter/material.dart';

// 실험: 저장한 일정을 하루 한 줄의 노선으로 보여준다. 일정은 역, 일정 사이는 선이다.
// 아직 장소 좌표가 없어 이동 시간은 계산하지 않고, 일정 사이 간격과 장소가 같은지만 본다.

/// 이 간격보다 짧은데 장소가 다르면 빠듯하다고 표시한다.
const tightGap = Duration(minutes: 30);

class RouteStop {
  RouteStop(this.event, this.start, this.end);

  final Map<String, dynamic> event;
  final DateTime start;
  final DateTime end;

  String get id => event['id'] as String? ?? '';
  String get title => event['title'] as String? ?? '';
  String get venue => event['venue'] as String? ?? '';
  String get category => event['category'] as String? ?? '기타';

  /// 추천 전시처럼 Cue가 방문 시간을 정한 일정은 나중에 옮길 수 있다.
  bool get flexible =>
      (event['description'] as String? ?? '').contains('추천 방문 시간');

  static RouteStop? from(Map<String, dynamic> event) {
    final start = DateTime.tryParse(event['startsAt'] as String? ?? '')?.toLocal();
    final end = DateTime.tryParse(event['endsAt'] as String? ?? '')?.toLocal();
    if (start == null || end == null || !end.isAfter(start)) return null;
    return RouteStop(event, start, end);
  }
}

/// 시간이 겹치는 일정 묶음. 하나면 일반 역, 둘 이상이면 갈림길이다.
class RouteCluster {
  RouteCluster(this.stops);

  final List<RouteStop> stops;

  bool get fork => stops.length > 1;
  DateTime get start => stops.first.start;
  DateTime get end =>
      stops.map((stop) => stop.end).reduce((a, b) => a.isAfter(b) ? a : b);
}

enum LinkKind { sameVenue, tight, relaxed }

class RouteLink {
  const RouteLink(this.kind, this.gap);

  final LinkKind kind;
  final Duration gap;
}

class RouteDay {
  RouteDay(this.date, this.clusters, this.links);

  final DateTime date;
  final List<RouteCluster> clusters;

  /// links[i]는 clusters[i]와 clusters[i + 1] 사이의 구간이다.
  final List<RouteLink> links;

  List<RouteStop> get stops => [for (final cluster in clusters) ...cluster.stops];
  bool get hasFork => clusters.any((cluster) => cluster.fork);
  bool get hasTight => links.any((link) => link.kind == LinkKind.tight);
}

String _place(String venue) => venue.replaceAll(RegExp(r'\s+'), '').toLowerCase();

List<RouteDay> buildRoute(List<Map<String, dynamic>> events) {
  final stops = events.map(RouteStop.from).whereType<RouteStop>().toList()
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
  final byDay = <DateTime, List<RouteStop>>{};
  for (final stop in stops) {
    byDay
        .putIfAbsent(DateTime(stop.start.year, stop.start.month, stop.start.day), () => [])
        .add(stop);
  }
  return [for (final entry in byDay.entries) _routeDay(entry.key, entry.value)];
}

RouteDay _routeDay(DateTime date, List<RouteStop> stops) {
  final clusters = <RouteCluster>[];
  for (final stop in stops) {
    if (clusters.isNotEmpty && stop.start.isBefore(clusters.last.end)) {
      clusters.last.stops.add(stop);
    } else {
      clusters.add(RouteCluster([stop]));
    }
  }
  final links = <RouteLink>[];
  for (var index = 0; index + 1 < clusters.length; index += 1) {
    final from = clusters[index];
    final to = clusters[index + 1];
    final gap = to.start.difference(from.end);
    final sameVenue = !from.fork && !to.fork &&
        _place(from.stops.single.venue) == _place(to.stops.single.venue);
    links.add(RouteLink(
      sameVenue ? LinkKind.sameVenue : gap < tightGap ? LinkKind.tight : LinkKind.relaxed,
      gap,
    ));
  }
  return RouteDay(date, clusters, links);
}

class NextCue {
  const NextCue(this.stop, this.inProgress, this.remaining);

  final RouteStop stop;
  final bool inProgress;

  /// 이 일정 다음에 남은 일정 수.
  final int remaining;
}

NextCue? nextCue(List<RouteDay> days, DateTime now) {
  final upcoming = [
    for (final day in days) ...day.stops.where((stop) => stop.end.isAfter(now)),
  ];
  if (upcoming.isEmpty) return null;
  final stop = upcoming.first;
  return NextCue(stop, !stop.start.isAfter(now), upcoming.length - 1);
}

String clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String spanLabel(Duration value) {
  final hours = value.inMinutes ~/ 60;
  final minutes = value.inMinutes % 60;
  if (hours == 0) return '$minutes분';
  return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
}

String countdown(DateTime start, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(start.year, start.month, start.day).difference(today).inDays;
  if (days >= 2) return '$days일 후';
  if (days == 1) return '내일 ${clock(start)}';
  final left = start.difference(now);
  if (left.inMinutes < 1) return '곧 시작';
  return '${spanLabel(left)} 후';
}

const _timeWidth = 54.0;

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String dayLabel(DateTime date) =>
    '${date.month}월 ${date.day}일 ${_weekdays[date.weekday - 1]}요일';

class _Palette {
  _Palette(BuildContext context) : dark = Theme.of(context).brightness == Brightness.dark;

  final bool dark;

  Color get ink => dark ? const Color(0xFFF4F5F6) : const Color(0xFF181A1D);
  Color get muted => dark ? const Color(0xFFA9AFB5) : const Color(0xFF697078);
  Color get accent => dark ? const Color(0xFF55C7F3) : const Color(0xFF169ED3);
  Color get mint => dark ? const Color(0xFF25343A) : const Color(0xFFE8F7FD);
  Color get surface => dark ? const Color(0xFF1A1D20) : Colors.white;
  Color get border => dark ? const Color(0xFF303438) : const Color(0xFFE7EAED);
  Color get cue => dark ? const Color(0xFF24292C) : const Color(0xFF169ED3);
  Color get warn => dark ? const Color(0xFFFFB86B) : const Color(0xFFC96A12);
  Color get warnSoft => dark ? const Color(0xFF3A2A17) : const Color(0xFFFFF1E2);
}

class RouteView extends StatefulWidget {
  const RouteView({
    super.key,
    required this.events,
    required this.onEdit,
    required this.onCancel,
    this.busyEventId,
    this.onKeep,
    this.focusDate,
    this.focusRequest = 0,
    this.now,
  });

  final List<Map<String, dynamic>> events;
  final void Function(Map<String, dynamic> event) onEdit;
  final void Function(Map<String, dynamic> event) onCancel;
  final String? busyEventId;

  /// 겹치는 일정에서 keep만 남기고 drop은 취소한다.
  final void Function(Map<String, dynamic> keep, List<Map<String, dynamic>> drop)? onKeep;

  /// focusRequest가 바뀔 때마다 focusDate의 하루로 스크롤한다.
  final DateTime? focusDate;
  final int focusRequest;

  /// 테스트에서 현재 시각을 고정할 때 쓴다.
  final DateTime? now;

  @override
  State<RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends State<RouteView> {
  final dayKeys = <DateTime, GlobalKey>{};
  String? expandedId;
  bool showPast = false;

  @override
  void initState() {
    super.initState();
    _focus();
  }

  @override
  void didUpdateWidget(RouteView old) {
    super.didUpdateWidget(old);
    if (widget.focusRequest != old.focusRequest) _focus();
  }

  void _focus() {
    final date = widget.focusDate;
    if (date == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = dayKeys[DateTime(date.year, date.month, date.day)]?.currentContext;
      if (target != null && mounted) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic, alignment: 0.05);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);
    final now = widget.now ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = buildRoute(widget.events);
    final upcoming = days.where((day) => day.stops.any((stop) => stop.end.isAfter(now))).toList();
    final past = days.where((day) => !upcoming.contains(day)).toList();
    final next = nextCue(days, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (next != null) ...[_nextCueCard(palette, next, now), const SizedBox(height: 16)],
        _weekStrip(palette, today, days),
        const SizedBox(height: 22),
        if (upcoming.isEmpty)
          _quiet(palette, '다가오는 일정이 없어요', '포스터를 저장하면 이곳에 하루 동선이 그려져요.'),
        for (final day in upcoming) ...[
          _daySection(palette, day, today),
          const SizedBox(height: 20),
        ],
        if (past.isNotEmpty) _pastSection(palette, past),
      ],
    );
  }

  Widget _nextCueCard(_Palette palette, NextCue next, DateTime now) {
    final stop = next.stop;
    final label = next.inProgress
        ? 'NOW · ${clock(stop.end)}까지'
        : 'NEXT CUE · ${countdown(stop.start, now)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.cue, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12,
              letterSpacing: 1.1, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(stop.title, style: const TextStyle(color: Colors.white, fontSize: 22,
              fontWeight: FontWeight.w900, height: 1.25)),
          const SizedBox(height: 8),
          Text('${clock(stop.start)} – ${clock(stop.end)} · ${stop.venue}',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          if (next.remaining > 0) ...[
            const SizedBox(height: 12),
            Text('이어서 큐 ${next.remaining}개가 더 있어요',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _weekStrip(_Palette palette, DateTime today, List<RouteDay> days) {
    final byDate = {for (final day in days) day.date: day};
    return Row(
      children: [
        for (var offset = 0; offset < 7; offset += 1)
          Expanded(child: _weekDay(palette, today.add(Duration(days: offset)), byDate, offset == 0)),
      ],
    );
  }

  Widget _weekDay(_Palette palette, DateTime date, Map<DateTime, RouteDay> byDate, bool isToday) {
    final day = byDate[DateTime(date.year, date.month, date.day)];
    final count = day?.stops.length ?? 0;
    final conflict = day != null && (day.hasFork || day.hasTight);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: day == null ? null : () {
        final target = dayKeys[day.date]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic, alignment: 0.05);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isToday ? palette.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(_weekdays[date.weekday - 1],
                style: TextStyle(fontSize: 12, color: palette.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${date.day}', style: TextStyle(fontSize: 16, color: palette.ink,
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var dot = 0; dot < count.clamp(0, 3); dot += 1)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: conflict ? palette.warn : palette.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _daySection(_Palette palette, RouteDay day, DateTime today) {
    final key = dayKeys.putIfAbsent(day.date, GlobalKey.new);
    final offset = day.date.difference(today).inDays;
    final badge = offset == 0 ? '오늘' : offset == 1 ? '내일' : null;
    final stops = day.stops;
    final rows = <Widget>[];
    for (var index = 0; index < day.clusters.length; index += 1) {
      final cluster = day.clusters[index];
      final first = index == 0;
      final last = index == day.clusters.length - 1;
      if (cluster.fork) {
        rows.add(_forkRow(palette, cluster, top: !first));
        for (var branch = 0; branch < cluster.stops.length; branch += 1) {
          rows.add(_stopRow(palette, cluster.stops[branch], branch: String.fromCharCode(65 + branch),
              top: true, bottom: !(last && branch == cluster.stops.length - 1)));
        }
      } else {
        rows.add(_stopRow(palette, cluster.stops.single, top: !first, bottom: !last));
      }
      if (!last) rows.add(_linkRow(palette, day.links[index]));
    }
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(dayLabel(day.date), style: TextStyle(fontSize: 17, color: palette.ink,
                fontWeight: FontWeight.w900)),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(50)),
                child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: palette.dark ? const Color(0xFF101214) : Colors.white)),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text('${stops.length}곳 · ${clock(day.clusters.first.start)}–${clock(day.clusters.last.end)}',
            style: TextStyle(fontSize: 12, color: palette.muted)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: day.hasFork ? palette.warn.withValues(alpha: 0.6) : palette.border),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  /// branch는 겹치는 일정에서 고를 수 있는 길의 이름(A, B, …)이다.
  Widget _stopRow(_Palette palette, RouteStop stop,
      {String? branch, bool top = true, bool bottom = true}) {
    final expanded = expandedId == stop.id;
    final busy = widget.busyEventId == stop.id;
    final rail = branch != null ? palette.warn : palette.accent;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _timeWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clock(stop.start), maxLines: 1, softWrap: false, style: TextStyle(fontSize: 14,
                      color: palette.ink, fontWeight: FontWeight.w900)),
                  Text(clock(stop.end), maxLines: 1, softWrap: false,
                      style: TextStyle(fontSize: 12, color: palette.muted)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: CustomPaint(painter: _RailPainter(
              color: rail, top: top, bottom: bottom, dot: true,
              hollow: stop.flexible, fill: palette.surface,
            )),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => expandedId = expanded ? null : stop.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 0, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(stop.title, style: TextStyle(fontSize: 16, color: palette.ink,
                              fontWeight: FontWeight.w800, height: 1.3)),
                        ),
                        // 눌러서 수정·취소를 펼칠 수 있다는 표시.
                        Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: palette.muted),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(stop.venue, style: TextStyle(fontSize: 13, color: palette.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (branch != null) _chip(palette, '$branch길', palette.warn, palette.warnSoft),
                        _chip(palette, stop.category, palette.accent, palette.mint),
                        if (stop.flexible)
                          _chip(palette, '방문 시간 조정 가능', palette.muted, palette.mint),
                      ],
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 10),
                      if (busy)
                        Row(children: [
                          const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text('캘린더와 알림을 확인하는 중',
                              style: TextStyle(fontSize: 13, color: palette.muted)),
                        ])
                      else
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => widget.onEdit(stop.event),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('수정'),
                            ),
                            TextButton.icon(
                              onPressed: () => widget.onCancel(stop.event),
                              icon: const Icon(Icons.event_busy_outlined, size: 18),
                              label: const Text('일정 취소'),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _forkRow(_Palette palette, RouteCluster cluster, {required bool top}) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(width: _timeWidth),
        SizedBox(
          width: 28,
          child: CustomPaint(
            painter: _RailPainter(color: palette.warn, top: top, bottom: true),
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: palette.warnSoft, shape: BoxShape.circle,
                    border: Border.all(color: palette.warn, width: 2)),
                child: Icon(Icons.call_split, size: 15, color: palette.warn),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 0, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: palette.warnSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cluster.stops.length}개 일정의 시간이 겹쳐요. 갈 길을 하나 골라 주세요.',
                    style: TextStyle(fontSize: 13, color: palette.warn, fontWeight: FontWeight.w700),
                  ),
                  if (widget.onKeep != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var branch = 0; branch < cluster.stops.length; branch += 1)
                          OutlinedButton(
                            onPressed: () => widget.onKeep!(cluster.stops[branch].event, [
                              for (final other in cluster.stops)
                                if (other != cluster.stops[branch]) other.event,
                            ]),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: palette.warn,
                              side: BorderSide(color: palette.warn),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text('${String.fromCharCode(65 + branch)}길로 가기'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _linkRow(_Palette palette, RouteLink link) {
    final (icon, text, color) = switch (link.kind) {
      LinkKind.sameVenue => (Icons.place_outlined,
          link.gap.inMinutes <= 0 ? '같은 장소에서 바로 이어져요' : '같은 장소 · ${spanLabel(link.gap)} 쉬어가요',
          palette.muted),
      LinkKind.tight => (Icons.warning_amber_rounded,
          '간격 ${spanLabel(link.gap)} · 이동이 빠듯해요', palette.warn),
      LinkKind.relaxed => (Icons.more_horiz, '여유 ${spanLabel(link.gap)}', palette.muted),
    };
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _timeWidth),
          SizedBox(
            width: 28,
            child: CustomPaint(painter: _RailPainter(
              color: link.kind == LinkKind.tight ? palette.warn : palette.accent.withValues(alpha: 0.45),
              dashed: true,
            )),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 10),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(text, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pastSection(_Palette palette, List<RouteDay> past) {
    final stops = [for (final day in past.reversed) ...day.stops.reversed];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => showPast = !showPast),
          icon: Icon(showPast ? Icons.expand_less : Icons.expand_more),
          label: Text('지난 일정 ${stops.length}개'),
        ),
        if (showPast)
          for (final stop in stops)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text('${stop.start.month}.${stop.start.day} ${clock(stop.start)}',
                        style: TextStyle(fontSize: 12, color: palette.muted)),
                  ),
                  Expanded(
                    child: Text(stop.title, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: palette.ink)),
                  ),
                  IconButton(
                    tooltip: '수정',
                    onPressed: () => widget.onEdit(stop.event),
                    icon: Icon(Icons.edit_outlined, size: 18, color: palette.muted),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _quiet(_Palette palette, String title, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: palette.border),
    ),
    child: Column(
      children: [
        Icon(Icons.route_outlined, size: 40, color: palette.accent),
        const SizedBox(height: 14),
        Text(title, style: TextStyle(fontSize: 17, color: palette.ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: palette.muted)),
      ],
    ),
  );

  Widget _chip(_Palette palette, String text, Color color, Color background) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(50)),
    child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
  );
}

/// 노선의 세로선과 역 점을 그린다. 시간이 정해지지 않은 역은 속이 빈 점이다.
class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.color,
    this.top = true,
    this.bottom = true,
    this.dot = false,
    this.hollow = false,
    this.dashed = false,
    this.fill = Colors.white,
  });

  final Color color;
  final bool top;
  final bool bottom;
  final bool dot;
  final bool hollow;
  final bool dashed;
  final Color fill;

  static const dotY = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final from = top ? 0.0 : (dot ? dotY : size.height / 2);
    final to = bottom ? size.height : (dot ? dotY : size.height / 2);
    if (dashed) {
      for (var y = from; y < to; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 3).clamp(from, to)), line);
      }
    } else if (to > from) {
      canvas.drawLine(Offset(x, from), Offset(x, to), line);
    }
    if (!dot) return;
    canvas.drawCircle(Offset(x, dotY), 7, Paint()..color = hollow ? fill : color);
    canvas.drawCircle(Offset(x, dotY), 7, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    if (!hollow) canvas.drawCircle(Offset(x, dotY), 2.5, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color || old.top != top || old.bottom != bottom || old.dot != dot ||
      old.hollow != hollow || old.dashed != dashed || old.fill != fill;
}
