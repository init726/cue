import 'package:flutter/material.dart';

/// Cue의 색을 한 곳에서 정한다. 화면 코드는 색 값 대신 역할(ink, accent, …)만 쓴다.
///
/// 방향: 인디고에서 바이올렛으로 이어지는 색을 정체성으로 쓴다(로고의 반짝임과 같은 색).
/// 회색은 보라 쪽으로 아주 살짝 기울인 라벤더 톤으로 두고, 큰 카드(촬영·다음 일정)에만
/// 인디고→바이올렛 그라데이션을 쓴다. 다크 모드는 남보라 바탕에 조금 밝힌 보라를 쓴다.
class CueColors {
  const CueColors._({
    required this.dark,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.ink,
    required this.muted,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.tint,
    required this.hero,
    required this.heroEnd,
    required this.heroMuted,
    required this.heroAction,
    required this.onHeroAction,
    required this.success,
    required this.successTint,
    required this.warn,
    required this.warnTint,
    required this.danger,
    required this.dangerTint,
  });

  final bool dark;

  /// 화면 바탕.
  final Color background;

  /// 카드·시트.
  final Color surface;

  /// 칩·날짜 블록처럼 카드 안에서 한 단계 낮춘 면.
  final Color surfaceMuted;
  final Color border;

  /// 본문 글자.
  final Color ink;

  /// 보조 글자. 흰 바탕 대비 4.5:1 이상.
  final Color muted;

  /// 주 버튼 배경과 글자.
  final Color primary;
  final Color onPrimary;

  /// 강조(다음 일정, 선택 표시, 아이콘). 작은 글자에는 accentText를 쓴다.
  final Color accent;
  final Color accentText;
  final Color onAccent;

  /// 강조색을 옅게 깐 배경(선택된 칩, 안내 상자).
  final Color tint;

  /// 첫 화면 촬영 카드처럼 크게 눈에 띄어야 하는 면과 그 위 보조 글자.
  final Color hero;
  final Color heroEnd;
  final Color heroMuted;

  /// 큰 카드 위의 주 버튼(흰 버튼에 보라 글자).
  final Color heroAction;
  final Color onHeroAction;

  /// 큰 카드의 바탕. 왼쪽 위 인디고에서 오른쪽 아래 바이올렛으로 넘어간다.
  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [hero, heroEnd],
  );

  /// 사용자 공유·연결됨 같은 긍정 상태.
  final Color success;
  final Color successTint;

  /// 주의(겹치는 일정, 교내 장소 확인, 마감 임박).
  final Color warn;
  final Color warnTint;
  final Color danger;
  final Color dangerTint;

  static const light = CueColors._(
    dark: false,
    background: Color(0xFFF6F5FC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2F1FA),
    border: Color(0xFFE6E4F2),
    ink: Color(0xFF17162B),
    muted: Color(0xFF615F78),
    primary: Color(0xFF6C5CF5),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF6C5CF5),
    accentText: Color(0xFF4F3FD9),
    onAccent: Color(0xFFFFFFFF),
    tint: Color(0xFFEFECFF),
    hero: Color(0xFF4B58E0),
    heroEnd: Color(0xFF7445E0),
    heroMuted: Color(0xFFE8E5FF),
    heroAction: Color(0xFFFFFFFF),
    onHeroAction: Color(0xFF4F3FD9),
    success: Color(0xFF1E8A57),
    successTint: Color(0xFFE5F5EC),
    warn: Color(0xFFA86400),
    warnTint: Color(0xFFFFF4DE),
    danger: Color(0xFFDC3F37),
    dangerTint: Color(0xFFFDECEB),
  );

  static const darkColors = CueColors._(
    dark: true,
    background: Color(0xFF0E0D18),
    surface: Color(0xFF17162A),
    surfaceMuted: Color(0xFF201E36),
    border: Color(0xFF2D2A48),
    ink: Color(0xFFEFEEF8),
    muted: Color(0xFFA3A1BC),
    primary: Color(0xFF6455E8),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF9787FF),
    accentText: Color(0xFFADA0FF),
    onAccent: Color(0xFF120F2A),
    tint: Color(0xFF24204A),
    hero: Color(0xFF3E3A9E),
    heroEnd: Color(0xFF5A2F9C),
    heroMuted: Color(0xFFD9D3FA),
    heroAction: Color(0xFFFFFFFF),
    onHeroAction: Color(0xFF4F3FD9),
    success: Color(0xFF5ED39A),
    successTint: Color(0xFF14291F),
    warn: Color(0xFFF5B94E),
    warnTint: Color(0xFF33270F),
    danger: Color(0xFFFF6B66),
    dangerTint: Color(0xFF3A1C1C),
  );

  static CueColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? darkColors : light;

  static CueColors of(BuildContext context) => forBrightness(Theme.of(context).brightness);
}
