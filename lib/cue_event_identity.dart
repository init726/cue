import 'package:flutter/material.dart';

import 'cue_colors.dart';

/// An event's date and available metadata provide structure without artwork.
class CueEventIdentity extends StatelessWidget {
  const CueEventIdentity({
    super.key,
    required this.title,
    required this.venue,
    required this.category,
    this.startsAt,
    this.sourceKind,
    this.participationFee,
    this.tags = const [],
    this.placeDetail,
    this.onOpenMap,
  });

  final String title;
  final String venue;
  final String category;
  final DateTime? startsAt;
  final String? sourceKind;
  final String? participationFee;

  /// 행사 키워드. 종류와 겹치지 않는 것만 최대 세 개를 #태그로 보여준다.
  final List<String> tags;

  /// 지도에서 확인한 장소의 주소·종류. 있으면 장소 아래에 한 줄 더 보여준다.
  final String? placeDetail;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    final ink = colors.ink;
    final muted = colors.muted;
    final accent = colors.accentText;
    final date = startsAt?.toLocal();
    final shared = sourceKind == 'shared';
    final sourceLabel = switch (sourceKind) {
      'shared' => '사용자 공유',
      'web' => '웹에서 찾은 행사',
      'demo' => '시연용 예시',
      null => '내가 저장한 행사',
      _ => '등록된 행사',
    };
    final sourceColor = shared
        ? colors.success
        : muted;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final hour = date?.hour.toString().padLeft(2, '0');
    final minute = date?.minute.toString().padLeft(2, '0');
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: muted)),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Column(children: [
            Text(date == null ? '일정' : '${date.month}월',
                style: TextStyle(fontSize: 11, color: accent)),
            const SizedBox(height: 3),
            Text(date == null ? '—' : '${date.day}'.padLeft(2, '0'),
                style: TextStyle(fontSize: 29, height: 1.2, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 4),
            Text(date == null ? '확인 필요' : '${weekdays[date.weekday - 1]}요일',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: muted)),
          ]),
        ),
        const SizedBox(width: 15),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(shared ? Icons.people_outline : sourceKind == 'web'
                  ? Icons.language : Icons.event_note_outlined, size: 13, color: sourceColor),
              const SizedBox(width: 5),
              Expanded(child: Text(sourceLabel, style: TextStyle(fontSize: 11, color: sourceColor))),
            ]),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 18, height: 1.45,
                fontWeight: FontWeight.w700, letterSpacing: -0.4, color: ink)),
            const SizedBox(height: 9),
            if (date != null)
              Text('${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} · $hour:$minute',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.6)),
            if (venue.isNotEmpty) ...[
              const SizedBox(height: 3),
              InkWell(
                onTap: onOpenMap,
                borderRadius: BorderRadius.circular(6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(placeDetail == null ? Icons.place_outlined : Icons.verified_outlined, size: 14,
                      color: placeDetail == null ? muted : accent),
                  const SizedBox(width: 3),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(venue, style: TextStyle(fontSize: 12, color: muted, height: 1.5)),
                    if (placeDetail?.isNotEmpty == true)
                      Text(placeDetail!, style: TextStyle(fontSize: 11, color: muted.withValues(alpha: 0.8), height: 1.4)),
                  ])),
                  if (onOpenMap != null) ...[
                    const SizedBox(width: 4),
                    Text('지도', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              chip(category),
              if (participationFee?.trim().isNotEmpty == true) chip(participationFee!.trim()),
              for (final tag in tags
                  .map((tag) => tag.trim().replaceAll('#', ''))
                  .where((tag) => tag.isNotEmpty && tag != category && tag != '시연용')
                  .toSet()
                  .take(3))
                chip('#$tag'),
            ]),
          ],
        )),
      ],
    );
  }
}
