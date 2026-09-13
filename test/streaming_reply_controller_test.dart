import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

/// 返答の Widget の入り口 ([StreamingReplyController]) と、1 文字ずつの出現の
/// 時計のテスト (AC-2, AC-3, AC-4, AC-5, AC-6, AC-12, AC-20)。
///
/// spec の受け入れ基準では seam が「返答の Widget」だが、要件「返答の Widget の
/// 入り口と観測」が定めるとおり、この Controller が入り口であり観測値
/// (受信した文字数・表示済みの文字数・出現中の文字と不透明度・思考の枠の状態) の
/// 正本。そこで時計の進み方はここで主張し、描画 (TextSpan・不透明度の見た目) は
/// 後続のスライスの widget test に置く。
///
/// 時間は [StreamingReplyController.tick] に [Duration] を直接渡して進めるので、
/// Widget も Ticker も要らない純 Dart のテストとして書く。
void main() {
  /// 基準の速さ 40 文字/秒 の 1 文字あたりの間隔。
  const revealInterval = Duration(milliseconds: 25);

  /// 1 文字の不透明度が 0 から 1 になるまでの時間。
  const fadeDuration = Duration(milliseconds: 300);

  /// 遅れの上限。未出現の残りがこの文字数を超えた瞬間に追いつきへ切り替わる。
  const catchUpThreshold = 24;

  /// 追いつきが遅れを上限以下へ戻すまでの猶予。
  const catchUpBudget = Duration(milliseconds: 600);

  /// 受信完了の時点の残りを出し切るまでの猶予 (早送り)。
  const fastForwardBudget = Duration(milliseconds: 400);

  /// 思考の本文を畳むのにかかる時間。
  const collapseDuration = Duration(milliseconds: 300);

  /// 時刻を細かく追うときの刻み。
  ///
  /// 追いつき・早送り・畳みの切り替わる瞬間は実装が何ミリ秒に置くか
  /// (文字の出現開始時刻そのものか、それを観測した tick か) で 1 刻み分ずれる。
  /// 実機の 1 フレーム (16ms) より細かい 10ms で追い、境界の主張には
  /// この刻み分の余裕を足す。
  const frameInterval = Duration(milliseconds: 10);

  /// 不透明度の比較に許す誤差。値は割り算 1 回で出る (経過 ÷ 300ms)。
  const opacityTolerance = 1e-9;

  /// [section] の出現中の文字のうち通し番号が [index] のものの不透明度。
  /// 出現中に無ければ (まだ出現していない / 表示済み) null。
  double? opacityOf(RevealSection section, int index) {
    for (final revealingChar in section.revealing) {
      if (revealingChar.index == index) return revealingChar.opacity;
    }
    return null;
  }

  /// 出現中の文字の通し番号を並び順のまま取り出す。
  List<int> revealingIndexes(RevealSection section) =>
      section.revealing.map((revealingChar) => revealingChar.index).toList();

  test('AC-2 4 文字の塊が 1 つ届くと、25ms ごとに 1 文字ずつ出現を始め、各文字は出現開始から 300ms で表示済みになる', () {
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk('画面表示'));

    controller.tick(Duration.zero);
    expect(controller.reply.receivedCount, 4);
    expect(
      controller.reply.startedCount,
      1,
      reason: '最初の文字は塊の到着時刻に出現を始める',
    );
    expect(controller.reply.displayedCount, 0, reason: '届いた瞬間には文字が見えない');
    expect(controller.reply.revealing.single.index, 0);
    expect(controller.reply.revealing.single.char, '画');
    expect(controller.reply.revealing.single.opacity, closeTo(0, opacityTolerance));

    controller.tick(revealInterval);
    expect(controller.reply.startedCount, 2);
    controller.tick(revealInterval * 2);
    expect(controller.reply.startedCount, 3);
    controller.tick(revealInterval * 3);
    expect(
      controller.reply.startedCount,
      4,
      reason: '4 文字目は 75ms 後に出現を始める',
    );

    // 不透明度は「その文字の出現開始からの経過 ÷ 300ms」。
    controller.tick(const Duration(milliseconds: 150));
    expect(
      opacityOf(controller.reply, 0),
      closeTo(0.5, opacityTolerance),
      reason: '1 文字目は 0ms に始まったので (150 - 0) ÷ 300',
    );
    expect(
      opacityOf(controller.reply, 3),
      closeTo(0.25, opacityTolerance),
      reason: '4 文字目は 75ms に始まったので (150 - 75) ÷ 300',
    );

    controller.tick(fadeDuration);
    expect(
      controller.reply.displayedCount,
      1,
      reason: '1 文字目は 0ms + 300ms で不透明度 1 に達する',
    );
    expect(
      revealingIndexes(controller.reply),
      orderedEquals(<int>[1, 2, 3]),
      reason: '表示済みに移った文字は出現中から外れる',
    );

    controller.tick(fadeDuration + revealInterval);
    expect(controller.reply.displayedCount, 2);
    controller.tick(fadeDuration + revealInterval * 2);
    expect(controller.reply.displayedCount, 3);
    controller.tick(fadeDuration + revealInterval * 3);
    expect(controller.reply.displayedCount, 4);
    expect(controller.reply.revealing, isEmpty);
    expect(controller.reply.revealedText, '画面表示');
  });

  test('AC-3 塊が届かないまま時間が経つと、未出現の文字が無くなった時点で表示が止まる', () {
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk('画面表示'));
    controller.tick(fadeDuration + revealInterval * 3);

    expect(controller.reply.displayedCount, 4, reason: '前提: 4 文字すべてが表示済み');
    expect(controller.reply.revealing, isEmpty, reason: '前提: 出現中の文字が無い');
    expect(controller.isComplete, isFalse, reason: '前提: 受信完了はまだ来ていない');
    expect(
      controller.needsTicks,
      isFalse,
      reason: '未出現も出現中も無いので Widget が Ticker を回す必要はない',
    );

    final revealedText = controller.reply.revealedText;
    for (final now in const <Duration>[
      Duration(milliseconds: 1000),
      Duration(milliseconds: 5000),
    ]) {
      controller.tick(now);
      expect(controller.reply.startedCount, 4, reason: '$now: 出現が先へ進まない');
      expect(controller.reply.displayedCount, 4, reason: '$now: 表示済みが増えない');
      expect(
        controller.reply.revealing,
        isEmpty,
        reason: '$now: 不透明度が変わり続ける文字が出てこない',
      );
      expect(controller.reply.revealedText, revealedText, reason: '$now: 表示が動かない');
      expect(controller.needsTicks, isFalse, reason: '$now: Ticker は回さないまま');
    }
  });

  test('AC-4 100 文字の塊が一度に届くと、600ms 以内に未出現の残りが 24 文字以下になり、その後は基準の 25ms 間隔に戻る', () {
    /// 100 文字の塊。10 文字の並びを 10 回。
    final longChunkText = 'あいうえおかきくけこ' * 10;
    expect(longChunkText.length, 100, reason: '前提: 塊は 100 文字');

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(longChunkText));

    // 追いつきの猶予 (600ms) まで細かく進めて、残りが上限以下へ戻った時刻を拾う。
    final catchUpFrames = catchUpBudget.inMilliseconds ~/ frameInterval.inMilliseconds;
    Duration? settledAt;
    for (var frame = 0; frame <= catchUpFrames; frame++) {
      final now = frameInterval * frame;
      controller.tick(now);
      if (settledAt == null && controller.reply.pendingCount <= catchUpThreshold) {
        settledAt = now;
      }
    }
    expect(
      settledAt,
      isNotNull,
      reason:
          '追いつき: 届いてから 600ms 以内に未出現の残りが $catchUpThreshold 文字以下へ戻る '
          '(基準の速さのままなら 600ms 時点の残りは 75 文字)',
    );

    // 基準へ戻ったあとの 250ms は 25ms 間隔ちょうど = 10 文字。
    final startedAtBudget = controller.reply.startedCount;
    final windowFrames = (revealInterval * 10).inMilliseconds ~/ frameInterval.inMilliseconds;
    for (var frame = catchUpFrames + 1; frame <= catchUpFrames + windowFrames; frame++) {
      controller.tick(frameInterval * frame);
    }
    expect(
      controller.reply.startedCount - startedAtBudget,
      10,
      reason: '600ms から 250ms の間に出現を始めるのは 25ms 間隔の 10 文字だけ '
          '(追いつきの速さを保ったままなら 41 文字)',
    );
    expect(
      controller.reply.pendingCount,
      greaterThan(0),
      reason: '前提: この時点ではまだ未出現の残りがある (窓の中で出し切っていない)',
    );
  });

  test('AC-5 残り 20 文字が未出現のまま受信完了すると、400ms 以内に 20 文字すべてが出現を始める', () {
    /// 24 文字の塊。遅れの上限ちょうどなので追いつきには入らず基準の速さで流れる。
    final chunkText = 'あいうえおかきくけこ' * 2 + 'さしすせ';
    expect(chunkText.length, 24, reason: '前提: 塊は 24 文字 (遅れの上限ちょうど)');

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(chunkText));
    controller.tick(Duration.zero);

    final completedAt = revealInterval * 3;
    controller.tick(completedAt);
    expect(
      controller.reply.startedCount,
      4,
      reason: '前提: 基準の速さで 4 文字が出現を始めている',
    );
    expect(controller.reply.pendingCount, 20, reason: '前提: 未出現の残りが 20 文字');

    controller.complete();

    controller.tick(completedAt + revealInterval);
    expect(
      controller.reply.startedCount,
      lessThan(24),
      reason: '早送りは残りを一度に出すのではなく 1 文字ずつ出し切る',
    );

    controller.tick(completedAt + fastForwardBudget);
    expect(
      controller.reply.startedCount,
      24,
      reason: '受信完了から 400ms 以内に 20 文字すべてが出現を始める '
          '(基準の速さのままなら 24 文字目は 575ms)',
    );
    expect(controller.reply.pendingCount, 0);
  });

  test('AC-6 表示済みの文字がある状態で次の塊が届いても、表示済みの文字は出現し直さない', () {
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk('画面表示'));
    controller.tick(fadeDuration + revealInterval * 3);
    expect(controller.reply.displayedCount, 4, reason: '前提: 4 文字が表示済み');

    controller.addChunk(const Chunk('される'));
    controller.tick(fadeDuration + revealInterval * 4);

    expect(
      controller.reply.displayedCount,
      greaterThanOrEqualTo(4),
      reason: '表示済みの文字数が減らない',
    );
    expect(
      controller.reply.revealing,
      isNotEmpty,
      reason: '前提: 新しく届いた文字が出現している',
    );
    expect(
      revealingIndexes(controller.reply),
      everyElement(greaterThanOrEqualTo(4)),
      reason: '表示済みの文字が出現中へ戻らない',
    );
    for (var index = 0; index < 4; index++) {
      expect(
        opacityOf(controller.reply, index),
        isNull,
        reason: '$index 文字目は表示済みなので不透明度 1 のまま動かない',
      );
    }
  });

  test('AC-12 空の塊が届いても例外にならず、文字数も出現の順番も変わらない', () {
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk(''));
    expect(controller.reply.receivedCount, 0);
    expect(controller.reply.text, isEmpty);

    controller.addChunk(const Chunk('あ'));
    controller.addChunk(const Chunk(''));
    controller.addChunk(const Chunk('い'));
    expect(controller.reply.receivedCount, 2);
    expect(controller.reply.text, 'あい');

    controller.tick(Duration.zero);
    expect(controller.reply.startedCount, 1);
    controller.tick(revealInterval);
    expect(
      controller.reply.startedCount,
      2,
      reason: '空の塊は 1 文字分の順番を消費しない',
    );
    expect(controller.reply.revealedText, 'あい');
  });

  test('AC-12 改行だけの塊は 1 文字として数え、1 文字分の順番を消費する', () {
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk('あ'));
    controller.addChunk(const Chunk('\n'));
    controller.addChunk(const Chunk('い'));
    expect(controller.reply.receivedCount, 3, reason: '改行も 1 文字として数える');
    expect(controller.reply.text, 'あ\nい');

    controller.tick(Duration.zero);
    expect(controller.reply.startedCount, 1);
    controller.tick(revealInterval);
    expect(controller.reply.startedCount, 2);
    expect(
      controller.reply.revealedText,
      'あ\n',
      reason: '2 文字目は改行で、見える文字は進まない',
    );
    controller.tick(revealInterval * 2);
    expect(controller.reply.startedCount, 3);
    expect(controller.reply.revealedText, 'あ\nい');
  });

  test('AC-12 塊の境界で絵文字 (サロゲートペア) が割れると、閉じるまで数えず、閉じたら 1 文字として出現する', () {
    const emoji = '😀';
    final controller = StreamingReplyController();
    controller.addChunk(const Chunk('あ'));
    controller.addChunk(Chunk(emoji.substring(0, 1)));

    expect(
      controller.reply.receivedCount,
      1,
      reason: '閉じていないサロゲートは受信した文字数に入らない',
    );
    expect(controller.reply.text, 'あ', reason: '閉じていないサロゲートは全文に含めない');

    controller.addChunk(Chunk(emoji.substring(1)));
    expect(controller.reply.receivedCount, 2, reason: '絵文字は 1 文字');
    expect(controller.reply.text, 'あ$emoji');

    controller.tick(Duration.zero);
    controller.tick(revealInterval);
    expect(controller.reply.startedCount, 2);
    expect(
      controller.reply.revealing.last.char,
      emoji,
      reason: '絵文字はサロゲートに割れず 1 文字として出現する',
    );
    expect(opacityOf(controller.reply, 1), closeTo(0, opacityTolerance));
    expect(controller.reply.revealedText, 'あ$emoji');
  });

  test('AC-20 思考に未出現の残り 30 文字がある時点で返答の最初の塊が届くと、思考を 400ms 以内に出し切って畳み、その 300ms 後に返答が流れ始める', () {
    /// 思考の文 30 文字。10 文字の並びを 3 回。
    final thinkingText = 'あいうえおかきくけこ' * 3;
    expect(thinkingText.length, 30, reason: '前提: 思考の残りは 30 文字');

    final controller = StreamingReplyController();
    // どちらも最初の tick より前に届くので、返答の到着時点で思考は 1 文字も
    // 出現を始めておらず、未出現の残りがちょうど 30 文字になる。
    controller.addChunk(Chunk(thinkingText, kind: ChunkKind.thinking));
    controller.addChunk(const Chunk('画面表示'));

    // 思考が流れている間の観測。
    const beforeCollapse = Duration(milliseconds: 200);
    final beforeCollapseFrames =
        beforeCollapse.inMilliseconds ~/ frameInterval.inMilliseconds;
    for (var frame = 0; frame <= beforeCollapseFrames; frame++) {
      controller.tick(frameInterval * frame);
    }
    expect(
      controller.thinking.startedCount,
      greaterThan(0),
      reason: '前提: 思考が流れ始めている',
    );
    expect(
      controller.thinkingFrame,
      isNot(ThinkingFrameState.collapsed),
      reason: '思考を出し切る前は畳まれない',
    );
    expect(controller.isThinking, isTrue, reason: '思考の時計が動いている');
    expect(
      controller.reply.receivedCount,
      4,
      reason: '返答の塊は畳む前も受信され、溜められる',
    );
    expect(
      controller.reply.startedCount,
      0,
      reason: '畳む前に返答の文字は出現しない (思考と返答は同時に流れない)',
    );

    // 思考を出し切った時刻・畳みが始まった時刻・返答が流れ始めた時刻を拾う。
    Duration? thinkingAllStartedAt;
    Duration? collapsedAt;
    Duration? replyStartedAt;
    for (var frame = beforeCollapseFrames + 1; frame <= 120; frame++) {
      final now = frameInterval * frame;
      controller.tick(now);
      if (thinkingAllStartedAt == null &&
          controller.thinking.startedCount == thinkingText.length) {
        thinkingAllStartedAt = now;
      }
      if (collapsedAt == null &&
          controller.thinkingFrame == ThinkingFrameState.collapsed) {
        collapsedAt = now;
      }
      if (replyStartedAt == null && controller.reply.startedCount > 0) {
        replyStartedAt = now;
      }
    }

    expect(
      thinkingAllStartedAt,
      isNotNull,
      reason: '早送り: 返答の最初の塊が届いてから 400ms 以内に思考の 30 文字すべてが出現を始める',
    );
    expect(collapsedAt, isNotNull, reason: '思考を出し切ったら本文を畳む');
    expect(replyStartedAt, isNotNull, reason: '畳んだあとに返答が流れ始める');
    final allStartedAt = thinkingAllStartedAt!;
    final collapseStartedAt = collapsedAt!;
    final replyStarted = replyStartedAt!;

    expect(
      allStartedAt,
      lessThanOrEqualTo(fastForwardBudget),
      reason: '早送りの猶予は 400ms (基準の速さのままなら 30 文字目は 725ms)',
    );
    expect(
      collapseStartedAt,
      greaterThanOrEqualTo(allStartedAt),
      reason: '畳むのは思考が出現を始めたあと (残りが読めないまま消えない)',
    );
    expect(
      collapseStartedAt,
      lessThanOrEqualTo(fastForwardBudget + frameInterval),
      reason: '早送りの猶予 400ms + 観測の刻み 1 つ分',
    );
    expect(
      replyStarted - collapseStartedAt,
      greaterThanOrEqualTo(collapseDuration - frameInterval * 2),
      reason: '畳みの 300ms が終わるまで返答の時計は進まない',
    );
    expect(
      replyStarted - collapseStartedAt,
      lessThanOrEqualTo(collapseDuration + frameInterval * 2),
      reason: '畳み終わったらすぐ返答が流れ始める',
    );

    expect(controller.thinkingFrame, ThinkingFrameState.collapsed);
    expect(controller.isThinking, isFalse, reason: '畳みが始まったら思考の時計は止まる');
    expect(controller.thinking.pendingCount, 0);
  });
}
