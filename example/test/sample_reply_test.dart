import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/sample_reply.dart';

import 'helpers/app.dart';
import 'helpers/reveal.dart';

/// サンプル (作り物の供給が流す質問・思考・返答) のテスト (AC-27)。
///
/// seam はサンプルの文字列。主張するのは 3 つ — 返答がブロックの 8 種
/// (見出し・段落・箇条書き・番号リスト・表・コードブロック・引用・リンク) を
/// 1 つ以上含み表は 2 列であること、思考と返答を合わせて 500 文字以下
/// (供給 32 文字/秒で 16 秒以内) で思考は 1 行であること、質問・思考・返答に
/// 日本語の文字が無いこと (spec: サンプルは英語)。
///
/// ブロックの種類は文字列の正規表現ではなく、返答を [StreamingReply] に流して
/// 描かれたブロックの Widget で見る — 画面で実際に描かれる経路をそのまま通る
/// ので、記法の書き間違い (コードブロックの中の `-` を箇条書きと数えるなど) に
/// 引っかからない。リンクは下線の span で見る (パッケージの既定のリンクの
/// style)。
///
/// ブロックは出現が届いた位置までの Markdown から作られるので、8 種を数えるには
/// 返答の全文が出切るまで時間を進める必要がある。出現の速さそのものは主張では
/// ないので、[StreamingReplyStyle] で出現の間隔を 1ms に詰めて 1 フレームに
/// 16 文字ほど出現させ、30 フレームほどで出切らせる ([revealBudget])。
///
/// 出現の見た目・供給のむらは spec の「テストしないと決めたもの」なので触らない
/// (ここでは Controller に返答をまとめて届け、供給は通さない)。
void main() {
  /// 供給の速さ (spec: 32 文字/秒)。
  const supplyCharsPerSecond = 32;

  /// 思考と返答を合わせた文字数の上限 (AC-27: 500 文字 = 16 秒以内)。
  const maxSampleChars = 500;

  /// 返答の全文が出切るまで進める時間の上限。
  ///
  /// [pumpSampleReply] が出現の間隔を 1ms に詰めるので 1 フレーム (16ms) で
  /// 16 文字ほど出現が始まるが、見積もりは半分の 8 文字/フレームで置いて倍の
  /// 余裕を取る (実際は残りが 0 になったフレームで止まる)。
  final revealBudget = frameInterval * (sampleReply.characters.length ~/ 8);

  /// 返答を [StreamingReply] にまとめて届け、全文が出切るまで描く。
  ///
  /// 出現の間隔は既定 (25ms、早送りでも 1 フレームに 1 文字) だと全文が出切る
  /// まで文字数ぶんのフレームがかかるので、1ms に詰める — 主張はブロックの
  /// 種類だけなので、出現の速さは見ない。
  Future<void> pumpSampleReply(WidgetTester tester) async {
    final controller = StreamingReplyController(
      style: StreamingReplyStyle(
        revealInterval: const Duration(milliseconds: 1),
        minRevealInterval: const Duration(milliseconds: 1),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreamingReply(controller: controller),
          ),
        ),
      ),
    );
    controller.addChunk(const Chunk(sampleReply, kind: ChunkKind.reply));
    controller.complete();

    // 残り (まだ出現が始まっていない文字) が 0 になったフレームでは、全文が
    // Markdown として整形されている = 8 種のブロックが揃って描かれている。
    await pumpUntil(
      tester,
      () => controller.reply.pendingCount == 0,
      budget: revealBudget,
      reason: '返答が出切らない',
    );
  }

  testWidgets('AC-27 サンプルの返答はブロックの 8 種をそれぞれ 1 つ以上含み、表は 2 列', (tester) async {
    await pumpSampleReply(tester);

    expect(
      find.byType(MarkdownHeading),
      findsAtLeastNWidgets(1),
      reason: '見出しが 1 つ以上ある',
    );
    expect(
      find.byType(MarkdownParagraph),
      findsAtLeastNWidgets(1),
      reason: '段落が 1 つ以上ある',
    );
    expect(
      find.byType(MarkdownCodeBlock),
      findsAtLeastNWidgets(1),
      reason: 'コードブロックが 1 つ以上ある',
    );
    expect(
      find.byType(MarkdownBlockquote),
      findsAtLeastNWidgets(1),
      reason: '引用が 1 つ以上ある',
    );

    final lists = tester.widgetList<MarkdownList>(find.byType(MarkdownList));
    expect(
      lists.where((list) => list.block.ordered == false),
      isNotEmpty,
      reason: '箇条書きが 1 つ以上ある',
    );
    expect(
      lists.where((list) => list.block.ordered == true),
      isNotEmpty,
      reason: '番号リストが 1 つ以上ある',
    );

    final tables = tester.widgetList<MarkdownTable>(find.byType(MarkdownTable));
    expect(tables, isNotEmpty, reason: '表が 1 つ以上ある');
    for (final table in tables) {
      expect(
        table.block.headerCells!.length,
        2,
        reason: '表の見出しの行は 2 列 (3 列は画面幅からはみ出す)',
      );
      expect(
        table.block.bodyRows!.map((row) => row.length),
        everyElement(2),
        reason: '表の本文の行も 2 列',
      );
    }

    expect(
      revealedSpans(
        tester,
      ).where((span) => span.style?.decoration == TextDecoration.underline),
      isNotEmpty,
      reason: 'リンクが 1 つ以上ある (リンクは下線の span で描かれる)',
    );
  });

  test('AC-27 サンプルの思考と返答を合わせて 500 文字以下 (32 文字/秒で 16 秒以内) で、思考は 1 行', () {
    // 供給は記法の文字もそのまま流すので、数えるのも記法を含む生の文字数
    // (書記素) — 供給が 1 塊に切るときと同じ数え方にする。
    final thinkingChars = sampleThinking.characters.length;
    final replyChars = sampleReply.characters.length;

    expect(
      thinkingChars + replyChars,
      lessThanOrEqualTo(maxSampleChars),
      reason:
          '思考 ($thinkingChars 文字) と返答 ($replyChars 文字) を合わせて '
          '$maxSampleChars 文字以下 = 供給 $supplyCharsPerSecond 文字/秒で 16 秒以内',
    );
    expect(sampleThinking, isNot(contains('\n')), reason: '思考は 1 行 (2 秒程度)');
  });

  test('AC-27 サンプルの質問・思考・返答に日本語の文字が無い', () {
    expect(sampleQuestion, isNotEmpty, reason: 'サンプルの質問がある');
    expect(sampleQuestion, isNot(matches(japanese)), reason: 'サンプルの質問は英語');
    expect(sampleThinking, isNot(matches(japanese)), reason: 'サンプルの思考は英語');
    expect(sampleReply, isNot(matches(japanese)), reason: 'サンプルの返答は英語');
  });
}
