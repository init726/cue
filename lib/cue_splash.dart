import 'package:flutter/material.dart';

import 'cue_colors.dart';
import 'cue_logo.dart';

class CueSplash extends StatelessWidget {
  const CueSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = CueColors.of(context);
    final text = colors.ink;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1), duration: const Duration(milliseconds: 750),
              curve: Curves.easeOutCubic,
              builder: (_, value, child) => Transform.scale(scale: value, child: child),
              child: const CueLogo(size: 64),
            ),
            const SizedBox(height: 22),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: '포스터에서 '),
                // 썸네일처럼 "일정까지"만 인디고→바이올렛으로 칠한다.
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => colors.heroGradient.createShader(bounds),
                    child: const Text('일정까지', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                ),
              ]),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.5),
            ),
            const SizedBox(height: 8),
            Text('사진 한 장에서 시작되는 일정', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.muted)),
            const SizedBox(height: 28),
            SizedBox(width: 90, child: LinearProgressIndicator(
              minHeight: 3, borderRadius: BorderRadius.circular(8),
              backgroundColor: colors.border,
              color: colors.accent,
            )),
            const SizedBox(height: 12),
            Text('Cue를 여는 중', style: TextStyle(fontSize: 12, color: colors.muted)),
          ]),
        ),
      ),
    );
  }
}
