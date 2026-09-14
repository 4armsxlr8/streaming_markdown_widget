import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'helpers/reveal.dart';

/// 公開入口から使う思考の枠の文言と合成 Widget のテスト
/// (AC-7, AC-8, AC-9, AC-22)。
///
/// 主張するのは見出し行に出る文言 (既定の「…」・利用側が渡した文言・秒数の
/// 関数が受け取る値) と、返答の文字と待機の点に吹き出し (地の色・枠・影) が
/// 描かれないこと。文言の中身以外の見た目 (光・余白・待機の点の動き) は spec の
/// 「テストしないと決めたもの」なので触らない。
///
/// [Keys] だけは公開入口に無いので `src/keys.dart` を足すが、Widget と
/// Controller は公開入口から取る。時間は [RevealTicker] が回す Ticker 越しに
/// しか進まないので `controller.tick` は呼ばず、[pumpFrames] で 1 フレーム
/// (16ms) ずつ進める。`pumpAndSettle` は使わない (見出し行の光が 1.6 秒周期で
/// 回り続けるので終わらない)。
void main() {
  /// 基準の速さ 40 文字/秒 の 1 文字あたりの間隔。
  const revealInterval = Duration(milliseconds: 25);

  /// 思考の枠を畳むのにかかる時間。
  const collapseDuration = Duration(milliseconds: 300);

  /// 思考が流れている間の見出し行の文言の既定 (三点リーダは U+2026)。
  const defaultThinkingTitle = '…';

  /// example が渡す思考中の文言。
  const thinkingTitle = '考え中…';

  /// 思考の最初の塊から受信完了までに進めるフレーム数。16ms × 125 = ちょうど 2 秒。
  const framesToComplete = 125;

  /// 測った秒数 (「n 秒考えました」の n)。[framesToComplete] を四捨五入した値。
  const measuredSeconds = 2;

  /// 利用側が渡す秒数 (測った値 [measuredSeconds] とは別の値にする)。
  const overrideSeconds = 7;

  /// 思考の文 (記法なし。6 文字)。
  const thinkingText = '考えの要約。';

  /// 返答の文 (記法なし。5 文字)。
  const replyText = '返答の文。';

  /// [reply] を画面に置く。
  Future<void> pumpReply(WidgetTester tester, StreamingReply reply) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: reply)),
      ),
    );
  }

  /// 見出し行の文言 (光を流すために [Text.rich] で組んでいてもよい)。
  String headTitle(WidgetTester tester) {
    final finder = find.byKey(Keys.thinkingFrameTitle);
    expect(finder, findsOneWidget, reason: '見出し行の Text が tree に居る');
    final text = tester.widget<Text>(finder);
    return text.data ?? text.textSpan?.toPlainText() ?? '';
  }

  /// 思考の塊を届けてから受信完了まで 2 秒進め、畳み終わるまで待つ。
  Future<void> flowThinkingThenComplete(
    WidgetTester tester,
    StreamingReplyController controller,
  ) async {
    await pumpFrames(tester, frameInterval * framesToComplete);
    controller.complete();
    await pumpFrames(tester, collapseDuration + frameInterval * 4);
    expect(controller.isThinking, isFalse, reason: '前提: 思考が終わっている');
  }

  /// [key] の Widget が吹き出し (地の色・枠・影) に包まれていないこと。
  ///
  /// 吹き出しは [Container] の装飾なので、合成 Widget の中でその Widget の
  /// 祖先になる [DecoratedBox] / [ColoredBox] が 1 つも無いことで主張する
  /// (Key が消えてもこの主張は残る)。
  void expectNoBubble(WidgetTester tester, Key key, {required String reason}) {
    for (final boxType in const <Type>[DecoratedBox, ColoredBox]) {
      expect(
        find.ancestor(
          of: find.byKey(key),
          matching: find.descendant(
            of: find.byType(StreamingReply),
            matching: find.byType(boxType),
          ),
        ),
        findsNothing,
        reason: '$reason: 周りに $boxType (地の色・枠・影) は描かれない',
      );
    }
  }

  testWidgets('AC-7 思考の枠の文言を渡さないと、思考中も思考が終わった後も見出し行は「…」のままで秒数は出ない', (
    tester,
  ) async {
    final controller = StreamingReplyController();
    await pumpReply(tester, StreamingReply(controller: controller));

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await tester.pump();
    expect(
      headTitle(tester),
      defaultThinkingTitle,
      reason: '思考中の見出し行の既定は「…」(三点、U+2026)',
    );

    await flowThinkingThenComplete(tester, controller);

    expect(
      controller.thinkingSeconds,
      isNotNull,
      reason: '前提: 秒数は測れている (出ないのは文言を渡していないから)',
    );
    expect(
      headTitle(tester),
      defaultThinkingTitle,
      reason: '秒数の文言を渡さなければ思考が終わっても「…」のまま',
    );
    expect(headTitle(tester), isNot(matches(RegExp(r'\d'))), reason: '秒数は出ない');
  });

  testWidgets('AC-8 思考中の文言と秒数の関数を渡すと、思考中は渡した文言が出て、思考が終わると測った秒数を受け取った関数の結果が出る', (
    tester,
  ) async {
    final receivedSeconds = <int>[];
    final controller = StreamingReplyController();
    await pumpReply(
      tester,
      StreamingReply(
        controller: controller,
        thinkingTitle: thinkingTitle,
        thoughtForSeconds: (seconds) {
          receivedSeconds.add(seconds);
          return '$seconds 秒考えました';
        },
      ),
    );

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await tester.pump();
    expect(headTitle(tester), thinkingTitle, reason: '思考中は渡した文言が出る');

    await flowThinkingThenComplete(tester, controller);

    expect(
      headTitle(tester),
      '$measuredSeconds 秒考えました',
      reason: '思考が終わると秒数の関数の結果が出る',
    );
    expect(
      receivedSeconds.last,
      measuredSeconds,
      reason:
          '関数が受け取るのは測った秒数 '
          '(思考の最初の塊から受信完了までの $framesToComplete フレーム = 2 秒)',
    );
  });

  testWidgets('AC-9 利用側が秒数を渡すと、秒数の関数は測った値ではなく渡した値を受け取る', (tester) async {
    final receivedSeconds = <int>[];
    final controller = StreamingReplyController()
      ..thinkingSecondsOverride = overrideSeconds;
    await pumpReply(
      tester,
      StreamingReply(
        controller: controller,
        thinkingTitle: thinkingTitle,
        thoughtForSeconds: (seconds) {
          receivedSeconds.add(seconds);
          return '$seconds 秒考えました';
        },
      ),
    );

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await tester.pump();
    await flowThinkingThenComplete(tester, controller);

    expect(
      receivedSeconds.last,
      overrideSeconds,
      reason:
          '関数が受け取るのは利用側が渡した $overrideSeconds '
          '(測った値の $measuredSeconds ではない)',
    );
    expect(headTitle(tester), '$overrideSeconds 秒考えました');
    expect(
      controller.thinkingSeconds,
      overrideSeconds,
      reason: '秒数の観測値も渡した値で上書きされる',
    );
  });

  testWidgets('AC-22 受信前の待機の点にも受信中の返答の文字にも、吹き出し (地の色・枠・影) は描かれない', (
    tester,
  ) async {
    final controller = StreamingReplyController();
    await pumpReply(tester, StreamingReply(controller: controller));

    expect(
      find.byKey(Keys.waitingDots),
      findsOneWidget,
      reason: '前提: 受信前は待機の点が出る',
    );
    expectNoBubble(tester, Keys.waitingDots, reason: '受信前の待機の点');

    controller.addChunk(const Chunk(replyText));
    await pumpFrames(tester, revealInterval * 4);

    expect(find.byKey(Keys.replyText), findsOneWidget, reason: '前提: 返答の文字が出る');
    expect(
      visibleText(tester, within: find.byKey(Keys.replyText)),
      isNotEmpty,
      reason: '前提: 返答の文字が出現を始めている',
    );
    expectNoBubble(tester, Keys.replyText, reason: '受信中の返答の文字');
  });
}
