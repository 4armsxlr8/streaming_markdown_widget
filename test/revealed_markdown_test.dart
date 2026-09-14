import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/markdown_blockquote.dart';
import 'package:streaming_markdown_widget/src/markdown_code_block.dart';
import 'package:streaming_markdown_widget/src/markdown_heading.dart';
import 'package:streaming_markdown_widget/src/markdown_list.dart';
import 'package:streaming_markdown_widget/src/markdown_paragraph.dart';
import 'package:streaming_markdown_widget/src/markdown_table.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

import 'helpers/reveal.dart';

/// AST から Widget への描画と、文字ごとの不透明度のテスト (AC-6, AC-11, AC-22)。
///
/// 時計の進み方 (何ミリ秒後に何文字が出現を始めるか) は
/// `streaming_reply_controller_test.dart` で済んでいる。ここで主張するのは
/// 描画だけ — どの記法がどの Widget になるか、記号が残らないか、表示済みと
/// 出現中がそれぞれどんな span になるか。不透明度の曲線と見た目 (色・余白・
/// 字体) は spec の「テストしないと決めたもの」なので触らない。
///
/// 時間は [RevealTicker] が回す Ticker 越しにしか進まないので、テストから
/// `controller.tick` は呼ばず、[pumpFrames] で 1 フレームずつ進める
/// (非機能要件「widget test では出現の進み方を時間で検証できる」の確認も兼ねる)。
void main() {
  /// 基準の速さ 40 文字/秒 の 1 文字あたりの間隔。
  const revealInterval = Duration(milliseconds: 25);

  /// 1 文字の不透明度が 0 から 1 になるまでの時間。
  const fadeDuration = Duration(milliseconds: 300);

  /// 追いつき・早送りの最速の間隔 (1 フレームに 1 文字)。
  const minRevealInterval = Duration(milliseconds: 16);

  /// 不透明度の比較に許す誤差。
  const opacityTolerance = 1e-6;

  /// 不透明度がこの値以上なら表示済みとみなす。
  const opaqueThreshold = 1 - opacityTolerance;

  /// 表が初めて描かれたフレームで、見出し行の文字がまだ出現中だといえる上限。
  const startingOpacity = 0.2;

  /// AC-6 の最初の塊 (4 文字)。
  const firstChunkText = '画面表示';

  /// AC-6 の次の塊 (3 文字)。
  const secondChunkText = 'される';

  /// [firstChunkText] の 4 文字が出現し終わるまで進める時間。
  ///
  /// 最後の文字は 75ms に出現を始めて 300ms で不透明度 1。Widget が出現開始を
  /// 刻むのは「その文字が初めて描かれたフレーム」なので、フレームの刻み
  /// ([frameInterval]) 3 つ分を余裕として足す。
  final firstChunkRevealDuration =
      fadeDuration + revealInterval * 3 + frameInterval * 3;

  /// AC-22 の表の見出し行 (3 列。行末の改行まで届く)。
  const tableHeaderChunk = '| 方法 | 効果 | 手間 |\n';

  /// 見出し行と同じ 3 列そろった区切り行。
  const tableDelimiterChunk = '|---|---|---|';

  /// [tableHeaderChunk] の文字数 (書記素)。`|` と空白を含む 16 文字 + 改行。
  const tableHeaderCharCount = 17;

  /// 見出し行の 17 文字が出現し終わるまで進める時間。
  final tableHeaderRevealDuration =
      fadeDuration + revealInterval * tableHeaderCharCount + frameInterval * 3;

  /// 区切り行が届いてから表が現れるまでに許すフレーム数の上限。
  ///
  /// 区切り行は 13 文字 = 325ms で出現し終わる。16ms 刻みで 21 フレームなので、
  /// 倍近い余裕を見て 40 フレームで打ち切る。
  const maxFramesToTable = 40;

  /// AC-11 の返答 (全記法を含む。斜体のため 1 箇所 `*滑らかに*` を足した)。
  const fullReplyText = '''
## リストを滑らかにスクロールさせるには

Flutter で長いリストを扱うときは、**画面に見えている行だけを組み立てる** のが基本です。`ListView.builder` を使うと、行は *滑らかに* 必要になった時点で作られます。

- 行の高さをできるだけ揃える
- 画像は `cacheWidth` で縮小して読み込む

1. `ListView` を `ListView.builder` に置き換える
2. `itemExtent` か `prototypeItem` で高さを固定する

| 方法 | 効果 | 手間 |
|---|---|---|
| `itemExtent` | 高さの計算が不要になる | 小 |

```dart
ListView.builder(
  itemExtent: 72,
)
```

> 行の高さが揃っていると、スクロール位置の計算が軽くなります。

詳しくは [公式ドキュメント](https://docs.flutter.dev/perf/best-practices) を参照してください。
''';

  /// [fullReplyText] が受信完了から全部表示済みになるまで進める時間。
  ///
  /// 早送りの割り当て間隔は max(min(400ms ÷ 482 文字, 25ms), 16ms) = 16ms で
  /// 頭打ちになるので (猶予の 400ms では出し切らない)、最後の文字が出現を
  /// 始めるのは 481 × 16ms。そこから 300ms で不透明度 1 になる。Widget が
  /// 出現開始を刻むのは「その文字が初めて描かれたフレーム」なので、フレームの
  /// 刻み 8 つ分を余裕として足す。
  final fullReplyRevealDuration =
      minRevealInterval * (fullReplyText.characters.length - 1) +
      fadeDuration +
      frameInterval * 8;

  /// [fullReplyText] の太字の部分。
  const boldText = '画面に見えている行だけを組み立てる';

  /// [fullReplyText] の斜体の部分。見出しにも「滑らかに」があるので、span の
  /// 文字がちょうどこれと一致することで見分ける。
  const italicText = '滑らかに';

  /// [fullReplyText] のインラインコードのうち、1 か所にしか出ないもの。
  const inlineCodeText = 'cacheWidth';

  /// [fullReplyText] のリンクのラベル。
  const linkLabelText = '公式ドキュメント';

  /// 整形されたら可視文字列に残ってはいけない記号。
  ///
  /// 単独の `*` は斜体 (`*滑らかに*`) の記号で、`**` を兼ねる。
  const rawMarkers = <String>[
    '**',
    '*',
    '`',
    '##',
    '|',
    '---',
    '[',
    '](',
    '> ',
  ];

  /// [spans] のうち表示済み (不透明度 1) のものの文字をつないだもの。
  String opaqueTextOf(List<RevealedSpan> spans) => spans
      .where((span) => span.opacity >= opaqueThreshold)
      .map((span) => span.text)
      .join();

  /// [spans] のうち出現中 (不透明度 1 未満) のもの。
  List<RevealedSpan> revealingOf(List<RevealedSpan> spans) =>
      spans.where((span) => span.opacity < opaqueThreshold).toList();

  testWidgets(
    'AC-6 表示済みの文字がある状態で次の塊が届いても、表示済みの span の不透明度は 1 のままで、新しく届いた文字だけが 1 文字 span で薄く出る',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpRevealedMarkdown(tester, controller);

      controller.addChunk(const Chunk(firstChunkText));
      await tester.pump();
      await pumpFrames(tester, firstChunkRevealDuration);

      expect(
        visibleText(tester),
        firstChunkText,
        reason: '前提: 最初の塊の 4 文字が描かれている',
      );
      expect(
        revealedSpans(tester).map((span) => span.opacity),
        everyElement(closeTo(1, opacityTolerance)),
        reason: '前提: 4 文字とも表示済み (不透明度 1)',
      );

      controller.addChunk(const Chunk(secondChunkText));
      await tester.pump();

      final spans = revealedSpans(tester);
      final revealing = revealingOf(spans);

      expect(
        opaqueTextOf(spans),
        firstChunkText,
        reason: '先に表示済みだった文字は不透明度 1 の span のまま、出現し直さない',
      );
      expect(revealing, isNotEmpty, reason: '前提: 新しく届いた文字が出現を始めている');
      expect(
        revealing.map((span) => span.text.length),
        everyElement(1),
        reason: '出現中の文字は 1 文字 1 span',
      );
      final revealingText = revealing.map((span) => span.text).join();
      expect(
        secondChunkText.startsWith(revealingText),
        isTrue,
        reason: '出現中なのは新しく届いた文字だけ (実際: $revealingText)',
      );
    },
  );

  testWidgets('AC-11 全記法を含む返答が受信完了すると、それぞれ対応する Widget と style で描かれ、記号は残らない', (
    tester,
  ) async {
    final controller = StreamingReplyController();
    await pumpRevealedMarkdown(tester, controller);

    controller.addChunk(const Chunk(fullReplyText));
    await tester.pump();
    controller.complete();
    await pumpFrames(tester, fullReplyRevealDuration);

    // ブロックの記法がそれぞれの Widget になる。
    expect(find.byType(MarkdownHeading), findsOneWidget);
    expect(
      tester.widget<MarkdownHeading>(find.byType(MarkdownHeading)).level,
      2,
      reason: '`##` は 2 段目の見出し',
    );
    expect(find.byType(MarkdownParagraph), findsWidgets);
    final lists = tester
        .widgetList<MarkdownList>(find.byType(MarkdownList))
        .toList();
    expect(
      lists.where((list) => !list.ordered),
      hasLength(1),
      reason: '箇条書き (`- `) が 1 つ',
    );
    expect(
      lists.where((list) => list.ordered),
      hasLength(1),
      reason: '番号リスト (`1. `) が 1 つ',
    );
    expect(find.byType(MarkdownBlockquote), findsOneWidget);
    expect(find.byType(MarkdownCodeBlock), findsOneWidget);
    expect(find.byType(MarkdownTable), findsOneWidget);

    // インラインの記法が契約どおりの style になる。
    final spans = revealedSpans(tester);
    RevealedSpan spanOf(String text) {
      final matched = spans.where((span) => span.text == text).toList();
      expect(matched, hasLength(1), reason: '「$text」は表示済みなので 1 つの span にまとまる');
      return matched.single;
    }

    expect(
      spanOf(boldText).style?.fontWeight?.value,
      greaterThanOrEqualTo(FontWeight.w600.value),
      reason: '太字',
    );
    expect(spanOf(italicText).style?.fontStyle, FontStyle.italic, reason: '斜体');
    final inlineCodeSpan = spanOf(inlineCodeText);
    expect(
      inlineCodeSpan.style?.backgroundColor,
      isNotNull,
      reason: 'インラインコードは地の色を持つ',
    );
    expect(
      inlineCodeSpan.style?.fontFamily,
      isNotNull,
      reason: 'インラインコードは段落と違う字体',
    );
    final linkSpan = spanOf(linkLabelText);
    expect(
      linkSpan.style?.decoration?.contains(TextDecoration.underline),
      isTrue,
      reason: 'リンクは下線',
    );
    expect(linkSpan.recognizer, isNull, reason: 'リンクにタップ処理を付けない');

    // 記号は残らず、コードブロックの中身は素の文字のまま残る。
    final text = visibleText(tester);
    expect(text, contains('リストを滑らかにスクロールさせるには'), reason: '前提: 返答の文字が描かれている');
    for (final marker in rawMarkers) {
      expect(text, isNot(contains(marker)), reason: '生の $marker が残らない');
    }
    final codeBlockText = visibleText(
      tester,
      within: find.byType(MarkdownCodeBlock),
    );
    expect(codeBlockText, contains('ListView.builder('));
    expect(codeBlockText, contains('itemExtent: 72,'));
  });

  testWidgets(
    'AC-22 区切り行が届いて表が初めて描かれたフレームで、見出し行の文字が一斉に不透明度 0 付近から出現を始め、300ms 後に 1 になる',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpRevealedMarkdown(tester, controller);

      controller.addChunk(const Chunk(tableHeaderChunk));
      await tester.pump();
      await pumpFrames(tester, tableHeaderRevealDuration);

      expect(
        controller.reply.pendingCount,
        0,
        reason: '前提: 見出し行の $tableHeaderCharCount 文字がすべて出現を始めている',
      );
      expect(
        find.byType(MarkdownTable),
        findsNothing,
        reason: '区切り行が届くまで表は描かれない',
      );
      final beforeText = visibleText(tester);
      expect(beforeText, isNot(contains('方法')), reason: '描かれていない見出し行の文字は見えない');
      expect(beforeText, isNot(contains('|')), reason: '生の | は見えない');

      controller.addChunk(const Chunk(tableDelimiterChunk));
      await tester.pump();

      var frames = 0;
      while (find.byType(MarkdownTable).evaluate().isEmpty) {
        frames++;
        expect(
          frames,
          lessThanOrEqualTo(maxFramesToTable),
          reason: '区切り行が出現し終わっても表が現れない',
        );
        await tester.pump(frameInterval);
      }

      final startingSpans = revealedSpans(
        tester,
        within: find.byType(MarkdownTable),
      );
      final startingText = startingSpans.map((span) => span.text).join();
      expect(startingText, contains('方法'));
      expect(startingText, contains('効果'));
      expect(startingText, contains('手間'));
      expect(
        startingSpans.map((span) => span.opacity),
        everyElement(lessThan(startingOpacity)),
        reason: '表が初めて描かれたフレームでは、見出し行の文字はまだ不透明度 0 付近',
      );
      expect(
        startingSpans.map((span) => span.opacity),
        everyElement(closeTo(startingSpans.first.opacity, opacityTolerance)),
        reason: '見出し行の文字は一斉に出現を始める (不透明度がそろっている)',
      );

      await pumpFrames(tester, fadeDuration + frameInterval * 2);

      final finishedSpans = revealedSpans(
        tester,
        within: find.byType(MarkdownTable),
      );
      final finishedText = finishedSpans.map((span) => span.text).join();
      expect(finishedText, contains('方法'));
      expect(finishedText, contains('効果'));
      expect(finishedText, contains('手間'));
      expect(
        finishedSpans.map((span) => span.opacity),
        everyElement(closeTo(1, opacityTolerance)),
        reason: '出現開始から 300ms で不透明度 1',
      );
    },
  );
}
