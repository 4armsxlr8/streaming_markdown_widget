import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'streaming_reply_style.dart';

/// A light that sweeps left to right, on a 1.6-second cycle, across the
/// thinking frame's headline text ("Thinking…").
///
/// Mirrors mock.html's `.demo-shimmer` (a `background-clip: text` gradient
/// animated via `background-position`) with a [ShaderMask]. The light's
/// motion and color are among the things spec decided not to test.
class ThinkingShimmer extends StatefulWidget {
  const ThinkingShimmer({
    super.key,
    required this.textKey,
    required this.text,
    required this.style,
  });

  /// Key attached to the text under the light (the caller passes Keys.thinkingFrameTitle).
  final Key textKey;

  final String text;

  final TextStyle style;

  @override
  State<ThinkingShimmer> createState() => _ThinkingShimmerState();
}

class _ThinkingShimmerState extends State<ThinkingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _started = false;

  // `StreamingReplyStyleScope.of` (an InheritedWidget lookup) is not safe to
  // call from initState, so the duration is set here instead — this runs
  // once, right after initState and before the first build.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = StreamingReplyStyleScope.of(
      context,
    ).thinkingShimmerDuration;
    if (!_started) {
      _started = true;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = StreamingReplyStyleScope.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              _gradientAt(_controller.value, style).createShader(bounds),
          child: child,
        );
      },
      child: Text(widget.text, key: widget.textKey, style: widget.style),
    );
  }
}

/// The gradient sweeping left to right at [t] (0–1, one cycle = 1.6 seconds).
LinearGradient _gradientAt(double t, StreamingReplyStyle style) {
  final dx = lerpDouble(-1.5, 1.5, t)!;
  return LinearGradient(
    begin: Alignment(dx - 1, 0),
    end: Alignment(dx + 1, 0),
    stops: const [0, 0.38, 0.5, 0.62, 1],
    colors: [
      style.thinkingShimmerBaseColor,
      style.thinkingShimmerBaseColor,
      style.thinkingShimmerHighlightColor,
      style.thinkingShimmerBaseColor,
      style.thinkingShimmerBaseColor,
    ],
  );
}
