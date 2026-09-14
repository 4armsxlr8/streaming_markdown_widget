import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

/// 追いつきが 2 度目以降も働くことのテスト (AC-28, AC-29)。
///
/// `streaming_reply_controller_test.dart` の AC-4 は「遅れの上限を初めて
/// 超えたときに追いつく」ことだけを見ている。ここで主張するのは、追いつきの
/// 速さが 1 度決めたきりにならないこと — 追いつきの途中でさらに塊が届いて
/// 残りが増えたとき (AC-28) と、いったん基準へ戻った後にまた上限を超えたとき
/// (AC-29) に、その時点の残りから割り当てを決め直す。
///
/// 速さの上限 (最速の間隔 16ms) が入ったので、100 文字級の残りでは割り当て
/// 間隔はどちらの回も 16ms で頭打ちになり、遅れが 600ms 以内に上限以下へ戻る
/// 保証は無くなった (spec: 「受信に必ず追いつく保証は捨てる」)。決め直して
/// いることは間隔ではなく「割り当て済みだった 25ms 間隔の尾まで 16ms へ
/// 引き戻す」ことと「基準へ戻った後にまた 16ms 間隔へ切り替わる」ことで見る。
///
/// 時間は [StreamingReplyController.tick] に [Duration] を直接渡して進めるので、
/// Widget も Ticker も要らない純 Dart のテストとして書く。
void main() {
  /// 遅れの上限。未出現の残りがこの文字数を超えた瞬間に追いつきへ切り替わる。
  const catchUpThreshold = 24;

  /// 追いつきが遅れを上限以下へ戻そうとする猶予。
  const catchUpBudget = Duration(milliseconds: 600);

  /// 追いつき・早送りの最速の間隔 (1 フレームに 1 文字)。
  const minRevealInterval = Duration(milliseconds: 16);

  /// 時刻を細かく追うときの刻み (`streaming_reply_controller_test.dart` と同じ)。
  const frameInterval = Duration(milliseconds: 10);

  /// 100 文字の塊。10 文字の並びを 10 回。
  final longChunkText = 'あいうえおかきくけこ' * 10;

  /// [controller] を [from] から [to] まで [frameInterval] 刻みで進める。
  void tickTo(
    StreamingReplyController controller, {
    required Duration from,
    required Duration to,
  }) {
    for (var now = from; now <= to; now += frameInterval) {
      controller.tick(now);
    }
  }

  test(
    'AC-28 追いつきの途中でさらに塊が届いて残りが増えると、その時点の未出現すべてを最速の 16ms 間隔へ組み直す (割り当て済みだった 25ms 間隔の尾も 16ms へ引き戻す)',
    () {
      /// 2 つ目の塊が届く時刻 (1 つ目の追いつきの途中)。
      const secondArrival = Duration(milliseconds: 200);

      /// 組み直しの結果を見る時刻。
      ///
      /// 1 つ目の塊だけなら、先頭 76 文字が 16ms 間隔 (0ms〜1200ms)、残り 24
      /// 文字が基準の 25ms 間隔 (1225ms〜1800ms) なので、1800ms 時点で出現を
      /// 始めているのはちょうど 100 文字。組み直すと 200ms の時点で未出現
      /// だった 187 文字 (通し番号 13〜199) が 200ms から 16ms 間隔に並ぶので、
      /// 1800ms = 200ms + 100 × 16ms 時点では通し番号 113 まで = 114 文字。
      const observeAt = Duration(milliseconds: 1800);

      final controller = StreamingReplyController();
      controller.addChunk(Chunk(longChunkText));

      tickTo(controller, from: Duration.zero, to: secondArrival);
      expect(
        controller.reply.pendingCount,
        greaterThan(catchUpThreshold),
        reason: '前提: まだ追いつきの途中 (未出現の残りが上限を超えたまま)',
      );

      controller.addChunk(Chunk(longChunkText));
      expect(controller.reply.receivedCount, 200, reason: '前提: 受信は 200 文字');

      controller.tick(secondArrival + frameInterval);
      expect(
        controller.reply.startedCount,
        lessThan(controller.reply.receivedCount),
        reason: '決め直した割り当てでも残りを一度に出すのではなく 1 文字ずつ出す',
      );

      tickTo(
        controller,
        from: secondArrival + frameInterval * 2,
        to: observeAt,
      );
      expect(
        controller.reply.startedCount,
        114,
        reason:
            '2 つ目の塊が届いた時点の未出現すべてを 200ms から 16ms 間隔へ組み直すので、'
            '1800ms までに 114 文字が出現を始める '
            '(組み直さず 1 つ目の割り当てを残して後ろに継ぎ足すだけなら、'
            '1225ms〜1800ms は基準の 25ms 間隔のままで 100 文字)',
      );
      expect(
        controller.reply.pendingCount,
        greaterThan(catchUpThreshold),
        reason:
            '最速の間隔で頭打ちになるので、遅れは追いつきの上限を超えて残ってよい '
            '(1800ms 時点の残りは 86 文字)',
      );
    },
  );

  test('AC-29 追いつきが基準に戻った後に再び残りが 24 文字を超えると、その時点の残りから決め直して最速の 16ms 間隔へ戻る', () {
    /// 2 つ目の塊が届く時刻。
    ///
    /// 1 つ目の 100 文字は 1200ms で追いつきの 76 文字を出し切り、そこから
    /// 残り 24 文字を基準の 25ms 間隔で流すので、1300ms は「基準の速さで
    /// 流れている」時刻 (未出現の残りは 20 文字)。
    const secondArrival = Duration(milliseconds: 1300);

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(longChunkText));

    tickTo(controller, from: Duration.zero, to: secondArrival);
    expect(
      controller.reply.pendingCount,
      lessThanOrEqualTo(catchUpThreshold),
      reason: '前提: 2 つ目の塊が届く時点では基準の速さで流れている (残り 20 文字)',
    );

    final startedAtArrival = controller.reply.startedCount;
    controller.addChunk(Chunk(longChunkText));
    expect(
      controller.reply.pendingCount,
      greaterThan(catchUpThreshold),
      reason: '前提: 2 つ目の塊で未出現の残りが再び上限を超えた',
    );

    tickTo(
      controller,
      from: secondArrival + frameInterval,
      to: secondArrival + catchUpBudget,
    );
    expect(
      controller.reply.startedCount - startedAtArrival,
      37,
      reason:
          '2 度目も同じ手順で決め直すので、届いてから 600ms の間に出現を始めるのは '
          '最速の ${minRevealInterval.inMilliseconds}ms 間隔の 37 文字 '
          '(基準の 25ms 間隔のままなら 24 文字)',
    );
  });
}
