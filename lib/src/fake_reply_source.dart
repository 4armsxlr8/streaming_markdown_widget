import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart' show StringCharacters;

import 'reply_theme.dart';
import 'streaming_reply_controller.dart';

/// 作り物の返答の供給 (TDD 対象外)。
///
/// 思考の文 → 返答の順に、塊 ([Chunk]) を [StreamingReplyController] へ
/// 届ける。1 塊は [ReplyTheme.supplyChunkChars] 文字 ([ReplyTheme
/// .supplyLongChunkEvery] 回に 1 回は [ReplyTheme.supplyLongChunkMultiplier]
/// 倍) で、届く間隔は [ReplyTheme.supplyBaseInterval] に [ReplyTheme
/// .supplyIntervalJitterMin]〜[ReplyTheme.supplyIntervalJitterMax] のむらを
/// 掛けたもの (mock.html の `cz-mock-script` の供給ループと同じ値)。文字は
/// 書記素 ([String.characters]) で数える。両方届き切ったら [complete] を呼ぶ。
///
/// [Timer] で実装する。[dispose] を呼ぶと、その時点で残っている Timer を
/// 止め、以後は [controller] へ一切届けない。
class FakeReplySource {
  // `this._controller` にすると外向きの引数名も `_controller` になり
  // (API の下書き通りの) `controller:` で呼べなくなるため、あえて手で代入する。
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

  /// 今流している区分 (最初は思考)。
  ChunkKind _kind = ChunkKind.thinking;

  /// [_kind] に応じた供給元 ([_thinking] か [_reply])。
  List<String> get _source => _kind == ChunkKind.thinking ? _thinking : _reply;

  /// [_source] のうち、まだ届けていない先頭の位置。
  int _position = 0;

  /// 届けた回数 ([ReplyTheme.supplyLongChunkEvery] 回に 1 回のむらに使う)。
  /// 思考から返答に移るときに 0 へ戻す (mock.html と同じ)。
  int _deliveries = 0;

  /// 供給を始める (思考の塊から)。
  void start() => _scheduleNext();

  void _scheduleNext() {
    if (_disposed) return;
    final jitter =
        ReplyTheme.supplyIntervalJitterMin +
        _random.nextDouble() *
            (ReplyTheme.supplyIntervalJitterMax - ReplyTheme.supplyIntervalJitterMin);
    final interval = Duration(
      microseconds: (ReplyTheme.supplyBaseInterval.inMicroseconds * jitter).round(),
    );
    _timer = Timer(interval, _deliver);
  }

  void _deliver() {
    if (_disposed) return;
    var size = ReplyTheme.supplyChunkChars;
    _deliveries++;
    if (_deliveries % ReplyTheme.supplyLongChunkEvery == 0) {
      size *= ReplyTheme.supplyLongChunkMultiplier;
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

  /// 供給を止める。以後 Timer は発火しない。
  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
