import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

/// The base interval at which chunks arrive (the supply delivers 8 chunks
/// per second, hence 1000ms / 8). The actual interval is this multiplied by
/// a variation between [_supplyIntervalJitterMin] and
/// [_supplyIntervalJitterMax] (the same values as the supply loop in
/// mock.html's `cz-mock-script`).
const _supplyBaseInterval = Duration(milliseconds: 125);

const _supplyIntervalJitterMin = 0.5;
const _supplyIntervalJitterMax = 2.0;

/// The base number of characters in one chunk (4, as in mock.html).
const _supplyChunkChars = 4;

/// Once every this many deliveries, the chunk is made
/// [_supplyLongChunkMultiplier] times larger, to create variation.
const _supplyLongChunkEvery = 5;
const _supplyLongChunkMultiplier = 2;

/// The fake reply supply (not a TDD target).
///
/// Delivers chunks ([Chunk]) to a [StreamingReplyController], the thinking
/// text first and the reply second. One chunk is [_supplyChunkChars]
/// characters (every [_supplyLongChunkEvery] deliveries,
/// [_supplyLongChunkMultiplier] times that), and the interval between
/// arrivals is [_supplyBaseInterval] multiplied by a variation between
/// [_supplyIntervalJitterMin] and [_supplyIntervalJitterMax]. Characters are
/// counted as grapheme clusters ([String.characters]). Once both have been
/// fully delivered, [complete] is called.
///
/// Implemented with [Timer]. Calling [dispose] stops whatever Timer is
/// outstanding at that point, and nothing at all is delivered to
/// [controller] after that.
class FakeReplySource {
  // Using `this._controller` would make the outward-facing parameter name
  // `_controller` as well, so it could no longer be called as `controller:`
  // (the name the API draft specifies), hence the deliberate assignment by
  // hand.
  FakeReplySource({
    required StreamingReplyController controller,
    required String thinking,
    required String reply,
    Random? random,
    // ignore: prefer_initializing_formals
  }) : _controller = controller,
       _thinking = thinking.characters.toList(growable: false),
       _reply = reply.characters.toList(growable: false),
       _random = random ?? Random();

  final StreamingReplyController _controller;
  final List<String> _thinking;
  final List<String> _reply;
  final Random _random;

  Timer? _timer;
  bool _disposed = false;

  /// The section currently being supplied (the thinking first).
  ChunkKind _kind = ChunkKind.thinking;

  /// The list being supplied from, according to [_kind] ([_thinking] or
  /// [_reply]).
  List<String> get _source => _kind == ChunkKind.thinking ? _thinking : _reply;

  /// The position in [_source] of the first character not yet delivered.
  int _position = 0;

  /// The number of deliveries made (used for the variation applied once
  /// every [_supplyLongChunkEvery] deliveries). Reset to 0 when moving from
  /// the thinking to the reply (same as mock.html).
  int _deliveries = 0;

  /// Starts the supply (beginning with the thinking chunks).
  void start() => _scheduleNext();

  void _scheduleNext() {
    if (_disposed) return;
    final jitter =
        _supplyIntervalJitterMin +
        _random.nextDouble() *
            (_supplyIntervalJitterMax - _supplyIntervalJitterMin);
    final interval = Duration(
      microseconds: (_supplyBaseInterval.inMicroseconds * jitter).round(),
    );
    _timer = Timer(interval, _deliver);
  }

  void _deliver() {
    if (_disposed) return;
    var size = _supplyChunkChars;
    _deliveries++;
    if (_deliveries % _supplyLongChunkEvery == 0) {
      size *= _supplyLongChunkMultiplier;
    }
    final source = _source;
    final end = min(_position + size, source.length);
    final text = source.sublist(_position, end).join();
    _position = end;
    if (text.isNotEmpty) {
      _controller.addChunk(Chunk(text, kind: _kind));
    }

    if (_position < source.length) {
      _scheduleNext();
      return;
    }
    if (_kind == ChunkKind.thinking) {
      _kind = ChunkKind.reply;
      _position = 0;
      _deliveries = 0;
      _scheduleNext();
      return;
    }
    _controller.complete();
  }

  /// Stops the supply. No Timer fires after this.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
