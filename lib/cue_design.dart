import 'package:flutter/material.dart';

// Cue 디자인 규칙. 모서리와 글자 단계는 여기 있는 값만 쓴다.
// 상자(카드)는 행사·일정처럼 실제 대상을 담을 때만 쓰고, 나머지는 여백과 구분선으로 나눈다.

abstract final class CueRadius {
  /// 버튼, 입력칸, 작은 표시.
  static const control = 10.0;

  /// 행사 카드와 묶음 목록.
  static const card = 16.0;
}

abstract final class CueType {
  static const largeTitle = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.6);
  static const title = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.3);
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35, letterSpacing: -0.2);
  // 한글 본문은 500 굵기가 작은 화면에서 더 또렷하다.
  static const body = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.45, letterSpacing: -0.2);
  static const caption = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.45);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3);

  /// 시간처럼 숫자를 세로로 맞춰야 하는 글자에 쓴다.
  static const tabular = [FontFeature.tabularFigures()];
}
