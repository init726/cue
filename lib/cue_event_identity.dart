import 'package:flutter/material.dart';

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
  });

  final String title;
  final String venue;
  final String category;
  final DateTime? startsAt;
  final String? sourceKind;
  final String? participationFee;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF4F5F6) : const Color(0xFF202629);
    final muted = dark ? const Color(0xFFA9AFB5) : const Color(0xFF788690);
    final blue = dark ? const Color(0xFF77BCE2) : const Color(0xFF497F9D);
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
        ? (dark ? const Color(0xFF96CDB3) : const Color(0xFF428568))
        : blue;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final hour = date?.hour.toString().padLeft(2, '0');
    final minute = date?.minute.toString().padLeft(2, '0');
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF252D32) : const Color(0xFFF2F6F8),
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
            color: dark ? const Color(0xFF25343D) : const Color(0xFFEFF5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dark ? const Color(0xFF334752) : const Color(0xFFE1EBF2)),
          ),
          child: Column(children: [
            Text(date == null ? '일정' : '${date.month}월',
                style: TextStyle(fontSize: 11, color: blue)),
            const SizedBox(height: 3),
            Text(date == null ? '—' : '${date.day}'.padLeft(2, '0'),
                style: TextStyle(fontSize: 29, height: 1.2, fontWeight: FontWeight.w600, color: blue)),
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
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.place_outlined, size: 14, color: muted),
                const SizedBox(width: 3),
                Expanded(child: Text(venue, style: TextStyle(fontSize: 12, color: muted, height: 1.5))),
              ]),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              chip(category),
              if (participationFee?.trim().isNotEmpty == true) chip(participationFee!.trim()),
            ]),
          ],
        )),
      ],
    );
  }
}
