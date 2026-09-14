import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/reveal_ticker.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'helpers/reveal.dart';

/// 公開入口から使うブロックの差し替えのテスト (AC-5)。
///
/// 主張するのは (a) 渡した種類のブロックだけが builder の結果で描かれ、渡さな
/// かった種類は既定のブロック Widget で描かれること、(b) builder が受け取る
/// [MarkdownBlock] からその中身と出現の状態 (出現中の文字の位置と不透明度) が
/// 取れること、(c) 補助関数 [applyReveal] を通した span の文字ごとの不透明度が
/// 既定の描き方と同じになること。出現の見た目そのもの (不透明度の曲線・色・
/// 余白) は spec の「テストしないと決めたもの」なので触らない。
///
/// [helpers/reveal.dart] の `pumpRevealedMarkdown` は `blockBuilders` を渡せ
/// ないので、このファイルは [RevealTicker] と [RevealedMarkdown] を自前で組んで
/// pump する (helpers は他のスライスと共有しているので書き換えない)。時間は
/// [RevealTicker] が回す Ticker 越しにしか進まないので `controller.tick` は
/// 呼ばず、[pumpFrames] と `pump(frameInterval)` で 1 フレームずつ進める。
/// `pumpAndSettle` は使わない。
///
/// [RevealTicker] だけは公開しない部品なので `src/reveal_ticker.dart` を直接
/// import し、それ以外は公開入口から取る — 利用側が書けるコードと同じもので
/// テストを組む。
void main() {
  /// 1 文字の不透明度が 0 から 1 になるまでの時間。
  const fadeDuration = Duration(milliseconds: 300);

  /// 追いつき・早送りの最速の間隔 (1 フレームに 1 文字)。
  const minRevealInterval = Duration(milliseconds: 16);

  /// 不透明度の比較に許す誤差。
  const opacityTolerance = 1e-6;

  /// 不透明度がこの値以上なら表示済みとみなす。
  const opaqueThreshold = 1 - opacityTolerance;

  /// 追いつきに入らせないための、十分に大きい遅れの上限。
  ///
  /// 遅れの上限の文字数は `catchUpBudget ÷ revealInterval` なので 10 秒なら
  /// 400 文字。[reply] は 120 文字ほどで、最後まで基準の 25ms 間隔 (40 文字/秒)
  /// で出現する — 追いつきに入ると 1 フレームに何文字も出現を始めてしまい、
  /// 「表示済みの文字と出現中の文字が両方あるフレーム」が取れなくなる。
  const noCatchUpBudget = Duration(seconds: 10);

  /// コードブロックの本文 (27 文字)。
  ///
  /// 出現中の文字は 1 度に 12 文字 (300ms ÷ 25ms) までなので、これだけ長ければ
  /// 本文の中に表示済みの文字と出現中の文字が同時にある瞬間ができる。
  const codeBody = 'final total = items.length;';

  /// 7 種のブロックを 1 つずつ含む返答 (`test/fixtures` は無いのでここに書く)。
  ///
  /// コードブロックは表より前に置く — 本文が出現の途中になる瞬間を、後ろの
  /// ブロックが届く前に取れるようにするため。
  const reply = '''
## 見出し

段落の文。

- 箇条書きの項目

1. 番号の項目

> 引用の文。

```dart
final total = items.length;
```

| 列 | 値 |
|---|---|
| 行 | 2 |''';

  /// [reply] が受信完了から全部表示済みになるまで進める時間。
  ///
  /// 早送りの割り当て間隔は max(min(400ms ÷ 116 文字, 25ms), 16ms) = 16ms で
  /// 頭打ちになるので (猶予の 400ms では出し切らない)、最後の文字が出現を
  /// 始めるのは 115 × 16ms。そこから 300ms で不透明度 1 になる。Widget が
  /// 出現開始を刻むのは「その文字が初めて描かれたフレーム」なので、フレームの
  /// 刻み 8 つ分を余裕として足す。
  final replyRevealDuration =
      minRevealInterval * (reply.characters.length - 1) +
      fadeDuration +
      frameInterval * 8;

  /// [codeBody] の 1 文字目の、受信した文字列の中での通し番号 (書記素)。
  /// Controller の `reply.revealing` の位置と、ブロックの中の位置を突き合わせる
  /// ための原点。
  final bodyStart = reply
      .substring(0, reply.indexOf(codeBody))
      .characters
      .length;

  /// 出現の途中のフレームを探すのに許すフレーム数の上限。
  ///
  /// 本文の末尾まで出現を始めるのに (bodyStart + 27) 文字 × 25ms ≒ 2 秒 =
  /// 125 フレーム。倍以上の余裕を見て打ち切る。
  const maxSampleFrames = 400;

  /// builder が返す Widget の目印。
  const builtCodeBlock = ValueKey<String>('built-code-block');

  /// 既定の描き方をする [RevealedMarkdown] の目印 (テスト (c) で 2 つ並べる)。
  const defaultMarkdown = ValueKey<String>('default-markdown');

  /// [within] に描かれた span を 1 文字ずつにほどき、文字と不透明度の列にする。
  ///
  /// 表示済みの文字は 1 span にまとまり出現中の文字は 1 文字 1 span になるので、
  /// span のまとまり方ではなく文字ごとに突き合わせる。
  List<({String char, double opacity})> revealedCharOpacities(
    WidgetTester tester, {
    required Finder within,
  }) => [
    for (final span in revealedSpans(tester, within: within))
      for (final char in span.text.characters)
        (char: char, opacity: span.opacity),
  ];

  /// 追いつきに入らない Controller。
  StreamingReplyController newController() => StreamingReplyController(
    style: StreamingReplyStyle(catchUpBudget: noCatchUpBudget),
  );

  /// [children] を [RevealTicker] で包んで画面に置く。
  Future<void> pumpBlocks(
    WidgetTester tester,
    StreamingReplyController controller,
    List<Widget> children,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RevealTicker(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'AC-5 コードブロックだけ builder を渡すと、コードブロックは builder の結果で描かれ、渡さなかった種類は既定のブロック Widget で描かれる',
    (tester) async {
      final controller = newController();
      await pumpBlocks(tester, controller, [
        RevealedMarkdown(
          controller: controller,
          kind: ChunkKind.reply,
          blockBuilders: {
            MarkdownBlockKind.codeBlock: (context, block) =>
                Text(block.text, key: builtCodeBlock),
          },
        ),
      ]);

      controller.addChunk(const Chunk(reply));
      controller.complete();
      await pumpFrames(tester, replyRevealDuration);

      expect(
        find.byKey(builtCodeBlock),
        findsOneWidget,
        reason: 'コードブロックは渡した builder の結果で描かれる',
      );
      expect(
        tester.widget<Text>(find.byKey(builtCodeBlock)).data,
        codeBody,
        reason:
            '出現し終わると builder は本文をそのまま受け取る '
            '(フェンスの記号も言語名も、末尾の改行も含まない)',
      );
      expect(
        find.byType(MarkdownCodeBlock),
        findsNothing,
        reason: 'builder を渡した種類は既定のコードブロックの Widget では描かれない',
      );
      expect(
        find.byType(MarkdownHeading),
        findsOneWidget,
        reason: '渡さなかった見出しは既定のまま',
      );
      expect(
        find.byType(MarkdownList),
        findsNWidgets(2),
        reason: '渡さなかった箇条書きと番号リストは既定のまま',
      );
      expect(
        find.byType(MarkdownBlockquote),
        findsOneWidget,
        reason: '渡さなかった引用は既定のまま',
      );
      expect(
        find.byType(MarkdownTable),
        findsOneWidget,
        reason: '渡さなかった表は既定のまま',
      );
      expect(
        find.byType(MarkdownParagraph),
        findsWidgets,
        reason: '渡さなかった段落は既定のまま (引用の中の段落もあるので数は問わない)',
      );
    },
  );

  testWidgets('AC-5 builder は受信の途中でコードブロックの中身と、出現中の文字の位置と不透明度を受け取る', (
    tester,
  ) async {
    final controller = newController();
    MarkdownBlock? captured;
    await pumpBlocks(tester, controller, [
      RevealedMarkdown(
        controller: controller,
        kind: ChunkKind.reply,
        blockBuilders: {
          MarkdownBlockKind.codeBlock: (context, block) {
            captured = block;
            return Text(block.text, key: builtCodeBlock);
          },
        },
      ),
    ]);

    controller.addChunk(const Chunk(reply));

    /// コードブロックの本文が出現の途中 (出現中の文字が 3 つ以上あり、
    /// Controller 側も本文の中の文字を出現中と見ている) になったか。
    bool sampleReady() {
      final block = captured;
      return block != null &&
          block.revealing.length >= 3 &&
          controller.reply.revealing.any((c) => c.index >= bodyStart);
    }

    var frames = 0;
    while (!sampleReady()) {
      await tester.pump(frameInterval);
      frames++;
      expect(
        frames,
        lessThanOrEqualTo(maxSampleFrames),
        reason: '$maxSampleFrames フレーム以内にコードブロックの本文が出現の途中になる',
      );
    }

    final block = captured!;
    expect(
      block.kind,
      MarkdownBlockKind.codeBlock,
      reason: 'builder が受け取るブロックの種類はコードブロック',
    );
    expect(
      codeBody.startsWith(block.text),
      isTrue,
      reason:
          '中身は本文の先頭からの出現した分だけ '
          '(フェンスの記号も言語名も含まない): "${block.text}"',
    );
    expect(block.text, isNotEmpty, reason: '前提: 本文が出現を始めている');

    final bodyChars = block.text.characters.toList();
    for (final revealing in block.revealing) {
      expect(
        revealing.index,
        inInclusiveRange(0, bodyChars.length - 1),
        reason: '出現中の文字の位置は、この中身の中の通し番号 (0 始まり)',
      );
      expect(
        revealing.char,
        bodyChars[revealing.index],
        reason: '位置 ${revealing.index} は中身の同じ位置の文字を指す',
      );
      expect(revealing.opacity, inInclusiveRange(0, 1), reason: '不透明度は 0〜1');
      expect(
        revealing.opacity,
        lessThan(1),
        reason: '出現中の文字だけが並ぶ (表示済みの文字は含まない)',
      );
    }

    /// 1 フレーム分のずれの上限。
    ///
    /// Widget は「その文字が初めて描かれたフレーム」を出現の開始にするので、
    /// Controller が予定した開始時刻より最大 1 フレーム (16ms) 遅れる。
    /// 不透明度に直すと 16ms ÷ 300ms。
    final frameSlack =
        frameInterval.inMicroseconds / fadeDuration.inMicroseconds;

    var matched = 0;
    for (final expected in controller.reply.revealing) {
      final index = expected.index - bodyStart;
      if (index < 0 || index >= bodyChars.length) continue;
      final inBlock = block.revealing.where((r) => r.index == index).toList();
      expect(
        inBlock,
        hasLength(1),
        reason:
            'Controller が出現中と見ている本文の $index 文字目は、'
            'builder が受け取る出現の状態にも 1 つだけ並ぶ',
      );
      expect(
        inBlock.single.char,
        expected.char,
        reason: '$index 文字目の文字が Controller の見ているものと同じ',
      );
      expect(
        inBlock.single.opacity,
        lessThanOrEqualTo(expected.opacity + opacityTolerance),
        reason: '$index 文字目の不透明度は Controller の予定を追い越さない',
      );
      expect(
        inBlock.single.opacity,
        greaterThan(expected.opacity - frameSlack - opacityTolerance),
        reason: '$index 文字目の不透明度の遅れは 1 フレーム分まで',
      );
      matched++;
    }
    expect(
      matched,
      greaterThan(0),
      reason: '前提: Controller が出現中と見ている文字が本文の中にある',
    );
  });

  testWidgets('AC-5 補助関数を通した span の文字ごとの不透明度は、既定の描き方と同じになる', (tester) async {
    final style = StreamingReplyStyle();
    final controller = newController();
    await pumpBlocks(tester, controller, [
      RevealedMarkdown(
        key: defaultMarkdown,
        controller: controller,
        kind: ChunkKind.reply,
        style: style,
      ),
      RevealedMarkdown(
        controller: controller,
        kind: ChunkKind.reply,
        style: style,
        blockBuilders: {
          MarkdownBlockKind.codeBlock: (context, block) => Text.rich(
            applyReveal(
              TextSpan(text: block.text, style: style.codeBlockTextStyle),
              block.revealing,
            ),
            key: builtCodeBlock,
          ),
        },
      ),
    ]);

    controller.addChunk(const Chunk(reply));

    final defaultCodeBlock = find.descendant(
      of: find.byKey(defaultMarkdown),
      matching: find.byType(MarkdownCodeBlock),
    );

    /// 既定のコードブロックに表示済みの文字と出現中の文字が両方あるか
    /// (どちらか片方だけのフレームで比べると、不透明度が全部 1 の列同士を
    /// 突き合わせるだけになってしまう)。
    bool bothStates() {
      if (defaultCodeBlock.evaluate().isEmpty) return false;
      final spans = revealedSpans(tester, within: defaultCodeBlock);
      return spans.any((span) => span.opacity >= opaqueThreshold) &&
          spans.any((span) => span.opacity < opaqueThreshold);
    }

    var frames = 0;
    while (!bothStates()) {
      await tester.pump(frameInterval);
      frames++;
      expect(
        frames,
        lessThanOrEqualTo(maxSampleFrames),
        reason:
            '$maxSampleFrames フレーム以内に、既定のコードブロックに'
            '表示済みの文字と出現中の文字が両方あるフレームが来る',
      );
    }

    final expected = revealedCharOpacities(tester, within: defaultCodeBlock);
    final actual = revealedCharOpacities(
      tester,
      within: find.byKey(builtCodeBlock),
    );

    expect(
      actual.map((e) => e.char).join(),
      expected.map((e) => e.char).join(),
      reason: '補助関数を通しても描かれる文字は既定と同じ',
    );
    for (var i = 0; i < expected.length; i++) {
      expect(
        actual[i].opacity,
        closeTo(expected[i].opacity, opacityTolerance),
        reason: '$i 文字目 "${expected[i].char}" の不透明度が既定の描き方と同じ',
      );
    }
  });
}
