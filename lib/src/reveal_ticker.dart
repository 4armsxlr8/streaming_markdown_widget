import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'streaming_reply_controller.dart';

/// Starts or stops [ticker] to match [wanted], then tells [controller]
/// whether frames are actually flowing (shared by both [RevealTicker] and the
/// Ticker in `revealed_markdown.dart`).
///
/// The start/stop guard checks [Ticker.isActive] (not [Ticker.isTicking]):
/// while `TickerMode` is disabled or the app is backgrounded, a muted Ticker
/// stays `isActive` while `isTicking` alone goes false — guarding on
/// `isTicking` would call `start()` twice and throw. [Ticker.isTicking] is
/// exactly the fact [StreamingReplyController.framesPaused] needs, and must
/// be read after the start/stop above — read first, the first arrival while
/// placed on its own would resolve at [Duration.zero] and the whole text
/// would become revealed all at once on the next frame.
void syncTicker(
  Ticker ticker,
  StreamingReplyController controller, {
  required bool wanted,
}) {
  if (wanted) {
    if (!ticker.isActive) ticker.start();
  } else {
    if (ticker.isActive) ticker.stop();
  }
  controller.framesPaused = !ticker.isTicking;
}

/// A widget that runs a Ticker, calling [StreamingReplyController.tick] every
/// frame, only while [StreamingReplyController.needsTicks] is true.
///
/// Wraps the reply widget as a whole (thinking frame + reply bubble) exactly
/// once. Passes [SchedulerBinding.currentFrameTimeStamp] (the frame's
/// timestamp itself) straight through to [StreamingReplyController.tick] —
/// the controller only uses the delta between ticks (elapsed time) and
/// doesn't need it to start at zero, so the widget side has no origin to subtract.
///
/// [StreamingReplyController.framesPaused] is set by asking the [Ticker]
/// itself whether frames are actually flowing (`!_ticker.isTicking`) — while
/// `TickerMode` is disabled or the Ticker itself is stopped, this makes the
/// controller defer time-dependent processing for chunks and completion that
/// arrive during that window.
class RevealTicker extends StatefulWidget {
  const RevealTicker({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The clock this ticker drives.
  final StreamingReplyController controller;

  /// The whole subtree subject to revealing — the thinking frame, reply
  /// bubble, and so on.
  final Widget child;

  @override
  State<RevealTicker> createState() => _RevealTickerState();
}

class _RevealTickerState extends State<RevealTicker>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
    _syncTicker();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateFramesPaused();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateFramesPaused();
  }

  void _updateFramesPaused() {
    widget.controller.framesPaused = !_ticker.isTicking;
  }

  @override
  void didUpdateWidget(covariant RevealTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _syncTicker();
    }
  }

  void _onControllerChanged() => _syncTicker();

  /// Runs the ticker only while the controller still needs it.
  void _syncTicker() {
    syncTicker(
      _ticker,
      widget.controller,
      wanted: widget.controller.needsTicks,
    );
  }

  void _onTick(Duration elapsed) {
    widget.controller.tick(SchedulerBinding.instance.currentFrameTimeStamp);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
