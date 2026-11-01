import 'package:flutter/material.dart';

/// Cue의 색을 한 곳에서 정한다. 화면 코드는 색 값 대신 역할(ink, accent, …)만 쓴다.
///
/// 방향: 따뜻한 회백색 바탕, 먹색 글자와 주 버튼, 강조는 탠저린 한 가지.
/// 다크 모드는 따뜻한 숯색 바탕에 흰 주 버튼, 조금 밝힌 탠저린을 쓴다.
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
    required this.heroMuted,
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
  final Color heroMuted;

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
    background: Color(0xFFF5F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1EFEB),
    border: Color(0xFFE7E4DE),
    ink: Color(0xFF1C1B19),
    muted: Color(0xFF6B665E),
    primary: Color(0xFF1C1B19),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFF2541B),
    accentText: Color(0xFFC4420E),
    onAccent: Color(0xFFFFFFFF),
    tint: Color(0xFFFFEDE4),
    hero: Color(0xFF1C1B19),
    heroMuted: Color(0xFFC9C4BB),
    success: Color(0xFF237A4B),
    successTint: Color(0xFFE6F3EB),
    warn: Color(0xFF9A5B00),
    warnTint: Color(0xFFFFF3DC),
    danger: Color(0xFFD13A3A),
    dangerTint: Color(0xFFFDECEC),
  );

  static const darkColors = CueColors._(
    dark: true,
    background: Color(0xFF121110),
    surface: Color(0xFF1C1B19),
    surfaceMuted: Color(0xFF262420),
    border: Color(0xFF34312C),
    ink: Color(0xFFF3F1EC),
    muted: Color(0xFFA6A097),
    primary: Color(0xFFF3F1EC),
    onPrimary: Color(0xFF121110),
    accent: Color(0xFFFF7A45),
    accentText: Color(0xFFFF8F61),
    onAccent: Color(0xFF1A0E08),
    tint: Color(0xFF3A2216),
    hero: Color(0xFF24221F),
    heroMuted: Color(0xFFA6A097),
    success: Color(0xFF6CCB98),
    successTint: Color(0xFF1C3127),
    warn: Color(0xFFF2B44A),
    warnTint: Color(0xFF3A2C14),
    danger: Color(0xFFFF6B6B),
    dangerTint: Color(0xFF3B1E1E),
  );

  static CueColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? darkColors : light;

  static CueColors of(BuildContext context) => forBrightness(Theme.of(context).brightness);
}
