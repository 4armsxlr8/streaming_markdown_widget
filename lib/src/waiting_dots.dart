import 'package:flutter/widgets.dart';

import 'streaming_reply_style.dart';

/// The 3 waiting dots shown inside the reply bubble before anything is received.
///
/// Mirrors mock.html's `.demo-wait-dot` (a 7-diameter circle whose opacity
/// moves trough (0.22) → peak (0.9) → trough on a 1.4-second ease-in-out
/// cycle, with the 2nd and 3rd dots starting 0.2 seconds later each) using a
/// single [AnimationController] and a phase offset. Since it doesn't own a
/// controller, look-and-feel values are read from [StreamingReplyStyleScope].
class WaitingDots extends StatefulWidget {
  const WaitingDots({super.key});

  @override
  State<WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<WaitingDots>
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
    ).waitingDotDuration;
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
    final staggerFraction =
        style.waitingDotStagger.inMicroseconds /
        style.waitingDotDuration.inMicroseconds;
    return SizedBox(
      height: style.waitingDotsHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i != 0) SizedBox(width: style.waitingDotGap),
            _WaitingDot(
              controller: _controller,
              phaseOffset: staggerFraction * i,
              style: style,
            ),
          ],
        ],
      ),
    );
  }
}

/// One waiting dot. Offsets [controller]'s value by [phaseOffset] (0–1).
class _WaitingDot extends StatelessWidget {
  const _WaitingDot({
    required this.controller,
    required this.phaseOffset,
    required this.style,
  });

  final Animation<double> controller;
  final double phaseOffset;
  final StreamingReplyStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // The 2nd and 3rd dots start later than the 1st (see the class doc
        // comment), so the phase is offset by subtraction (adding would make
        // them run ahead instead, making the light appear to sweep right to left).
        final phase = (controller.value - phaseOffset) % 1.0;
        return Opacity(
          opacity: _opacityAt(phase),
          child: Container(
            width: style.waitingDotDiameter,
            height: style.waitingDotDiameter,
            decoration: BoxDecoration(
              color: style.waitingDotColor,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  /// An ease-in-out triangle wave: trough at 0%/100%, peak at 50%.
  double _opacityAt(double phase) {
    final half = phase <= 0.5 ? phase / 0.5 : (1 - phase) / 0.5;
    final eased = Curves.easeInOut.transform(half);
    return style.waitingDotMinOpacity +
        (style.waitingDotMaxOpacity - style.waitingDotMinOpacity) * eased;
  }
}
