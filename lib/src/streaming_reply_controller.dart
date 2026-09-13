import 'package:flutter/foundation.dart';

import 'chunk.dart';
import 'reveal_clock.dart';

export 'chunk.dart';
export 'reveal_clock.dart' show RevealingChar;

/// 思考の枠の状態: 無し / 1 行 / 全部 / 畳み。
enum ThinkingFrameState {
  /// 思考の塊が 1 つも届いていない。
  none,

  /// 思考が流れている間の、1 行だけの表示。
  line,

  /// 思考の全文を広げた表示 (流れている間・畳んだ後のどちらでも取り得る)。
  full,

  /// 思考を畳んだ、見出し行だけの表示。
  collapsed,
}

/// 思考・返答それぞれ 1 つずつ持つ観測値。
///
/// [StreamingReplyController.thinking] / [StreamingReplyController.reply] の型。
abstract class RevealSection {
  /// 受信した文字数 (書記素。閉じていないサロゲートは数えない)。
  int get receivedCount;

  /// 表示済み (不透明度が 1 に達した) の文字数。
  int get displayedCount;

  /// 出現中の文字 (出現を始めたがまだ不透明度 1 未満)。index 昇順。
  List<RevealingChar> get revealing;

  /// 出現を始めた文字数 = [displayedCount] + [revealing] の要素数。
  int get startedCount;

  /// まだ出現していない残り = [receivedCount] - [startedCount]。
  int get pendingCount;

  /// 受信した全文 (閉じていないサロゲートは含まない)。
  String get text;

  /// 出現を始めた分までの文字列 (書記素の境界で切る)。
  String get revealedText;
}

/// [RevealClock] を [Duration Function()] 越しに覗く読み取り専用の観測値。
class _RevealSectionView implements RevealSection {
  _RevealSectionView(this._clock, this._now);

  final RevealClock _clock;
  final Duration Function() _now;

  @override
  int get receivedCount => _clock.receivedCount;

  @override
  int get displayedCount => _clock.displayedCountAt(_now());

  @override
  List<RevealingChar> get revealing => _clock.revealingAt(_now());

  @override
  int get startedCount => _clock.startedCountAt(_now());

  @override
  int get pendingCount => _clock.pendingCountAt(_now());

  @override
  String get text => _clock.text;

  @override
  String get revealedText => _clock.revealedTextAt(_now());
}

/// 返答の Widget の入り口。
///
/// 塊 ([Chunk]) を受け取り ([addChunk])、受信完了を伝え ([complete])、時計を
/// 進める ([tick]) ことで、思考・返答それぞれの観測値 ([thinking] / [reply])
/// と思考の枠の状態 ([thinkingFrame]) を更新する [ChangeNotifier]。
///
/// 思考と返答は同じ [RevealClock] (出現の仕組み) を 1 つずつ持つ。返答の
/// 最初の塊が届くと、思考の残りは早送りで出し切られ、思考の枠が畳まれてから
/// (畳みは 300ms) 返答の時計が進み始める。
class StreamingReplyController extends ChangeNotifier {
  StreamingReplyController();

  /// 思考の枠を畳むのにかかる時間 (`ReplyTheme.thinkingCollapseDuration` は
  /// これを参照する — 畳みの速さの正本はここ)。
  static const Duration collapseDuration = Duration(milliseconds: 300);

  final RevealClock _thinkingClock = RevealClock();
  final RevealClock _replyClock = RevealClock();

  Duration _now = Duration.zero;

  /// 直近の [tick] の `now`。[addChunk] / [complete] の到着時刻に使う
  /// (tick 前なら [Duration.zero])。
  Duration? _lastTickNow;

  /// `TickerMode` が無効・アプリが background の間 (フレームが流れていない
  /// 間)、[addChunk] / [complete] の到着時刻に依存する処理を繰り延べさせる
  /// フラグ (既定 false)。Widget ([RevealTicker]) が実際の `Ticker` の状態を
  /// 見て設定する — フレームが流れているかどうかの事実は Controller 自身では
  /// 推定せず、Widget から教えてもらう。
  bool framesPaused = false;

  /// [framesPaused] が true の間、または [_deferredArrivals] がまだ空でない
  /// 間に届いた塊の、到着時刻に依存する処理 (出現の割り当て) を、次の [tick]
  /// の `now` で行うための待ち行列。
  final List<void Function(Duration now)> _deferredArrivals = [];

  bool _thinkingStarted = false;
  bool _collapsed = false;
  Duration? _collapseStartedAt;
  bool _userExpanded = false;

  Duration? _thinkingArrivedAt;
  Duration? _replyArrivedAt;
  int? _thinkingSeconds;

  /// 返答の時計が出現の割り当てを始めてよいかどうか。思考の塊が一度も
  /// 届いていなければ最初から true。届いていれば、畳みが終わるまで false。
  bool _replyGateOpen = false;

  bool _isComplete = false;

  late final RevealSection thinking = _RevealSectionView(_thinkingClock, () => _now);

  late final RevealSection reply = _RevealSectionView(_replyClock, () => _now);

  /// 思考の枠の状態: 無し / 1 行 / 全部 / 畳み。
  ThinkingFrameState get thinkingFrame {
    if (!_thinkingStarted) return ThinkingFrameState.none;
    if (!_collapsed) return _userExpanded ? ThinkingFrameState.full : ThinkingFrameState.line;
    return _userExpanded ? ThinkingFrameState.full : ThinkingFrameState.collapsed;
  }

  /// 思考の時計が動いている (思考の塊が届き始めてから畳みが始まるまで)。
  bool get isThinking => _thinkingStarted && !_collapsed;

  /// 「n 秒考えました」の n。確定前は null。
  int? get thinkingSeconds => _thinkingSeconds;

  /// 受信完了済み。
  bool get isComplete => _isComplete;

  /// フレームが流れておらず ([framesPaused])、または繰り延べの列
  /// ([_deferredArrivals]) がまだ空でない間は、到着時刻に依存する処理を
  /// 今すぐ行わず繰り延べる ([_resolveOrDefer])。
  bool get _mustDefer => framesPaused || _deferredArrivals.isNotEmpty;

  /// 畳みを開始してよい状態か: まだ畳んでおらず、思考が始まっていて、返答の
  /// 到着か受信完了のどちらかが来ていて、かつ [now] 時点で思考の未出現が
  /// もう無い。[tick] (実際に畳みを始めるかどうか) と [needsTicks] (畳みの
  /// 開始条件は満たしたがまだ tick が来ていないことの検出) の両方で使う。
  bool _collapseReady(Duration now) =>
      !_collapsed &&
      _thinkingStarted &&
      (_replyArrivedAt != null || _isComplete) &&
      _thinkingClock.pendingCountAt(now) == 0;

  bool _needsTicksCache = false;

  /// 出現中か未出現の文字があるか、畳みの途中 → Widget が Ticker を回す目安。
  ///
  /// [tick] / [addChunk] / [complete] が状態を変えるたびに計算し直して保持
  /// した値を返すだけにする (1 フレームの中で Widget 側からも複数回読まれる
  /// ため、そのたび全長を走査しない)。
  bool get needsTicks => _needsTicksCache;

  bool _computeNeedsTicks() {
    if (_thinkingClock.displayedCountAt(_now) < _thinkingClock.receivedCount) return true;
    if (_replyClock.displayedCountAt(_now) < _replyClock.receivedCount) return true;
    if (_collapsed && !_replyGateOpen) return true;
    // Ticker が止まっている間に届いた到着・完了の、時刻に依存する処理がまだ
    // 済んでいない (次の tick で処理する)。
    if (_deferredArrivals.isNotEmpty) return true;
    // 思考を出し切って畳みの開始条件は満たしたが、まだ tick が来ていないので
    // 畳みが始まっていない (このまま tick が止まると「考え中…」のまま止まる)。
    if (_collapseReady(_now)) return true;
    return false;
  }

  void _refreshNeedsTicks() {
    _needsTicksCache = _computeNeedsTicks();
  }

  /// 到着の解決 (`now` に依存する処理) を行う。[_mustDefer] でなければ直近の
  /// [tick] の `now` ([_lastTickNow]。tick 前なら [Duration.zero]) で今すぐ
  /// [resolve] を呼び、[_mustDefer] なら次の [tick] の `now` まで
  /// [_deferredArrivals] に積んで繰り延べる — フレームが止まっている間の
  /// [_lastTickNow] は古くなりうるため、それを到着時刻にすると次のフレームで
  /// 出現中の残りがまとめて表示済みへ飛び「1 文字ずつ」が崩れる。
  /// [_deferredArrivals] が残っている間も繰り延べるのは、そこに積まれた到着が
  /// まだ古い `now` のまま解決されていないため — ここで直近の `now` を使うと、
  /// 次の [tick] で繰り延べ分がまとめて解決されたときに、この塊だけ先に
  /// 進んだ扱いになる。
  void _resolveOrDefer(void Function(Duration now) resolve) {
    if (_mustDefer) {
      _deferredArrivals.add(resolve);
    } else {
      resolve(_lastTickNow ?? Duration.zero);
    }
  }

  /// 塊を届ける。
  void addChunk(Chunk chunk) {
    switch (chunk.kind) {
      case ChunkKind.thinking:
        _addThinkingChunk(chunk.text);
      case ChunkKind.reply:
        _addReplyChunk(chunk.text);
    }
    _refreshNeedsTicks();
    notifyListeners();
  }

  /// 思考の書記素が 1 つ以上受信された時点で [_thinkingStarted] を true にし、
  /// 到着の解決 ([_resolveOrDefer]) を行う。0 文字の塊 (空文字・保留中の上位
  /// サロゲートだけの塊) は文字を溜めるだけで、思考の切替 ([_thinkingStarted]・
  /// 到着時刻の確定) を走らせない。
  void _addThinkingChunk(String text) {
    final receivedBefore = _thinkingClock.receivedCount;
    _thinkingClock.appendOnly(text);
    if (_thinkingClock.receivedCount == receivedBefore) return;
    _thinkingStarted = true;
    _resolveOrDefer(_resolveThinkingArrival);
  }

  void _resolveThinkingArrival(Duration now) {
    _thinkingArrivedAt ??= now;
    _thinkingClock.scheduleFromArrival(now);
  }

  /// 返答の書記素が 1 つ以上受信された時点で到着の解決 ([_replyArrivedAt] の
  /// 確定・思考の早送り・門の開放) を行う。0 文字の塊は文字を溜めるだけ。
  void _addReplyChunk(String text) {
    final receivedBefore = _replyClock.receivedCount;
    _replyClock.appendOnly(text);
    if (_replyClock.receivedCount == receivedBefore) return;
    _resolveOrDefer(_resolveReplyArrival);
  }

  void _resolveReplyArrival(Duration now) {
    if (_replyArrivedAt == null) {
      _replyArrivedAt = now;
      if (_thinkingArrivedAt != null) {
        _thinkingSeconds = _roundSeconds(now - _thinkingArrivedAt!);
        if (_thinkingClock.pendingCountAt(now) > 0) {
          _thinkingClock.fastForward(now);
        }
      } else {
        // 思考が一度も届いていなければ、返答は畳みを待たずに流れる。
        _replyGateOpen = true;
      }
    }
    if (_replyGateOpen) {
      _replyClock.scheduleFromArrival(now);
    }
  }

  /// 受信完了。まず思考・返答それぞれの時計に保留中の上位サロゲートがあれば
  /// 確定させる ([RevealClock.complete])。[_isComplete] は同期的に立てる
  /// ([needsTicks] や Widget がすぐ観測できるようにするため)。`now` に依存する
  /// 処理 (「n 秒考えました」の確定・早送り) は [addChunk] と同じ [_resolveOrDefer]
  /// で行う。
  ///
  /// [RevealClock.complete] が保留中の上位サロゲートを U+FFFD として確定させた
  /// (戻り値 true) 場合、その区分はこの塊で初めて 1 文字以上を受信したのと同じ
  /// なので、[_addThinkingChunk] / [_addReplyChunk] と同じ到着解決
  /// ([_resolveThinkingArrival] / [_resolveReplyArrival]) を通す — 通さないと
  /// 返答側は [_replyGateOpen] が開かないまま (受信した 1 文字が永久に出現し
  /// ない) になり、思考側は [_thinkingStarted] が立たないまま (枠が出ない)
  /// になる。
  void complete() {
    final thinkingCompleted = _thinkingClock.complete();
    final replyCompleted = _replyClock.complete();
    _isComplete = true;
    _resolveOrDefer(
      (now) => _resolveComplete(
        now,
        thinkingCompleted: thinkingCompleted,
        replyCompleted: replyCompleted,
      ),
    );
    _refreshNeedsTicks();
    notifyListeners();
  }

  void _resolveComplete(
    Duration now, {
    required bool thinkingCompleted,
    required bool replyCompleted,
  }) {
    if (thinkingCompleted) {
      _thinkingStarted = true;
      _resolveThinkingArrival(now);
    }
    if (replyCompleted) {
      _resolveReplyArrival(now);
    }
    // 思考の到着が (U+FFFD の経路などで) ここで初めて解決され、かつ
    // まだ秒数が確定していなければ、ここで確定させる — 返答の到着が
    // 既にあればそこまでの秒数、無ければ complete までの秒数にする。
    // 返答の到着が思考の到着より前 (思考の解決がこの complete まで遅れた)
    // 場合は差が負になり得るので 0 に切り上げる。
    if (_thinkingArrivedAt != null && _thinkingSeconds == null) {
      final until = _replyArrivedAt ?? now;
      final elapsed = until - _thinkingArrivedAt!;
      _thinkingSeconds = _roundSeconds(elapsed.isNegative ? Duration.zero : elapsed);
    }
    if (_thinkingClock.pendingCountAt(now) > 0) {
      _thinkingClock.fastForward(now);
    }
    if (_replyGateOpen && _replyClock.pendingCountAt(now) > 0) {
      _replyClock.fastForward(now);
    }
  }

  /// 時計を進める。[now] は単調増加の経過時間。
  void tick(Duration now) {
    if (_deferredArrivals.isNotEmpty) {
      final arrivals = _deferredArrivals.toList();
      _deferredArrivals.clear();
      for (final resolve in arrivals) {
        resolve(now);
      }
    }

    _refreshNeedsTicks();
    final wasActive = needsTicks;
    _lastTickNow = now;
    _now = now;

    var transitioned = false;
    if (_collapseReady(now)) {
      _collapsed = true;
      _collapseStartedAt = now;
      _userExpanded = false;
      transitioned = true;
    }
    if (_collapsed && !_replyGateOpen && now - _collapseStartedAt! >= collapseDuration) {
      _replyGateOpen = true;
      if (_isComplete) {
        _replyClock.fastForward(now);
      } else {
        _replyClock.scheduleFromArrival(now);
      }
      transitioned = true;
    }

    _refreshNeedsTicks();
    if (wasActive || transitioned) notifyListeners();
  }

  /// 思考の枠のタップ: 1 行 ⇄ 全部 (思考中) / 畳み ⇄ 全部 (畳んだ後)。
  void toggleThinkingFrame() {
    _userExpanded = !_userExpanded;
    notifyListeners();
  }

  int _roundSeconds(Duration elapsed) =>
      (elapsed.inMicroseconds / Duration.microsecondsPerSecond).round();
}
