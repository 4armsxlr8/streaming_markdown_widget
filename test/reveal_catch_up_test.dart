import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

/// 追いつきが 2 度目以降も働くことのテスト (AC-28, AC-29)。
///
/// `streaming_reply_controller_test.dart` の AC-4 は「遅れの上限を初めて
/// 超えたときに追いつく」ことだけを見ている。ここで主張するのは、追いつきの
/// 速さが 1 度決めたきりにならないこと — 追いつきの途中でさらに塊が届いて
/// 残りが増えたとき (AC-28) と、いったん基準へ戻った後にまた上限を超えたとき
/// (AC-29) に、その時点の残りから速さを決め直して 600ms 以内に上限以下へ戻る。
///
/// 時間は [StreamingReplyController.tick] に [Duration] を直接渡して進めるので、
/// Widget も Ticker も要らない純 Dart のテストとして書く。
void main() {
  /// 遅れの上限。未出現の残りがこの文字数を超えた瞬間に追いつきへ切り替わる。
  const catchUpThreshold = 24;

  /// 追いつきが遅れを上限以下へ戻すまでの猶予。
  const catchUpBudget = Duration(milliseconds: 600);

  /// 時刻を細かく追うときの刻み (`streaming_reply_controller_test.dart` と同じ)。
  const frameInterval = Duration(milliseconds: 10);

  /// 100 文字の塊。10 文字の並びを 10 回。
  final longChunkText = 'あいうえおかきくけこ' * 10;

  /// [controller] を [from] から [to] まで [frameInterval] 刻みで進め、
  /// 未出現の残りが初めて [catchUpThreshold] 以下になった時刻を返す
  /// (最後まで戻らなければ null)。
  Duration? tickUntilCaughtUp(
    StreamingReplyController controller, {
    required Duration from,
    required Duration to,
  }) {
    Duration? caughtUpAt;
    for (var now = from; now <= to; now += frameInterval) {
      controller.tick(now);
      if (caughtUpAt == null &&
          controller.reply.pendingCount <= catchUpThreshold) {
        caughtUpAt = now;
      }
    }
    return caughtUpAt;
  }

  test('AC-28 追いつきの途中でさらに塊が届いて残りが増えると、その時点の残りから速さを決め直し、届いてから 600ms 以内に残りが 24 文字以下になる', () {
    /// 2 つ目の塊が届く時刻 (1 つ目の追いつきの途中)。
    const secondArrival = Duration(milliseconds: 200);

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(longChunkText));

    tickUntilCaughtUp(controller, from: Duration.zero, to: secondArrival);
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
      reason: '決め直した速さでも残りを一度に出すのではなく 1 文字ずつ出す',
    );

    final caughtUpAt = tickUntilCaughtUp(
      controller,
      from: secondArrival + frameInterval * 2,
      to: secondArrival + catchUpBudget,
    );
    expect(
      caughtUpAt,
      isNotNull,
      reason: '2 つ目の塊が届いてから 600ms 以内に未出現の残りが $catchUpThreshold 文字以下へ戻る '
          '(1 つ目の追いつきの速さのまま後ろに継ぎ足すだけなら、'
          '800ms 時点の残りは 100 文字を超える)',
    );
  });

  test('AC-29 追いつきが基準に戻った後に再び残りが 24 文字を超えると、超えてから 600ms 以内に 24 文字以下へ戻る', () {
    /// 2 つ目の塊が届く時刻 (1 つ目の追いつきが基準へ戻った後)。
    const secondArrival = Duration(milliseconds: 700);

    final controller = StreamingReplyController();
    controller.addChunk(Chunk(longChunkText));

    final firstCaughtUpAt = tickUntilCaughtUp(
      controller,
      from: Duration.zero,
      to: catchUpBudget,
    );
    expect(
      firstCaughtUpAt,
      isNotNull,
      reason: '前提: 1 度目の追いつきが 600ms 以内に上限以下へ戻った',
    );

    tickUntilCaughtUp(
      controller,
      from: catchUpBudget + frameInterval,
      to: secondArrival,
    );
    expect(
      controller.reply.pendingCount,
      lessThanOrEqualTo(catchUpThreshold),
      reason: '前提: 2 つ目の塊が届く時点では基準の速さで流れている',
    );

    controller.addChunk(Chunk(longChunkText));
    expect(
      controller.reply.pendingCount,
      greaterThan(catchUpThreshold),
      reason: '前提: 2 つ目の塊で未出現の残りが再び上限を超えた',
    );

    final secondCaughtUpAt = tickUntilCaughtUp(
      controller,
      from: secondArrival + frameInterval,
      to: secondArrival + catchUpBudget,
    );
    expect(
      secondCaughtUpAt,
      isNotNull,
      reason: '2 度目も同じ手順で追いつき、超えてから 600ms 以内に '
          '$catchUpThreshold 文字以下へ戻る '
          '(基準の速さのままなら 600ms で出せるのは 24 文字だけで、残りは 90 文字)',
    );
  });
}
