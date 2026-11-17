import 'package:flutter/widgets.dart';

/// 아이패드처럼 넓은 화면에서는 휴대폰 기준으로 만든 내용을 가운데 일정 폭으로 보여준다.
/// 배경과 바텀시트·대화상자의 어두운 막은 화면 전체를 그대로 덮는다.
class CueWideFrame extends StatelessWidget {
  const CueWideFrame({super.key, required this.child});

  static const maxContentWidth = 680.0;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxContentWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
