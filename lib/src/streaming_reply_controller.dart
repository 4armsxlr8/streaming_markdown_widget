import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chunk.dart';
import 'reveal_clock.dart';
import 'streaming_reply_style.dart';

export 'chunk.dart';
export 'reveal_clock.dart' show RevealingChar;

/// State of the thinking frame: none / one line / full / collapsed.
enum ThinkingFrameState {
  /// Not a single thinking chunk has arrived yet.
  none,

  /// The single-line display shown while the thinking is still arriving.
  line,

  /// The expanded display showing the whole thinking text (reachable both
  /// while it is still arriving and after it has been collapsed).
  full,

  /// The collapsed thinking display, showing only the headline row.
  collapsed,
}

/// The observed values held one per section, one for the thinking and one
/// for the reply.
///
/// The type of [StreamingReplyController.thinking] /
/// [StreamingReplyController.reply].
abstract class RevealSection {
  /// Number of characters received (grapheme clusters; an unpaired surrogate
  /// is not counted).
  int get receivedCount;

  /// Number of displayed characters (those whose opacity has reached 1).
  int get displayedCount;

  /// The characters currently revealing (they have started to reveal but
  /// their opacity is still below 1). In ascending index order.
  List<RevealingChar> get revealing;

  /// Number of characters that have started to reveal = [displayedCount]
  /// plus the number of elements in [revealing].
  int get startedCount;

  /// The remainder that has not started to reveal yet = [receivedCount] -
  /// [startedCount].
  int get pendingCount;

  /// The whole received text (an unpaired surrogate is not included).
  String get text;

  /// The text up to and including what has started to reveal (cut at a
  /// grapheme cluster boundary).
  String get revealedText;
}

/// A read-only observed value that looks into a [RevealClock] through a
/// [Duration Function()].
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

/// The entry point of the reply widget.
///
/// A [ChangeNotifier] that updates the observed values for the thinking and
/// for the reply ([thinking] / [reply]) and the state of the thinking frame
/// ([thinkingFrame]) as it receives chunks ([Chunk]) through [addChunk], is
/// told that receiving is complete through [complete], and has its clocks
/// advanced through [tick].
///
/// The thinking and the reply each hold one [RevealClock] of their own (the
/// reveal machinery). Once the first reply chunk arrives, what is left of the
/// thinking is fast-forwarded until it has all been revealed, and only after
/// the thinking frame has been collapsed (the collapse takes 300ms) does the
/// reply's clock start to advance.
class StreamingReplyController extends ChangeNotifier {
  StreamingReplyController({StreamingReplyStyle? style})
    : style = style ?? StreamingReplyStyle();

  /// Timing values this controller reads: [StreamingReplyStyle.revealInterval]
  /// (the clocks' base interval), [StreamingReplyStyle.fadeDuration]
  /// ([RevealSection.displayedCount] / [RevealSection.revealing]),
  /// [StreamingReplyStyle.catchUpBudget] / [StreamingReplyStyle.fastForwardBudget]
  /// / [StreamingReplyStyle.minRevealInterval] (all baked into
  /// [_thinkingClock] / [_replyClock] at construction), and
  /// [StreamingReplyStyle.thinkingCollapseDuration] (the collapse threshold in
  /// [tick]). The same-named values on the `style` passed to
  /// [StreamingReply]/[RevealedMarkdown]/[ThinkingFrame] are a separate
  /// instance and are not used here.
  final StreamingReplyStyle style;

  /// Backlog (characters) that triggers catch-up in [RevealClock
  /// .scheduleFromArrival], derived from `catchUpBudget ÷ revealInterval` so
  /// the two stay consistent (e.g. 600ms ÷ 25ms = 24).
  late final int _catchUpThreshold =
      style.catchUpBudget.inMicroseconds ~/ style.revealInterval.inMicroseconds;

  RevealClock _newClock() => RevealClock(
    normalInterval: style.revealInterval,
    catchUpThreshold: _catchUpThreshold,
    catchUpBudget: style.catchUpBudget,
    fastForwardBudget: style.fastForwardBudget,
    minInterval: style.minRevealInterval,
    fade: style.fadeDuration,
  );

  late final RevealClock _thinkingClock = _newClock();
  late final RevealClock _replyClock = _newClock();

  Duration _now = Duration.zero;

  /// The `now` of the most recent [tick]. Used as the arrival time for
  /// [addChunk] / [complete] (before the first tick, [Duration.zero]).
  Duration? _lastTickNow;

  /// Flag (false by default) that defers the arrival-time-dependent work of
  /// [addChunk] / [complete] while `TickerMode` is disabled or the app is in
  /// the background (that is, while frames are not running). The widget
  /// (`RevealTicker`) sets it by looking at the actual `Ticker` state — the
  /// Controller does not itself infer whether frames are running; it is told
  /// by the widget.
  bool framesPaused = false;

  /// Queue that holds the arrival-time-dependent work (the reveal
  /// scheduling) for chunks that arrived while [framesPaused] was true, or
  /// while [_deferredArrivals] was not yet empty, so that it can be done with
  /// the `now` of the next [tick].
  final List<void Function(Duration now)> _deferredArrivals = [];

  bool _thinkingStarted = false;
  bool _collapsed = false;
  Duration? _collapseStartedAt;
  bool _userExpanded = false;

  Duration? _thinkingArrivedAt;
  Duration? _replyArrivedAt;
  int? _thinkingSeconds;
  int? _thinkingSecondsOverride;

  /// The subscription held by [attach] (null if there is none).
  StreamSubscription<Chunk>? _subscription;

  /// Whether the reply's clock may start scheduling reveals. True from the
  /// start if no thinking chunk ever arrived; if one did, false until the
  /// collapse has finished.
  bool _replyGateOpen = false;

  bool _isComplete = false;

  /// Set by [dispose]. Once true, [tick] / [addChunk] / [complete] /
  /// [toggleThinkingFrame] return immediately without calling
  /// [notifyListeners] (a disposed [ChangeNotifier] throws if notified) — a
  /// call arriving after [dispose] (a stray `Ticker` tick from a widget that
  /// hasn't unmounted yet, for instance) is ignored.
  bool _disposed = false;

  late final RevealSection thinking = _RevealSectionView(
    _thinkingClock,
    () => _now,
  );

  late final RevealSection reply = _RevealSectionView(_replyClock, () => _now);

  /// State of the thinking frame: none / one line / full / collapsed.
  ThinkingFrameState get thinkingFrame {
    if (!_thinkingStarted) return ThinkingFrameState.none;
    if (_userExpanded) return ThinkingFrameState.full;
    return _collapsed ? ThinkingFrameState.collapsed : ThinkingFrameState.line;
  }

  /// The thinking clock is running (from when thinking chunks start arriving
  /// until the collapse begins).
  bool get isThinking => _thinkingStarted && !_collapsed;

  /// The n in the "thought for n seconds" headline. Null before it is
  /// settled. If [thinkingSecondsOverride] is set, that is returned instead
  /// of the measured value.
  int? get thinkingSeconds => _thinkingSecondsOverride ?? _thinkingSeconds;

  /// Pins [thinkingSeconds] to a fixed value in place of the measured one.
  /// Setting it back to null restores the measured value. A negative value
  /// throws [ArgumentError]. A call arriving after [dispose] is ignored (the
  /// value is left unchanged and nothing is thrown, even for a negative
  /// value) and notifies listeners only when the value actually changes.
  int? get thinkingSecondsOverride => _thinkingSecondsOverride;

  set thinkingSecondsOverride(int? value) {
    if (_disposed) return;
    if (value != null && value < 0) {
      throw ArgumentError.value(
        value,
        'thinkingSecondsOverride',
        'must not be negative',
      );
    }
    final changed = value != _thinkingSecondsOverride;
    _thinkingSecondsOverride = value;
    if (changed && !_disposed) notifyListeners();
  }

  /// Receiving is complete.
  bool get isComplete => _isComplete;

  /// While frames are not running ([framesPaused]), or while the deferral
  /// queue ([_deferredArrivals]) is not yet empty, arrival-time-dependent
  /// work is not done right away but deferred ([_resolveOrDefer]).
  bool get _mustDefer => framesPaused || _deferredArrivals.isNotEmpty;

  /// Whether the collapse may begin: nothing has been collapsed yet, the
  /// thinking has started, either the reply has arrived or receiving is
  /// complete, and as of [now] there is nothing of the thinking left
  /// unrevealed. Used both by [tick] (to decide whether to actually begin the
  /// collapse) and by [needsTicks] (to detect that the conditions for
  /// beginning the collapse are met but no tick has arrived yet).
  bool _collapseReady(Duration now) =>
      !_collapsed &&
      _thinkingStarted &&
      (_replyArrivedAt != null || _isComplete) &&
      _thinkingClock.pendingCountAt(now) == 0;

  bool _needsTicksCache = false;

  /// There are characters still revealing or still unrevealed, or a collapse
  /// is in progress → the signal for the widget to run a Ticker.
  ///
  /// This does no more than return a value that is recomputed and held every
  /// time [tick] / [addChunk] / [complete] change the state (the widget side
  /// also reads it several times within one frame, so it must not scan the
  /// whole length each of those times).
  bool get needsTicks => _needsTicksCache;

  bool _computeNeedsTicks() {
    if (_thinkingClock.displayedCountAt(_now) < _thinkingClock.receivedCount) {
      return true;
    }
    if (_replyClock.displayedCountAt(_now) < _replyClock.receivedCount) {
      return true;
    }
    if (_collapsed && !_replyGateOpen) return true;
    // The time-dependent work for the arrivals and completions that came in
    // while the Ticker was stopped has not been done yet (it is done on the
    // next tick).
    if (_deferredArrivals.isNotEmpty) return true;
    // The thinking has been fully revealed and the conditions for beginning
    // the collapse are met, but no tick has arrived yet, so the collapse has
    // not begun (if ticks stay stopped like this, the display is left stuck
    // on the "thinking" headline).
    if (_collapseReady(_now)) return true;
    return false;
  }

  void _refreshNeedsTicks() {
    _needsTicksCache = _computeNeedsTicks();
  }

  /// Resolves an arrival (the work that depends on `now`). If not
  /// [_mustDefer], calls [resolve] right away with the `now` of the most
  /// recent [tick] ([_lastTickNow]; [Duration.zero] before the first tick);
  /// if [_mustDefer], pushes it onto [_deferredArrivals] and defers it until
  /// the `now` of the next [tick] — while frames are stopped [_lastTickNow]
  /// can be stale, and using it as the arrival time would make everything
  /// still revealing jump to displayed all at once on the next frame,
  /// breaking the character-by-character reveal. The reason it also defers
  /// while entries remain in [_deferredArrivals] is that the arrivals queued
  /// there have not been resolved yet and still carry the old `now` — using
  /// the most recent `now` here would mean that, when the deferred arrivals
  /// are all resolved together on the next [tick], this chunk alone is
  /// treated as having moved ahead of them.
  void _resolveOrDefer(void Function(Duration now) resolve) {
    if (_mustDefer) {
      _deferredArrivals.add(resolve);
    } else {
      resolve(_lastTickNow ?? Duration.zero);
    }
  }

  /// Subscribes to [stream]: each element calls [addChunk], and the end of
  /// the Stream calls [complete]. If an error arrives, what has been received
  /// so far is fast-forwarded with [complete] and then [onError] (if one was
  /// passed) is called. Only one Stream may be attached to a single
  /// Controller; attaching a second one throws [StateError]. Calling
  /// [addChunk] by hand after attaching still works. [dispose] cancels the
  /// subscription, so no further elements arrive after that. A call arriving
  /// after [dispose] is ignored (no subscription is created, and no
  /// [StateError] is thrown even for a second call).
  void attach(
    Stream<Chunk> stream, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (_disposed) return;
    if (_subscription != null) {
      throw StateError(
        'StreamingReplyController.attach is already attached to a Stream',
      );
    }
    _subscription = stream.listen(
      addChunk,
      onDone: complete,
      onError: (Object error, StackTrace stackTrace) {
        complete();
        onError?.call(error, stackTrace);
      },
      // Without this, a chunk queued right before an error would still be
      // delivered to this (by then already completed) Controller after the
      // error — cancelOnError stops the subscription the moment the error
      // arrives, so nothing past it is delivered.
      cancelOnError: true,
    );
  }

  /// Delivers a chunk. A call arriving after [dispose] is ignored.
  void addChunk(Chunk chunk) {
    if (_disposed) return;
    switch (chunk.kind) {
      case ChunkKind.thinking:
        _addThinkingChunk(chunk.text);
      case ChunkKind.reply:
        _addReplyChunk(chunk.text);
    }
    _refreshNeedsTicks();
    notifyListeners();
  }

  /// Sets [_thinkingStarted] to true and resolves the arrival
  /// ([_resolveOrDefer]) as soon as at least one thinking grapheme cluster
  /// has been received. A zero-character chunk (an empty string, or a chunk
  /// that is nothing but a dangling high surrogate) only accumulates
  /// characters; it does not run the thinking transition (setting
  /// [_thinkingStarted], settling the arrival time).
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

  /// Resolves the arrival (settling [_replyArrivedAt], fast-forwarding the
  /// thinking, opening the gate) as soon as at least one reply grapheme
  /// cluster has been received. A zero-character chunk only accumulates
  /// characters.
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
        // If no thinking ever arrived, the reply runs without waiting for a
        // collapse.
        _replyGateOpen = true;
      }
    }
    if (_replyGateOpen) {
      _replyClock.scheduleFromArrival(now);
    }
  }

  /// Receiving is complete. First, if the thinking clock or the reply clock
  /// still holds a dangling high surrogate, settle it
  /// ([RevealClock.complete]). [_isComplete] is set synchronously (so that
  /// [needsTicks] and the widget can observe it immediately). The work that
  /// depends on `now` (settling the "thought for n seconds" value and
  /// fast-forwarding) is done through the same [_resolveOrDefer] as
  /// [addChunk].
  ///
  /// If [RevealClock.complete] settled a dangling high surrogate as U+FFFD
  /// (returning true), that section is in the same position as having
  /// received its first character or more in this chunk, so it is put through
  /// the same arrival resolution as [_addThinkingChunk] / [_addReplyChunk]
  /// ([_resolveThinkingArrival] / [_resolveReplyArrival]) — without that, on
  /// the reply side [_replyGateOpen] would never open (the one received
  /// character would never be revealed), and on the thinking side
  /// [_thinkingStarted] would never be set (the frame would not appear).
  ///
  /// A call arriving after [dispose] is ignored.
  void complete() {
    if (_disposed || _isComplete) return;
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
    // If the thinking's arrival is resolved here for the first time (through
    // the U+FFFD path, for instance) and the seconds have not been settled
    // yet, settle them here — if the reply has already arrived, the seconds
    // up to that point; if not, the seconds up to complete. If the reply
    // arrived before the thinking did (because the thinking's resolution was
    // deferred all the way to this complete), the difference can be negative,
    // so it is raised to 0.
    if (_thinkingArrivedAt != null && _thinkingSeconds == null) {
      final until = _replyArrivedAt ?? now;
      final elapsed = until - _thinkingArrivedAt!;
      _thinkingSeconds = _roundSeconds(
        elapsed.isNegative ? Duration.zero : elapsed,
      );
    }
    if (_thinkingClock.pendingCountAt(now) > 0) {
      _thinkingClock.fastForward(now);
    }
    if (_replyGateOpen && _replyClock.pendingCountAt(now) > 0) {
      _replyClock.fastForward(now);
    }
  }

  /// Advances the clocks. [now] is monotonically increasing elapsed time.
  ///
  /// A call arriving after [dispose] is ignored (a stray `Ticker` tick can
  /// still land here for one frame while the widget that owns it is
  /// unmounting).
  void tick(Duration now) {
    if (_disposed) return;
    final arrivalsResolved = _deferredArrivals.isNotEmpty;
    if (arrivalsResolved) {
      final arrivals = _deferredArrivals.toList();
      _deferredArrivals.clear();
      for (final resolve in arrivals) {
        resolve(now);
      }
    }

    // The cached value from before this tick, used as-is: recomputing here
    // (before `_now` is updated below) would only return the same value.
    final wasActive = needsTicks;
    final nowChanged = now != _now;
    _lastTickNow = now;
    _now = now;

    var transitioned = false;
    if (_collapseReady(now)) {
      _collapsed = true;
      _collapseStartedAt = now;
      _userExpanded = false;
      transitioned = true;
    }
    if (_collapsed &&
        !_replyGateOpen &&
        now - _collapseStartedAt! >= style.thinkingCollapseDuration) {
      _replyGateOpen = true;
      if (_isComplete) {
        _replyClock.fastForward(now);
      } else {
        _replyClock.scheduleFromArrival(now);
      }
      transitioned = true;
    }

    if (arrivalsResolved || transitioned || nowChanged) _refreshNeedsTicks();
    if (wasActive || transitioned) notifyListeners();
  }

  /// A tap on the thinking frame: one line ⇄ full (while thinking) /
  /// collapsed ⇄ full (after the collapse). A call arriving after [dispose]
  /// is ignored.
  void toggleThinkingFrame() {
    if (_disposed) return;
    _userExpanded = !_userExpanded;
    notifyListeners();
  }

  int _roundSeconds(Duration elapsed) =>
      (elapsed.inMicroseconds / Duration.microsecondsPerSecond).round();

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
