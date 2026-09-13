import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// 思考の枠の見出し行「考え中…」の文字の上を、1.6 秒周期で左から右へ流れる光。
///
/// mock.html の `.demo-shimmer` (`background-clip: text` のグラデーションを
/// `background-position` で流す) を [ShaderMask] で写す。光の流れ方・色そのものは
/// spec が「テストしないと決めたもの」。
class ThinkingShimmer extends StatefulWidget {
  const ThinkingShimmer({
    super.key,
    required this.textKey,
    required this.text,
    required this.style,
  });

  /// 光の下の文字に付けるキー (呼び出し元が Keys.thinkingFrameTitle を渡す)。
  final Key textKey;

  final String text;

  final TextStyle style;

  @override
  State<ThinkingShimmer> createState() => _ThinkingShimmerState();
}

class _ThinkingShimmerState extends State<ThinkingShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: ReplyTheme.thinkingShimmerDuration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => _gradientAt(_controller.value).createShader(bounds),
          child: child,
        );
      },
      child: Text(widget.text, key: widget.textKey, style: widget.style),
    );
  }
}

/// [t] (0〜1、1 周で 1.6 秒) に応じて左から右へ流れるグラデーション。
LinearGradient _gradientAt(double t) {
  final dx = lerpDouble(-1.5, 1.5, t)!;
  return LinearGradient(
    begin: Alignment(dx - 1, 0),
    end: Alignment(dx + 1, 0),
    stops: const [0, 0.38, 0.5, 0.62, 1],
    colors: const [
      ReplyTheme.thinkingShimmerBaseColor,
      ReplyTheme.thinkingShimmerBaseColor,
      ReplyTheme.thinkingShimmerHighlightColor,
      ReplyTheme.thinkingShimmerBaseColor,
      ReplyTheme.thinkingShimmerBaseColor,
    ],
  );
}
