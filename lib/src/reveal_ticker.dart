import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'streaming_reply_controller.dart';

/// [ticker] を [wanted] に合わせて開始・停止する ([RevealTicker] と
/// `revealed_markdown.dart` の両方の Ticker で共有する)。
///
/// ガードは [Ticker.isActive] を見る ([Ticker.isTicking] ではない):
/// `TickerMode` が無効・アプリが background のとき muted な Ticker は
/// `isActive` のまま `isTicking` だけ false になるので、`isTicking` で
/// ガードすると `start()` を 2 度呼んで例外になる。
void syncTicker(Ticker ticker, {required bool wanted}) {
  if (wanted) {
    if (!ticker.isActive) ticker.start();
  } else {
    if (ticker.isActive) ticker.stop();
  }
}

/// [StreamingReplyController.needsTicks] が true の間だけ Ticker を回し、
/// フレームごとに [StreamingReplyController.tick] を呼ぶ Widget。
///
/// 返答の Widget 全体 (思考の枠 + 返答の吹き出し) を 1 つだけ包む。
/// [StreamingReplyController.tick] には
/// [SchedulerBinding.currentFrameTimeStamp] (フレームの時刻そのもの) を
/// そのまま渡す — Controller は tick 間の差分 (経過) しか使わず 0 始まりで
/// ある必要が無いので、Widget 側で原点を引く必要は無い。
///
/// [StreamingReplyController.framesPaused] は、フレームが実際に流れている
/// かどうかの事実を [Ticker] 自身に聞いて (`!_ticker.isTicking`) 立てる —
/// `TickerMode` が無効な間や Ticker 自体が止まっている間、その間に届いた
/// 塊・受信完了の時刻に依存する処理を Controller 側で繰り延べさせる。
class RevealTicker extends StatefulWidget {
  const RevealTicker({super.key, required this.controller, required this.child});

  /// 時計を進める対象。
  final StreamingReplyController controller;

  /// 思考の枠・返答の吹き出しなど、出現の対象になる Widget 全体。
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

  /// Controller が Ticker を必要としている間だけ回す。
  void _syncTicker() {
    syncTicker(_ticker, wanted: widget.controller.needsTicks);
    _updateFramesPaused();
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
