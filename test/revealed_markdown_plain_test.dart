import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

import 'helpers/reveal.dart';

/// 整形しない描画と、出現が終わったあとのフレーム要求のテスト (AC-30, AC-31)。
///
/// `revealed_markdown_test.dart` が整形あり (`formatted: true`) の描画を見るのに
/// 対し、ここは思考の文の整形なし (`formatted: false`) の描画 (AC-30) と、
/// 出現中の文字が無くなった後にフレームを要求しないこと (AC-31) を見る。
///
/// 時間は [RevealTicker] が回す Ticker 越しにしか進まないので、テストから
/// `controller.tick` は呼ばず、[pumpFrames] で 1 フレームずつ進める。
void main() {
  /// 1 文字の不透明度が 0 から 1 になるまでの時間。
  const fadeDuration = Duration(milliseconds: 300);

  /// 受信完了の時点の残りを出し切るまでの猶予 (早送り)。
  const fastForwardBudget = Duration(milliseconds: 400);

  /// 不透明度の比較に許す誤差。
  const opacityTolerance = 1e-6;

  /// 整形しない思考の文 (記法の記号と改行を含む 2 行)。
  const plainThinkingText = '**強調** の記号\n2 行目';

  /// AC-31 の返答 (記法を含まない短い文)。
  const shortReplyText = '返答の文字';

  /// 受信完了から、出現中の文字が 1 つも残らなくなるまで進める時間。
  ///
  /// 早送りは 400ms 以内に全部の文字の出現を始めさせ、最後の文字はそこから
  /// 300ms で不透明度 1 になる。Widget が出現開始を刻むのは「その文字が初めて
  /// 描かれたフレーム」なので、フレームの刻み 4 つ分を余裕として足す。
  final revealAllDuration =
      fastForwardBudget + fadeDuration + frameInterval * 4;

  testWidgets(
    'AC-30 整形なしの思考の文に改行を含む 2 行が届くと、記法は整形されず素の文字で描かれ、改行はそのまま行の区切りになる',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpRevealedMarkdown(
        tester,
        controller,
        kind: ChunkKind.thinking,
        formatted: false,
      );

      controller.addChunk(
        const Chunk(plainThinkingText, kind: ChunkKind.thinking),
      );
      await tester.pump();
      controller.complete();
      await pumpFrames(tester, revealAllDuration);

      expect(
        visibleText(tester),
        plainThinkingText,
        reason:
            '整形しないので ** は太字にならず素の文字のまま残り、'
            '改行も文字として残る (届いた文字列がそのまま可視文字列になる)',
      );
      expect(
        visibleText(tester).split('\n'),
        hasLength(2),
        reason: '改行がそのまま行の区切りになり、TextSpan の平文が 2 行になる',
      );
    },
  );

  testWidgets('AC-31 出現中の文字が無くなる (全部が不透明度 1) と、以後フレームを要求しない', (tester) async {
    final controller = StreamingReplyController();
    await pumpRevealedMarkdown(tester, controller);

    controller.addChunk(const Chunk(shortReplyText));
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason:
          '前提: 出現中の文字がある間はフレームを要求している '
          '(この主張が常に false なら、後の isFalse は何も確かめていない)',
    );

    controller.complete();
    await pumpFrames(tester, revealAllDuration);

    expect(
      revealedSpans(tester).map((span) => span.opacity),
      everyElement(closeTo(1, opacityTolerance)),
      reason: '前提: 出現中の文字が 1 つも残っていない',
    );

    await tester.pump(frameInterval);
    await tester.pump(frameInterval);

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason:
          '出現中の文字が無くなったら Ticker を止め、次のフレームを予約しない '
          '(予約し続けると、何も動いていないのに毎フレーム描き直すことになる)',
    );
  });
}
