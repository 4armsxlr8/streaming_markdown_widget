import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'helpers/reveal.dart';

/// 公開入口から使う基準値の集まり ([StreamingReplyStyle]) のテスト (AC-11, AC-12)。
///
/// 主張するのは (a) 利用側が渡した見た目の値が描かれた文字と Widget の寸法に
/// 出ること、(b) 利用側が Controller に渡した時間の値が出現の進み方に出ること、
/// (c) 省略すると初期値 (今のサンプルの値) になること、(d) 不正な値が
/// [ArgumentError] で拒否され境界値は受け入れられること、(e) 役割ごとの
/// `TextStyle` で指定しなかった属性が周囲の [DefaultTextStyle] から
/// 引き継がれること。
///
/// 同値クラス代表 1 点の規律で、見た目は本文の `TextStyle` (色・文字サイズ・
/// 太さ・字間) と余白から 1 つずつ、時間は出現の間隔・不透明度の時間・
/// 追いつきの上限・早送りの 4 つだけを見る (全フィールドは総当たりしない)。
/// 周囲の [DefaultTextStyle] を引き継ぐ規則も 11 役割を総当たりせず、本文の
/// `TextStyle` 1 つで代表させる。出現の見た目・思考の枠の光・待機の点の
/// 動きは spec の「テストしないと決めたもの」なので触らない。
///
/// [StreamingReplyStyle] のコンストラクタは不正な値を (デバッグ・リリースの
/// 双方で) [ArgumentError] にするので `const` にはできない。このファイルは
/// どこでも `const StreamingReplyStyle(...)` と書かない。
///
/// 公開入口 (`package:streaming_markdown_widget/streaming_markdown_widget.dart`)
/// だけを import して書く — 利用側が書けるコードと同じものでテストを組む。
/// Widget のテストは [pumpFrames] で 1 フレーム (16ms) ずつ進め、Controller の
/// テストは [StreamingReplyController.tick] に [Duration] を直接渡す。
void main() {
  // ── 初期値 (今のサンプルの値) ──

  /// 本文の文字色の初期値。
  const defaultTextColor = Color(0xFF1D2026);

  /// 本文の文字サイズの初期値。
  const defaultBodyFontSize = 14.0;

  /// ブロックの下余白の初期値。
  const defaultBlockSpacing = 11.0;

  /// 基準の出現の間隔の初期値 (40 文字/秒)。
  const defaultRevealInterval = Duration(milliseconds: 25);

  // ── 利用側が渡す値 (初期値とは別の値にする) ──

  const textColor = Color(0xFF116644);
  const bodyFontSize = 20.0;
  const bodyFontWeight = FontWeight.w600;
  const bodyLetterSpacing = 1.5;
  const blockSpacing = 30.0;

  /// 周囲の [DefaultTextStyle] に置くフォント名と字間。本文の `TextStyle` では
  /// どちらも指定しないので、引き継がれたときだけ描かれた文字に出る。
  const ambientFontFamily = 'TestFamily';
  const ambientLetterSpacing = 2.0;

  /// 周囲を引き継ぐテストで本文の `TextStyle` に指定する文字サイズ
  /// (初期値の 14 とも [bodyFontSize] とも別の値)。
  const inheritedFontSize = 16.0;

  /// 返答の Widget を置く幅。段落が折り返らない広さにする。
  const replyWidth = 360.0;

  /// 段落 2 つの返答 (記法なし。改行 2 つを含めて 16 文字)。
  const twoParagraphs = '一つ目の段落。\n\n二つ目の段落。';

  /// [twoParagraphs] の 16 文字が出現し終わるまで進める時間
  /// (16 文字 × 25ms + 不透明度の 300ms に余裕を足す)。
  const timeToSettle = Duration(milliseconds: 1200);

  /// 20 文字の塊。既定の遅れの上限 24 文字以下なので、省略時は追いつきに入らない。
  const twentyChars = 'あいうえおかきくけこさしすせそたちつてと';

  /// 24 文字の塊。既定の遅れの上限ちょうどなので、省略時は基準の速さで流れる。
  const twentyFourChars = 'あいうえおかきくけこあいうえおかきくけこさしすせ';

  /// 寸法・不透明度の比較に許す誤差。
  const tolerance = 0.5;
  const opacityTolerance = 1e-9;

  /// 表示済みと見なす不透明度の下限 (これ未満は出現中)。
  const opaqueThreshold = 1 - opacityTolerance;

  /// 表示済みの文字と出現中の文字が並ぶフレームを探して進める最大フレーム数
  /// (14 文字なら 25ms 間隔の出現開始と 300ms の不透明度で 42 フレーム以内に来る)。
  const maxSampleFrames = 60;

  /// [revealing] のうち通し番号が [index] の文字の不透明度。
  /// 出現中に無ければ (まだ出現していない / 表示済み) null。
  double? opacityOf(List<RevealingChar> revealing, int index) {
    for (final revealingChar in revealing) {
      if (revealingChar.index == index) return revealingChar.opacity;
    }
    return null;
  }

  /// [reply] を [replyWidth] の幅で画面に置く。[ambient] を渡すと、その
  /// [DefaultTextStyle] で包んだ中に置く (Material 既定の [DefaultTextStyle]
  /// より内側に入れて、周囲の style をこれ 1 つに決めるため)。
  Future<void> pumpReply(
    WidgetTester tester,
    StreamingReply reply, {
    TextStyle? ambient,
  }) async {
    final Widget sized = SizedBox(width: replyWidth, child: reply);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ambient == null
                ? sized
                : DefaultTextStyle(style: ambient, child: sized),
          ),
        ),
      ),
    );
  }

  /// 表示済みの文字と出現中の文字が同じフレームに並んでいるか。
  bool bothStates(WidgetTester tester) {
    final spans = revealedSpans(tester);
    return spans.any((span) => span.opacity >= opaqueThreshold) &&
        spans.any((span) => span.opacity < opaqueThreshold);
  }

  /// [span] の文字色から出現の不透明度 (アルファ) を外した色。出現中の 1 文字は
  /// 文字色にアルファだけを乗せて描かれるので、色そのものを比べるには 1 に戻す。
  Color? opaqueColorOf(RevealedSpan span) =>
      span.style?.color?.withValues(alpha: 1);

  /// 段落 2 つの間隔 (下の段落の上端 − 上の段落の下端)。
  double paragraphGap(WidgetTester tester) {
    final paragraphs = find.descendant(
      of: find.byType(RevealedMarkdown),
      matching: find.byType(RichText),
    );
    expect(paragraphs, findsNWidgets(2), reason: '前提: 段落 2 つが描かれている');
    return tester.getTopLeft(paragraphs.at(1)).dy -
        tester.getBottomLeft(paragraphs.at(0)).dy;
  }

  testWidgets(
    'AC-11 本文の TextStyle (色・文字サイズ・太さ・字間) とブロックの下余白を渡すと、描かれた文字の style と段落の間隔がその値になる',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpReply(
        tester,
        StreamingReply(
          controller: controller,
          style: StreamingReplyStyle(
            bodyTextStyle: const TextStyle(
              color: textColor,
              fontSize: bodyFontSize,
              fontWeight: bodyFontWeight,
              letterSpacing: bodyLetterSpacing,
            ),
            blockSpacing: blockSpacing,
          ),
        ),
      );

      controller.addChunk(const Chunk(twoParagraphs));
      await pumpFrames(tester, timeToSettle);

      final spans = revealedSpans(tester);
      expect(spans, isNotEmpty, reason: '前提: 返答の文字が描かれている');
      expect(
        visibleText(tester),
        '一つ目の段落。二つ目の段落。',
        reason: '前提: 16 文字すべてが出現し終わっている',
      );
      expect(
        spans.map((span) => span.style?.color).toSet(),
        <Color>{textColor},
        reason: '描かれた文字の色は渡した色 (初期値の $defaultTextColor ではない)',
      );
      expect(
        spans.map((span) => span.style?.fontSize).toSet(),
        <double>{bodyFontSize},
        reason:
            '描かれた文字の大きさは渡した文字サイズ '
            '(初期値の $defaultBodyFontSize ではない)',
      );
      expect(
        spans.map((span) => span.style?.fontWeight).toSet(),
        <FontWeight>{bodyFontWeight},
        reason: '描かれた文字の太さは渡した太さ (初期値の本文は太さを持たない)',
      );
      expect(
        spans.map((span) => span.style?.letterSpacing).toSet(),
        <double>{bodyLetterSpacing},
        reason: '描かれた文字の字間は渡した字間 (初期値の本文は字間を持たない)',
      );
      expect(
        paragraphGap(tester),
        closeTo(blockSpacing, tolerance),
        reason: '段落の間隔は渡した下余白 (初期値の $defaultBlockSpacing ではない)',
      );
    },
  );

  testWidgets('AC-11 基準値を渡さないと、描かれた文字の色・文字サイズと段落の間隔は初期値になる', (tester) async {
    final controller = StreamingReplyController();
    await pumpReply(tester, StreamingReply(controller: controller));

    controller.addChunk(const Chunk(twoParagraphs));
    await pumpFrames(tester, timeToSettle);

    final spans = revealedSpans(tester);
    expect(
      visibleText(tester),
      '一つ目の段落。二つ目の段落。',
      reason: '前提: 16 文字すべてが出現し終わっている',
    );
    expect(spans.map((span) => span.style?.color).toSet(), <Color>{
      defaultTextColor,
    }, reason: '省略時の文字色は今のサンプルと同じ');
    expect(
      spans.map((span) => span.style?.fontSize).toSet(),
      <double>{defaultBodyFontSize},
      reason: '省略時の文字サイズは今のサンプルと同じ',
    );
    expect(
      paragraphGap(tester),
      closeTo(defaultBlockSpacing, tolerance),
      reason: '省略時のブロックの下余白は今のサンプルと同じ',
    );
  });

  testWidgets(
    'AC-11 周囲の DefaultTextStyle にフォント名と字間があると、本文の TextStyle で指定しなかったその 2 つを表示済みの文字も出現中の文字も引き継ぎ、文字色は初期値になる',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpReply(
        tester,
        StreamingReply(
          controller: controller,
          style: StreamingReplyStyle(
            bodyTextStyle: const TextStyle(fontSize: inheritedFontSize),
          ),
        ),
        ambient: const TextStyle(
          fontFamily: ambientFontFamily,
          letterSpacing: ambientLetterSpacing,
        ),
      );

      controller.addChunk(const Chunk(twoParagraphs));

      // 表示済みの文字と出現中の文字が同じフレームに並ぶまで進める
      // (片方しかないフレームで見ると、もう片方の style を見落とす)。
      var frames = 0;
      while (!bothStates(tester)) {
        await tester.pump(frameInterval);
        frames++;
        expect(
          frames,
          lessThanOrEqualTo(maxSampleFrames),
          reason: '$maxSampleFrames フレーム以内に表示済みの文字と出現中の文字が両方あるフレームが来る',
        );
      }

      final spans = revealedSpans(tester);
      final displayed = spans
          .where((span) => span.opacity >= opaqueThreshold)
          .toList();
      final revealing = spans
          .where((span) => span.opacity < opaqueThreshold)
          .toList();
      expect(displayed, isNotEmpty, reason: '前提: 表示済みの文字がある');
      expect(revealing, isNotEmpty, reason: '前提: 出現中の文字がある');

      expect(
        spans.map((span) => span.style?.fontFamily).toSet(),
        <String>{ambientFontFamily},
        reason: '本文の TextStyle にフォント名が無いので、表示済みも出現中も周囲のフォント名で描かれる',
      );
      expect(
        spans.map((span) => span.style?.letterSpacing).toSet(),
        <double>{ambientLetterSpacing},
        reason: '本文の TextStyle に字間が無いので、表示済みも出現中も周囲の字間で描かれる',
      );
      expect(
        spans.map((span) => span.style?.fontSize).toSet(),
        <double>{inheritedFontSize},
        reason: '本文の TextStyle に指定した文字サイズは周囲に上書きされない',
      );
      expect(
        displayed.map((span) => span.style?.color).toSet(),
        <Color>{defaultTextColor},
        reason: '周囲も本文の TextStyle も文字色を持たないので、初期値の文字色で埋まる',
      );
      expect(
        revealing.map(opaqueColorOf).toSet(),
        <Color>{defaultTextColor},
        reason: '出現中の 1 文字も同じ初期値の文字色 (不透明度だけがアルファに乗る)',
      );
    },
  );

  test('AC-11 出現の間隔を 50ms にすると、文字が出現を始める間隔が 50ms ごとになる', () {
    final controller = StreamingReplyController(
      style: StreamingReplyStyle(
        revealInterval: const Duration(milliseconds: 50),
      ),
    );
    controller.addChunk(const Chunk('画面表示'));

    controller.tick(Duration.zero);
    expect(controller.reply.startedCount, 1, reason: '最初の文字は塊の到着時刻に出現を始める');

    controller.tick(defaultRevealInterval);
    expect(
      controller.reply.startedCount,
      1,
      reason:
          '25ms ではまだ 2 文字目は始まらない '
          '(初期値の 25ms のままなら 2 文字目が始まっている)',
    );

    controller.tick(const Duration(milliseconds: 50));
    expect(controller.reply.startedCount, 2, reason: '2 文字目は 50ms に始まる');

    controller.tick(const Duration(milliseconds: 150));
    expect(
      controller.reply.startedCount,
      4,
      reason: '4 文字目は 150ms に始まる (50ms 間隔の 4 文字目)',
    );
  });

  test('AC-11 不透明度の時間を 100ms にすると、文字は出現開始から 100ms で表示済みになる', () {
    final controller = StreamingReplyController(
      style: StreamingReplyStyle(
        fadeDuration: const Duration(milliseconds: 100),
      ),
    );
    controller.addChunk(const Chunk('画面表示'));

    controller.tick(Duration.zero);
    controller.tick(const Duration(milliseconds: 50));
    expect(
      opacityOf(controller.reply.revealing, 0),
      closeTo(0.5, opacityTolerance),
      reason:
          '1 文字目の不透明度は 50ms ÷ 100ms '
          '(初期値の 300ms のままなら 50 ÷ 300)',
    );
    expect(
      controller.reply.displayedCount,
      0,
      reason: '前提: 50ms ではまだ表示済みの文字は無い',
    );

    controller.tick(const Duration(milliseconds: 100));
    expect(
      controller.reply.displayedCount,
      1,
      reason:
          '1 文字目は 0ms + 100ms で不透明度 1 に達する '
          '(初期値の 300ms のままなら 100ms では 0 文字)',
    );
  });

  test(
    'AC-11 追いつきの上限を 300ms にしても、20 文字の塊の追いつきは最速の 16ms 間隔までで、出し切るのは 412ms',
    () {
      final controller = StreamingReplyController(
        style: StreamingReplyStyle(
          catchUpBudget: const Duration(milliseconds: 300),
        ),
      );
      controller.addChunk(const Chunk(twentyChars));
      controller.tick(Duration.zero);
      expect(controller.reply.receivedCount, 20, reason: '前提: 塊は 20 文字');

      controller.tick(const Duration(milliseconds: 405));
      expect(
        controller.reply.startedCount,
        19,
        reason:
            '遅れの上限が 300ms ÷ 25ms = 12 文字になるので 20 文字は追いつきに入るが、'
            '割り当て間隔は max(300ms ÷ 20, 16ms) = 16ms で頭打ちになるので '
            '405ms では 19 文字目まで (上限が無ければ 15ms 間隔で 405ms にちょうど出し切る)',
      );

      controller.tick(const Duration(milliseconds: 412));
      expect(
        controller.reply.startedCount,
        20,
        reason:
            '先頭 8 文字を最速の 16ms 間隔 (0ms〜112ms)、残り 12 文字を基準の '
            '25ms 間隔 (137ms〜412ms) で出すので、出し切るのは 412ms',
      );

      // 省略時は上限 600ms ÷ 25ms = 24 文字なので、同じ 20 文字は追いつきに入らない。
      final defaultController = StreamingReplyController();
      defaultController.addChunk(const Chunk(twentyChars));
      defaultController.tick(Duration.zero);
      defaultController.tick(const Duration(milliseconds: 412));
      expect(
        defaultController.reply.startedCount,
        17,
        reason:
            '省略時の遅れの上限は 24 文字なので 20 文字は基準の 25ms 間隔のまま '
            '(412ms 時点で 17 文字目まで)',
      );
    },
  );

  test(
    'AC-11 早送りの時間を 200ms にしても、受信完了時の残り 20 文字の早送りは最速の 16ms 間隔までで、出し切るのは 404ms',
    () {
      final controller = StreamingReplyController(
        style: StreamingReplyStyle(
          fastForwardBudget: const Duration(milliseconds: 200),
        ),
      );
      controller.addChunk(const Chunk(twentyFourChars));
      controller.tick(Duration.zero);
      controller.tick(const Duration(milliseconds: 100));
      expect(
        controller.reply.pendingCount,
        19,
        reason: '前提: 100ms 時点で 5 文字が出現を始め、残りは 19 文字',
      );

      controller.complete();
      controller.tick(const Duration(milliseconds: 290));
      expect(
        controller.reply.startedCount,
        16,
        reason:
            '受信完了 (100ms) の時点の残り 20 文字の割り当て間隔は '
            'max(min(200ms ÷ 20, 25ms), 16ms) = 16ms で頭打ちになるので '
            '290ms では 16 文字目まで (上限が無ければ 10ms 間隔で 290ms に出し切る)',
      );

      controller.tick(const Duration(milliseconds: 404));
      expect(
        controller.reply.startedCount,
        24,
        reason:
            '残り 20 文字を 16ms 間隔で出すので、最後の文字は 100ms + 19 × 16ms = 404ms に始まる '
            '(初期値の 400ms のままなら 20ms 間隔で 404ms 時点は 20 文字目)',
      );
      expect(controller.reply.pendingCount, 0);
    },
  );

  test(
    'AC-12 時間 0・TextStyle の文字サイズ NaN と行間 0・負の余白・待機の点の不透明度 1.1 と 下限 > 上限・最速の間隔 > 出現の間隔 は ArgumentError で拒否される',
    () {
      expect(
        () => StreamingReplyStyle(revealInterval: Duration.zero),
        throwsArgumentError,
        reason: '非正の時間は黙って補正せず拒否する',
      );
      expect(
        () => StreamingReplyStyle(minRevealInterval: Duration.zero),
        throwsArgumentError,
        reason: '非正の最速の間隔は拒否する',
      );
      expect(
        () => StreamingReplyStyle(
          minRevealInterval: const Duration(milliseconds: 30),
          revealInterval: const Duration(milliseconds: 25),
        ),
        throwsArgumentError,
        reason:
            '1 文字ずつ出す間隔より長い最速の間隔は拒否する '
            '(追いつき・早送りが基準より遅くなるので、値の組み合わせとして成り立たない)',
      );
      expect(
        () => StreamingReplyStyle(
          bodyTextStyle: const TextStyle(fontSize: double.nan),
        ),
        throwsArgumentError,
        reason: '`TextStyle` に指定した有限でない文字サイズは拒否する',
      );
      expect(
        () =>
            StreamingReplyStyle(thinkingTextStyle: const TextStyle(height: 0)),
        throwsArgumentError,
        reason: '`TextStyle` に指定した非正の行間は拒否する',
      );
      expect(
        () => StreamingReplyStyle(blockSpacing: -1),
        throwsArgumentError,
        reason: '負の余白は拒否する',
      );
      expect(
        () => StreamingReplyStyle(waitingDotMaxOpacity: 1.1),
        throwsArgumentError,
        reason: '0〜1 の外の待機の点の不透明度は拒否する',
      );
      expect(
        () => StreamingReplyStyle(
          waitingDotMinOpacity: 0.9,
          waitingDotMaxOpacity: 0.5,
        ),
        throwsArgumentError,
        reason: '待機の点の不透明度の下限が上限を超えていれば拒否する',
      );
    },
  );

  test(
    'AC-12 境界値 (余白 0・待機の点の不透明度 0 と 1・最速の間隔 = 出現の間隔・文字サイズ未指定の TextStyle) は受け入れる',
    () {
      final style = StreamingReplyStyle(
        blockSpacing: 0,
        waitingDotMinOpacity: 0,
        waitingDotMaxOpacity: 1,
        minRevealInterval: const Duration(milliseconds: 25),
        revealInterval: const Duration(milliseconds: 25),
        bodyTextStyle: const TextStyle(fontWeight: FontWeight.w600),
      );

      expect(style.blockSpacing, 0, reason: '余白 0 は受け入れる');
      expect(style.waitingDotMinOpacity, 0, reason: '待機の点の不透明度の下限 0 は受け入れる');
      expect(style.waitingDotMaxOpacity, 1, reason: '待機の点の不透明度の上限 1 は受け入れる');
      expect(
        style.minRevealInterval,
        style.revealInterval,
        reason: '最速の間隔と出現の間隔が等しいのは受け入れる (追いつき・早送りが基準と同じ速さになるだけ)',
      );
      expect(
        style.bodyTextStyle.fontSize,
        isNull,
        reason: '文字サイズ未指定の `TextStyle` は受け入れ、渡したまま持つ (周囲から引き継ぐので既定値で埋めない)',
      );
    },
  );
}
