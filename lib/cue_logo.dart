import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cue_colors.dart';

/// "Cue" 워드마크. 굵은 C 안에 인디고→바이올렛 반짝임을 넣고 뒤에 "ue"를 붙인다.
/// [size]는 "ue" 글자 크기이고 C는 대문자 높이에 맞춘다.
class CueLogo extends StatelessWidget {
  const CueLogo({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    final mark = size * 0.74;
    return Semantics(
      label: 'Cue',
      child: ExcludeSemantics(
        child: Text.rich(TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.aboveBaseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: EdgeInsets.only(right: size * 0.02),
              child: CustomPaint(
                size: Size(mark * 0.98, mark),
                painter: CueMarkPainter(ink: colors.ink, from: colors.hero, to: colors.heroEnd),
              ),
            ),
          ),
          TextSpan(
            text: 'ue',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              letterSpacing: -size * 0.05,
              color: colors.ink,
              height: 1,
            ),
          ),
        ])),
      ),
    );
  }
}

/// C 모양 고리와 그 안의 네 갈래 반짝임. 앱 아이콘과 같은 그림이다.
class CueMarkPainter extends CustomPainter {
  const CueMarkPainter({required this.ink, required this.from, required this.to});
  final Color ink;
  final Color from;
  final Color to;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final stroke = h * 0.25;
    final center = Offset(size.width / 2, h / 2);
    final radius = (h - stroke) / 2;
    // 오른쪽이 열린 C. 열린 각도는 위아래로 45도씩.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi / 4,
      math.pi * 1.5,
      false,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    final sparkle = Paint()
      ..shader = LinearGradient(colors: [from, to], begin: Alignment.topLeft, end: Alignment.bottomRight)
          .createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(_star(center.translate(h * 0.03, 0), h * 0.2), sparkle);
  }

  // 가운데로 오목하게 들어간 네 갈래 별.
  static Path _star(Offset c, double r) {
    final k = r * 0.16;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CueMarkPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.from != from || oldDelegate.to != to;
}
