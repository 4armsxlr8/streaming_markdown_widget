import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

/// 公開入口から使う Controller のテスト
/// (AC-9, AC-14, AC-15, AC-16, AC-17, AC-21, AC-24)。
///
/// 主張するのは塊の Stream を繋ぐ入り口 (購読・受信完了・2 本目の拒否・破棄)、
/// 利用側が渡す秒数、返答の最初の塊の後に届いた思考の塊の扱い、そして
/// 追いつき・早送りの速さの上限 (AC-24)。公開入口
/// (`package:streaming_markdown_widget/streaming_markdown_widget.dart`) だけを
/// import して書く — 利用側が書けるコードと同じものでテストを組む。
///
/// 時間は [StreamingReplyController.tick] に [Duration] を直接渡して進めるので、
/// Widget も Ticker も要らない純 Dart のテストとして書く。Stream の配送は
/// [pumpEventQueue] で待つ。
void main() {
  /// 基準の速さ 40 文字/秒 の 1 文字あたりの間隔。
  const revealInterval = Duration(milliseconds: 25);

  /// 受信完了の時点の残りを出し切るまでの猶予 (早送り)。
  const fastForwardBudget = Duration(milliseconds: 400);

  /// 追いつき・早送りの最速の間隔 (1 フレームに 1 文字)。
  const minRevealInterval = Duration(milliseconds: 16);

  /// 追いつきが遅れを消すまでの猶予。
  const catchUpBudget = Duration(milliseconds: 600);

  /// 遅れの上限 (`catchUpBudget ÷ revealInterval` = 24 文字)。
  const catchUpThreshold = 24;

  /// 思考の枠を畳むのにかかる時間。
  const collapseDuration = Duration(milliseconds: 300);

  /// 思考の最初の塊から返答の最初の塊までに進める時間 (「n 秒考えました」の n = 2)。
  const elapsedToReply = Duration(seconds: 2);

  /// 思考の文 (6 文字。150ms で出し切るので 2 秒の時点では未出現の残りが無い)。
  const thinkingText = '考えの要約。';

  /// 返答の文 (5 文字、記法なし)。
  const replyText = '返答の文。';

  /// 返答の最初の塊の後に届く思考の塊。
  const laterThinkingText = '後から届いた思考。';

  /// 畳み終わって返答が流れ始めた Controller を作る (AC-21 の 2 ケースの共通の
  /// 前段)。返り値の時刻は畳みが始まった時刻 ([elapsedToReply])。
  ///
  /// 思考 → 2 秒 → 返答の最初の塊、の順に届けて畳みまで進める。
  StreamingReplyController collapsedController() {
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    controller.tick(Duration.zero);
    controller.tick(elapsedToReply);
    controller.addChunk(const Chunk(replyText));
    controller.tick(elapsedToReply);
    return controller;
  }

  test('AC-9 負の秒数を渡すと ArgumentError', () {
    final controller = StreamingReplyController();
    expect(
      () => controller.thinkingSecondsOverride = -1,
      throwsArgumentError,
      reason: '負の秒数は黙って補正せず ArgumentError で拒否する',
    );
  });

  test(
    'AC-14 思考 2 塊 + 返答 3 塊を流して閉じる Stream を繋ぐと、届いた順に受信し、Stream の終わりで受信完了になる',
    () async {
      final source = StreamController<Chunk>();
      final controller = StreamingReplyController();

      // 利用側は listen も購読の解除も書かない。
      controller.attach(source.stream);

      source.add(const Chunk('考えの', kind: ChunkKind.thinking));
      source.add(const Chunk('要約。', kind: ChunkKind.thinking));
      source.add(const Chunk('返答の'));
      source.add(const Chunk('文の'));
      source.add(const Chunk('続き。'));
      await pumpEventQueue();

      expect(controller.thinking.text, '考えの要約。', reason: '思考の塊が届いた順につながる');
      expect(controller.reply.text, '返答の文の続き。', reason: '返答の塊が届いた順につながる');
      expect(controller.isComplete, isFalse, reason: '前提: Stream はまだ閉じていない');

      await source.close();
      await pumpEventQueue();

      expect(controller.isComplete, isTrue, reason: 'Stream の終わりで受信完了になる');
    },
  );

  test(
    'AC-15 返答 2 塊の後にエラーで終わる Stream を繋ぐと、届いた 2 塊を早送りで出し切って受信完了になり、エラーの通知が 1 回届く',
    () async {
      /// 12 文字の塊 2 つ = 24 文字 (遅れの上限ちょうどなので基準の速さで流れる)。
      const first = 'あいうえおかきくけこさし';
      const second = 'すせそたちつてとなにぬね';
      final failure = StateError('通信が切れた');

      Stream<Chunk> failingStream() async* {
        yield const Chunk(first);
        yield const Chunk(second);
        throw failure;
      }

      final errors = <Object>[];
      final controller = StreamingReplyController();
      controller.attach(
        failingStream(),
        onError: (error, stackTrace) => errors.add(error),
      );
      await pumpEventQueue();

      expect(errors, hasLength(1), reason: 'エラーの通知は 1 回だけ届く');
      expect(errors.single, same(failure), reason: '届くのは Stream が投げたエラーそのもの');
      expect(controller.isComplete, isTrue, reason: 'エラーで終わった Stream も受信完了になる');
      expect(controller.reply.text, '$first$second', reason: '届いた文字は消えない');

      controller.tick(Duration.zero);
      controller.tick(fastForwardBudget);
      expect(
        controller.reply.startedCount,
        24,
        reason:
            'エラーで終わってから 400ms 以内に 24 文字すべてが出現を始める '
            '(基準の速さのままなら 24 文字目は 575ms)',
      );
      expect(controller.reply.pendingCount, 0);
    },
  );

  test(
    'AC-16 Stream を繋いだ Controller にもう 1 本繋ぐと StateError になり、繋いだ後に手で届けた塊は同じ返答に続く',
    () async {
      final source = StreamController<Chunk>();
      final controller = StreamingReplyController();

      controller.attach(source.stream);
      expect(
        () => controller.attach(Stream<Chunk>.empty()),
        throwsStateError,
        reason: '1 つの Controller に繋げる Stream は 1 本で、2 本目は拒否する',
      );

      source.add(const Chunk('Stream で届いた'));
      await pumpEventQueue();
      controller.addChunk(const Chunk('手で届けた'));

      expect(
        controller.reply.text,
        'Stream で届いた手で届けた',
        reason: 'Stream を繋いだ後に手で届けた塊も同じ返答に続く',
      );
    },
  );

  test('AC-17 Stream を繋いだまま Controller を破棄すると購読が解除され、その後に流した塊は届かない', () async {
    final source = StreamController<Chunk>();
    final controller = StreamingReplyController();

    controller.attach(source.stream);
    source.add(const Chunk('破棄の前に届いた'));
    await pumpEventQueue();
    expect(source.hasListener, isTrue, reason: '前提: Controller が購読を持っている');

    controller.dispose();
    source.add(const Chunk('破棄の後に流した'));
    await pumpEventQueue();

    expect(source.hasListener, isFalse, reason: '破棄で購読が解除される');
    expect(
      controller.reply.text,
      '破棄の前に届いた',
      reason: '破棄後の塊は届かない (届けば破棄済みの ChangeNotifier の通知で例外になる)',
    );
  });

  test('AC-21 畳みの最中に思考の塊が届くと、畳まれた本文の末尾に足されるだけで枠は開かず、秒数も変わらず、返答の出現も止まらない', () {
    final controller = collapsedController();
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.collapsed,
      reason: '前提: 思考の枠が畳まれている',
    );
    expect(controller.thinkingSeconds, 2, reason: '前提: 秒数は 2 秒で確定している');

    // 畳み (300ms) の途中に思考の塊が届く。
    controller.addChunk(
      const Chunk(laterThinkingText, kind: ChunkKind.thinking),
    );
    controller.tick(elapsedToReply + const Duration(milliseconds: 100));

    expect(
      controller.thinking.text,
      '$thinkingText$laterThinkingText',
      reason: '畳まれた思考の枠の本文の末尾に足される',
    );
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.collapsed,
      reason: '枠は開かない',
    );
    expect(controller.isThinking, isFalse, reason: '思考の時計は止まったまま');
    expect(controller.thinkingSeconds, 2, reason: '秒数は変わらない');

    // 畳みが終われば返答が流れ始める (後から届いた思考は返答を止めない)。
    controller.tick(elapsedToReply + collapseDuration);
    controller.tick(elapsedToReply + collapseDuration + revealInterval * 4);
    expect(
      controller.reply.startedCount,
      greaterThan(0),
      reason: '畳み終わった後に返答の出現が始まる',
    );
    expect(replyText.startsWith(controller.reply.revealedText), isTrue);
  });

  test(
    'AC-21 畳み終わった後に思考の塊が届いても、畳まれた本文の末尾に足されるだけで枠は開かず、秒数も変わらず、返答の出現も止まらない',
    () {
      final controller = collapsedController();

      // 畳みが終わって返答が流れ始めたところまで進める。
      controller.tick(elapsedToReply + collapseDuration);
      final flowingAt = elapsedToReply + collapseDuration + revealInterval * 2;
      controller.tick(flowingAt);
      final startedBefore = controller.reply.startedCount;
      expect(startedBefore, greaterThan(0), reason: '前提: 返答が流れ始めている');

      controller.addChunk(
        const Chunk(laterThinkingText, kind: ChunkKind.thinking),
      );
      controller.tick(flowingAt + revealInterval * 4);

      expect(
        controller.thinking.text,
        '$thinkingText$laterThinkingText',
        reason: '畳まれた思考の枠の本文の末尾に足される',
      );
      expect(
        controller.thinkingFrame,
        ThinkingFrameState.collapsed,
        reason: '枠は開かない',
      );
      expect(controller.thinkingSeconds, 2, reason: '秒数は変わらない');
      expect(
        controller.reply.startedCount,
        greaterThan(startedBefore),
        reason: '返答の出現は止まらない',
      );
    },
  );

  test('AC-24 100 文字の塊が一度に届くと、追いつきの間隔は最速の 16ms までしか短くならず、'
      '600ms の時点では遅れが上限 (24 文字) を超えて残る', () {
    /// 100 文字の塊。10 文字の並びを 10 回。
    final longChunkText = 'あいうえおかきくけこ' * 10;
    expect(longChunkText.length, 100, reason: '前提: 塊は 100 文字');

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(longChunkText));

    // 追いつきの割り当て間隔 = max(600ms ÷ 100 文字, 16ms) = 16ms。
    controller.tick(Duration.zero);
    expect(controller.reply.startedCount, 1, reason: '最初の文字は塊の到着時刻に出現を始める');
    controller.tick(minRevealInterval);
    expect(
      controller.reply.startedCount,
      2,
      reason:
          '2 文字目は 16ms に始まる '
          '(上限が無ければ 600ms ÷ 100 = 6ms 間隔なので 16ms では 3 文字目まで始まっている)',
    );
    controller.tick(minRevealInterval * 2);
    expect(
      controller.reply.startedCount,
      3,
      reason: '3 文字目は 32ms に始まる (16ms 間隔を保つ)',
    );

    controller.tick(catchUpBudget);
    expect(
      controller.reply.startedCount,
      38,
      reason:
          '600ms までに出現を始めるのは 16ms 間隔の 38 文字 (0ms〜592ms) だけ '
          '(上限が無ければ 6ms 間隔で 82 文字)',
    );
    expect(
      controller.reply.pendingCount,
      greaterThan(catchUpThreshold),
      reason:
          '遅れは追いつきの上限 600ms を超えて溜まってよい '
          '(600ms の時点の残りは 62 文字で、上限の $catchUpThreshold 文字より多い)',
    );

    // 出し切るのは 1.6 秒 — 先頭 76 文字 (= 100 − 24) を 16ms 間隔で
    // 0ms〜1200ms、残り 24 文字を基準の 25ms 間隔で 1225ms〜1800ms。
    controller.tick(const Duration(milliseconds: 1200));
    expect(
      controller.reply.startedCount,
      76,
      reason: '1200ms までに始まるのは 16ms 間隔の先頭 76 文字',
    );
    controller.tick(const Duration(milliseconds: 1800));
    expect(
      controller.reply.pendingCount,
      0,
      reason: '残り 24 文字は基準の 25ms 間隔で 1800ms までに出し切る',
    );
  });

  test('AC-24 残り 100 文字で受信完了すると、早送りの間隔も最速の 16ms までしか短くならず、'
      '出し切るのに 1.6 秒かかる', () {
    /// 100 文字の塊。10 文字の並びを 10 回。
    final longChunkText = 'あいうえおかきくけこ' * 10;
    expect(longChunkText.length, 100, reason: '前提: 塊は 100 文字');

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(longChunkText));
    controller.complete();

    // 早送りの割り当て間隔 = max(min(400ms ÷ 100 文字, 25ms), 16ms) = 16ms。
    controller.tick(Duration.zero);
    expect(
      controller.reply.pendingCount,
      99,
      reason: '早送りでも残りを一度に出すのではなく 1 文字ずつ出す',
    );

    controller.tick(fastForwardBudget);
    expect(
      controller.reply.startedCount,
      26,
      reason:
          '早送りの猶予 400ms までに始まるのは 16ms 間隔の 26 文字 (0ms〜400ms) だけ '
          '(上限が無ければ 4ms 間隔で 100 文字すべて)',
    );
    expect(
      controller.reply.pendingCount,
      74,
      reason: '受信完了の猶予を過ぎても残りは残ってよい (400ms の時点で 74 文字)',
    );

    // 100 文字 × 16ms 間隔 = 最後の文字が 99 × 16ms = 1584ms に始まる。
    controller.tick(const Duration(milliseconds: 1568));
    expect(
      controller.reply.pendingCount,
      1,
      reason: '1568ms の時点では最後の 1 文字がまだ出現を始めていない',
    );
    controller.tick(const Duration(milliseconds: 1584));
    expect(
      controller.reply.pendingCount,
      0,
      reason: '100 文字を 16ms 間隔で出し切るので、最後の文字は 1584ms に出現を始める',
    );
  });
}
