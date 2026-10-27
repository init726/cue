import 'package:flutter/material.dart';

class CueSplash extends StatelessWidget {
  const CueSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blue = dark ? const Color(0xFF55C7F3) : const Color(0xFF169ED3);
    final background = dark ? const Color(0xFF101214) : const Color(0xFFF7F8FA);
    final text = dark ? const Color(0xFFF4F5F6) : const Color(0xFF181A1D);
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              label: 'Cue 카메라 로딩 화면',
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1), duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                builder: (_, value, child) => Transform.scale(scale: value, child: child),
                child: Container(
                  width: 208, height: 208,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF1A1D20) : const Color(0xFFE8F7FD),
                    borderRadius: BorderRadius.circular(54),
                  ),
                  child: CustomPaint(painter: _CameraPainter(blue)),
                ),
              ),
            ),
            const SizedBox(height: 36),
            Text('cue', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -2.5, color: text)),
            const SizedBox(height: 7),
            Text('사진 한 장에서 시작되는 일정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text)),
            const SizedBox(height: 28),
            SizedBox(width: 90, child: LinearProgressIndicator(
              minHeight: 3, borderRadius: BorderRadius.circular(8),
              backgroundColor: dark ? const Color(0xFF303438) : const Color(0xFFD9EFF8),
              color: blue,
            )),
            const SizedBox(height: 12),
            Text('Cue를 여는 중', style: TextStyle(fontSize: 12, color: dark ? const Color(0xFFA9AFB5) : const Color(0xFF697078))),
          ]),
        ),
      ),
    );
  }
}

class _CameraPainter extends CustomPainter {
  const _CameraPainter(this.blue);
  final Color blue;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round;
    final fine = Paint()..color = blue.withValues(alpha: 0.44)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2 + 8);
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(38, 66, 132, 102), const Radius.circular(22));
    canvas.drawRRect(body, outline);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(63, 51, 49, 19), const Radius.circular(7)), outline);
    canvas.drawCircle(center, 34, outline);
    canvas.drawCircle(center, 22, fine);
    canvas.drawCircle(center, 9, Paint()..color = blue.withValues(alpha: 0.22));
    canvas.drawCircle(const Offset(148, 83), 4, Paint()..color = blue);

    final corners = Path()
      ..moveTo(23, 46)..lineTo(23, 28)..lineTo(43, 28)
      ..moveTo(165, 28)..lineTo(185, 28)..lineTo(185, 46)
      ..moveTo(23, 164)..lineTo(23, 183)..lineTo(43, 183)
      ..moveTo(165, 183)..lineTo(185, 183)..lineTo(185, 164);
    canvas.drawPath(corners, fine);
  }

  @override
  bool shouldRepaint(covariant _CameraPainter oldDelegate) => oldDelegate.blue != blue;
}
