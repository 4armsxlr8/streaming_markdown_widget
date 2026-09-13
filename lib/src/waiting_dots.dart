import 'package:flutter/widgets.dart';

import 'reply_theme.dart';

/// 受信前、返答の吹き出しの中に出す待機の点 3 つ。
///
/// mock.html の `.demo-wait-dot` (直径 7 の丸。不透明度が 1.4 秒周期で谷 (0.22) →
/// 山 (0.9) → 谷と ease-in-out で動き、2 つ目・3 つ目は 0.2 秒ずつ遅れて始まる) を
/// [AnimationController] 1 つと位相のずれで写す。
class WaitingDots extends StatefulWidget {
  const WaitingDots({super.key});

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: ReplyTheme.waitingDotDuration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staggerFraction =
        ReplyTheme.waitingDotStagger.inMicroseconds / ReplyTheme.waitingDotDuration.inMicroseconds;
    return SizedBox(
      height: ReplyTheme.waitingDotsHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i != 0) const SizedBox(width: ReplyTheme.waitingDotGap),
            _WaitingDot(controller: _controller, phaseOffset: staggerFraction * i),
          ],
        ],
      ),
    );
  }
}

/// 待機の点 1 つ。[controller] の値を [phaseOffset] (0〜1) だけずらして使う。
class _WaitingDot extends StatelessWidget {
  const _WaitingDot({required this.controller, required this.phaseOffset});

  final Animation<double> controller;
  final double phaseOffset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // 2・3 つ目の点が 1 つ目より遅れて始まる (doc コメント参照) ので、
        // 位相は引き算でずらす (足し算だと逆に先んじて動き、光が右→左に見える)。
        final phase = (controller.value - phaseOffset) % 1.0;
        return Opacity(
          opacity: _opacityAt(phase),
          child: Container(
            width: ReplyTheme.waitingDotDiameter,
            height: ReplyTheme.waitingDotDiameter,
            decoration: const BoxDecoration(
              color: ReplyTheme.waitingDotColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  /// 0%/100% で谷、50% で山になる ease-in-out の三角波。
  double _opacityAt(double phase) {
    final half = phase <= 0.5 ? phase / 0.5 : (1 - phase) / 0.5;
    final eased = Curves.easeInOut.transform(half);
    return ReplyTheme.waitingDotMinOpacity +
        (ReplyTheme.waitingDotMaxOpacity - ReplyTheme.waitingDotMinOpacity) * eased;
  }
}
