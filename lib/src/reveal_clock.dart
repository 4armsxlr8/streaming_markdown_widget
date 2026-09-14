import 'package:flutter/widgets.dart' show StringCharacters;

/// One character (grapheme) that is mid-reveal, and its opacity.
///
/// [opacity] ranges from 0 (transparent) to 1 (opaque). Only characters that
/// have started revealing but haven't reached 1 yet appear as this type (see
/// [RevealClock.revealingAt]).
class RevealingChar {
  const RevealingChar({
    required this.index,
    required this.char,
    required this.opacity,
  });

  /// The grapheme's running index (0-based) within the received text.
  final int index;

  /// The character itself (one grapheme).
  final String char;

  /// Opacity (0–1).
  final double opacity;
}

/// Computes opacity (0–1) from elapsed time since a character started
/// revealing ([elapsed]) and the fade duration ([fade]). This is the shared
/// gradient used by both [RevealClock.revealingAt] and the rendering side
/// (`_RevealCursor.consume` in `revealed_markdown.dart`).
double revealOpacity(Duration elapsed, Duration fade) =>
    (elapsed.inMicroseconds / fade.inMicroseconds).clamp(0, 1);

/// The clock behind revealing characters one at a time.
///
/// Holds the received sequence of graphemes and assigns each character a
/// time (a base value) at which it starts revealing. Pure Dart, independent
/// of Flutter widgets. All times are [Duration] (elapsed time) — this class
/// knows nothing about `Widget` or `Ticker`.
///
/// The base reveal interval is 40 characters/sec = 25ms. The moment the
/// unrevealed backlog ([pendingCountAt]) exceeds the catch-up threshold, or
/// the moment [fastForward] is called, a speed is decided once from the
/// backlog at that instant and assigned to the rest (decided from "the
/// backlog at the moment it kicked in," not recomputed from the backlog on
/// every frame).
///
/// If a surrogate pair is split across a chunk boundary, it isn't counted as
/// a character ([receivedCount] / [text] exclude it) until the grapheme
/// closes.
///
/// [RevealClock] is not itself public — every time value it needs
/// ([normalInterval], [catchUpThreshold], [catchUpBudget],
/// [fastForwardBudget], [minInterval], [fade]) is a required constructor
/// argument, supplied by [StreamingReplyController] from its own `style` (see
/// [StreamingReplyController.style]).
class RevealClock {
  RevealClock({
    required this.normalInterval,
    required this.catchUpThreshold,
    required this.catchUpBudget,
    required this.fastForwardBudget,
    required this.minInterval,
    required this.fade,
  });

  /// The base reveal interval (40 characters/sec).
  final Duration normalInterval;

  /// Backlog (characters) that triggers catch-up in [scheduleFromArrival].
  final int catchUpThreshold;

  /// Budget to clear a backlog once catch-up kicks in ([scheduleFromArrival]).
  final Duration catchUpBudget;

  /// Budget to reveal the remaining characters once streaming completes
  /// ([fastForward]).
  final Duration fastForwardBudget;

  /// The fastest interval catch-up ([_scheduleCatchUpTail]) and fast-forward
  /// ([fastForward]) may shrink to (one character per frame). Their assigned
  /// interval never drops below this, however large the backlog or however
  /// short [catchUpBudget] / [fastForwardBudget] is — the backlog may stay
  /// above [catchUpThreshold] instead.
  final Duration minInterval;

  /// Time for one character's opacity to go from 0 to 1 ([revealingAt],
  /// [displayedCountAt]).
  final Duration fade;

  /// Received graphemes (only ones whose surrogates are closed).
  final List<String> _chars = [];

  /// Each grapheme's reveal start time. Null for a character not yet assigned.
  final List<Duration?> _startTimes = [];

  /// A high surrogate split at a chunk boundary that hasn't closed yet.
  String? _danglingHighSurrogate;

  /// Number of received characters (graphemes; an unclosed surrogate doesn't count).
  int get receivedCount => _chars.length;

  /// The full received text (excludes an unclosed surrogate). Memoized:
  /// [appendOnly] and [complete] are the only ways [_chars] changes, and both
  /// invalidate this cache.
  String? _textCache;
  String get text => _textCache ??= _chars.join();

  /// Receives a chunk's text without assigning reveal times.
  ///
  /// Used to hold onto chunks that shouldn't start revealing yet — e.g.
  /// while waiting for the thinking frame to collapse. Assignment happens
  /// later via [scheduleFromArrival] or [fastForward].
  void appendOnly(String chunkText) {
    final combined = (_danglingHighSurrogate ?? '') + chunkText;
    _danglingHighSurrogate = null;

    var toProcess = combined;
    if (toProcess.isNotEmpty) {
      final lastUnit = toProcess.codeUnitAt(toProcess.length - 1);
      // If it ends on a high surrogate (U+D800-U+DBFF), hold it until its
      // matching low surrogate arrives in the next chunk.
      if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) {
        _danglingHighSurrogate = toProcess.substring(toProcess.length - 1);
        toProcess = toProcess.substring(0, toProcess.length - 1);
      }
    }
    if (toProcess.isEmpty) return;
    _textCache = null;
    _revealedTextCachedCount = null;

    // If the previously received grapheme and the new chunk combine into a
    // single grapheme (ZWJ-joined emoji, combining characters, skin-tone
    // modifiers, flags, etc. — any case where a chunk boundary split one in
    // the middle), re-segment "previous grapheme + new chunk" together. If
    // the first grapheme of that absorbs the previous one, replace the
    // previous entry (keeping its reveal start time in [_startTimes] as-is).
    var graphemes = toProcess.characters.toList(growable: false);
    if (_chars.isNotEmpty) {
      final merged = (_chars.last + toProcess).characters.toList(
        growable: false,
      );
      if (merged.isNotEmpty && merged.first != _chars.last) {
        _chars[_chars.length - 1] = merged.first;
        graphemes = merged.skip(1).toList(growable: false);
      }
    }

    for (final grapheme in graphemes) {
      _chars.add(grapheme);
      _startTimes.add(null);
    }
  }

  /// Signals that receiving has finished. If there's a pending high
  /// surrogate (one whose matching low surrogate never arrived), it's turned
  /// into U+FFFD (replacement character) and added as one received
  /// character (so it doesn't permanently disappear after receiving ends).
  /// Doesn't assign reveal times itself (the caller does that via
  /// [scheduleFromArrival] or [fastForward]).
  ///
  /// Returns: true if this call resolved a pending high surrogate (i.e. this
  /// is the first time at least one character was received). The caller
  /// ([StreamingReplyController]) uses this to route it through the normal
  /// arrival resolution (thinking-start detection, reply gate opening).
  bool complete() {
    if (_danglingHighSurrogate == null) return false;
    _danglingHighSurrogate = null;
    _chars.add('�');
    _startTimes.add(null);
    _textCache = null;
    _revealedTextCachedCount = null;
    return true;
  }

  /// Assigns reveal start times, by the normal or catch-up rule, to
  /// unassigned characters (and already-assigned characters that haven't
  /// started revealing yet).
  ///
  /// If the backlog exceeds [catchUpThreshold], a catch-up speed is decided
  /// once from the backlog at [eventTime] and brings it back under the
  /// threshold within [catchUpBudget] — unless that speed would fall below
  /// [minInterval], in which case the interval is held at [minInterval] and
  /// the backlog may stay above the threshold. Otherwise, characters are
  /// assigned at the normal interval, continuing the queue of
  /// already-assigned, not-yet-revealed characters (or starting from
  /// [eventTime] if there is none).
  void scheduleFromArrival(Duration eventTime) {
    final unassigned = <int>[];
    final outstanding = <int>[];
    for (var i = 0; i < _startTimes.length; i++) {
      final startTime = _startTimes[i];
      if (startTime == null) {
        unassigned.add(i);
      } else if (startTime >= eventTime) {
        // A character with the same arrival time still joins the queue if
        // time hasn't advanced past it yet (including equality matters:
        // without it, multiple chunks that arrive at the same instant
        // without an intervening tick would all pile onto exactly that
        // arrival time and reveal simultaneously).
        outstanding.add(i);
      }
    }
    if (unassigned.isEmpty) return;

    final pendingAfter = outstanding.length + unassigned.length;
    if (pendingAfter > catchUpThreshold) {
      _scheduleCatchUpTail(
        [...outstanding, ...unassigned],
        eventTime,
        budget: catchUpBudget,
        keepThreshold: catchUpThreshold,
      );
      return;
    }

    var next = outstanding.isNotEmpty
        ? _startTimes[outstanding.last]! + normalInterval
        : eventTime;
    for (final index in unassigned) {
      _startTimes[index] = next;
      next += normalInterval;
    }
  }

  /// Reveals every not-yet-revealed character (both assigned and
  /// unassigned) at a single speed, decided from the backlog at [eventTime],
  /// so they finish within [fastForwardBudget] — unless that would drop
  /// below [minInterval], in which case the interval is held at [minInterval]
  /// and the characters are not all revealed within [fastForwardBudget].
  ///
  /// Used both for the fast-forward at the end of receiving, and for
  /// fast-forwarding thinking once the reply's first chunk arrives.
  ///
  /// If the same character becomes the target of a second [fastForward]
  /// call (e.g. thinking's fast-forward running twice before receiving
  /// completes), the earlier of the two assigned times wins ([min]) — if the
  /// later one won instead, a character that the first fast-forward placed
  /// within [fastForwardBudget] could get pushed past its deadline by the
  /// second (later-`eventTime`-based) assignment.
  void fastForward(Duration eventTime) {
    final tail = <int>[];
    for (var i = 0; i < _startTimes.length; i++) {
      final startTime = _startTimes[i];
      // Same reasoning as scheduleFromArrival for including equality: letting
      // a character that starts (or started) revealing at exactly eventTime
      // slip through would assign the character right after it to that same
      // eventTime, making two characters reveal simultaneously.
      if (startTime == null || startTime >= eventTime) tail.add(i);
    }
    if (tail.isEmpty) return;

    final normalUs = normalInterval.inMicroseconds.toDouble();
    final budgetUs = fastForwardBudget.inMicroseconds.toDouble();
    final minUs = minInterval.inMicroseconds.toDouble();
    final uncappedUs = (budgetUs / tail.length) < normalUs
        ? budgetUs / tail.length
        : normalUs;
    final intervalUs = uncappedUs < minUs ? minUs : uncappedUs;
    for (var j = 0; j < tail.length; j++) {
      final index = tail[j];
      final candidate =
          eventTime + Duration(microseconds: (j * intervalUs).round());
      final existing = _startTimes[index];
      _startTimes[index] = existing == null || candidate < existing
          ? candidate
          : existing;
    }
  }

  /// Assigns [indexes] (ascending, outstanding before unassigned) by the
  /// catch-up rule.
  ///
  /// The first `indexes.length - keepThreshold` characters get the catch-up
  /// speed (held at [minInterval] when `budget ÷ indexes.length` would fall
  /// below it); the remaining [keepThreshold] characters get the normal
  /// speed, continuing right after the last catch-up character.
  void _scheduleCatchUpTail(
    List<int> indexes,
    Duration eventTime, {
    required Duration budget,
    required int keepThreshold,
  }) {
    final total = indexes.length;
    final catchUpCount = total - keepThreshold;
    final uncappedUs = budget.inMicroseconds / total;
    final minUs = minInterval.inMicroseconds.toDouble();
    final catchUpIntervalUs = uncappedUs < minUs ? minUs : uncappedUs;

    for (var j = 0; j < catchUpCount; j++) {
      _startTimes[indexes[j]] =
          eventTime + Duration(microseconds: (j * catchUpIntervalUs).round());
    }

    var next = _startTimes[indexes[catchUpCount - 1]]! + normalInterval;
    for (var k = 0; k < keepThreshold; k++) {
      _startTimes[indexes[catchUpCount + k]] = next;
      next += normalInterval;
    }
  }

  /// Number of characters that have started revealing as of [now].
  int startedCountAt(Duration now) {
    var count = 0;
    for (final startTime in _startTimes) {
      if (startTime != null && startTime <= now) count++;
    }
    return count;
  }

  /// Remaining characters that haven't started revealing as of [now].
  int pendingCountAt(Duration now) => receivedCount - startedCountAt(now);

  /// Characters that have started revealing but haven't reached opacity 1 yet,
  /// as of [now]. Ascending by index.
  List<RevealingChar> revealingAt(Duration now) {
    final result = <RevealingChar>[];
    for (var i = 0; i < _chars.length; i++) {
      final startTime = _startTimes[i];
      if (startTime == null || startTime > now) continue;
      final elapsed = now - startTime;
      if (elapsed >= fade) continue;
      result.add(
        RevealingChar(
          index: i,
          char: _chars[i],
          opacity: revealOpacity(elapsed, fade),
        ),
      );
    }
    return result;
  }

  /// Number of characters whose opacity has reached 1 (fully revealed) as of [now].
  int displayedCountAt(Duration now) {
    var count = 0;
    for (final startTime in _startTimes) {
      if (startTime != null && now - startTime >= fade) count++;
    }
    return count;
  }

  /// The text up through the characters that have started revealing as of
  /// [now] (cut at a grapheme boundary). Memoized by the count of characters
  /// that have started (invalidated by [appendOnly] / [complete] through
  /// [_revealedTextCachedCount]) — repeated calls with the same [now] within
  /// one frame, or a [now] that hasn't crossed another character's start
  /// time, reuse the cached string instead of rejoining it.
  int? _revealedTextCachedCount;
  String? _revealedTextCache;

  String revealedTextAt(Duration now) {
    var count = 0;
    for (var i = 0; i < _chars.length; i++) {
      final startTime = _startTimes[i];
      if (startTime == null || startTime > now) break;
      count++;
    }
    if (_revealedTextCachedCount == count) return _revealedTextCache!;
    final result = _chars.take(count).join();
    _revealedTextCachedCount = count;
    _revealedTextCache = result;
    return result;
  }
}
