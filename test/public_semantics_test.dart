import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'helpers/reveal.dart';

/// 読み上げ (VoiceOver / TalkBack) に渡す情報のテスト (AC-10)。
///
/// 主張するのは 4 つ — 受信中でも返答の読み上げ文字列が届いた全文と一致する、
/// 思考の文も同じ、思考の枠の見出し行がボタンとして読み上げられて読み上げの
/// 操作で開閉する、そして自動で読み上げを始める (live region) ノードがどこにも
/// 無いこと。読み上げの実際の音声・読み順は実機の話なので spec の
/// 「テストしないと決めたもの」に入っており、ここでは触らない。
///
/// 「届いた全文」は未出現の文字も含むので、読み上げの内容は画面に見えている
/// 文字より先に進む — 各テストは未出現の文字が残っている状態
/// ([RevealSection.pendingCount] が 0 より大きい) を前提として作る。
///
/// 読み上げ情報は `testWidgets` が既定で有効にするので (`semanticsEnabled` の
/// 既定は true)、`tester.ensureSemantics()` は取らない — 取ると
/// `addTearDown(handle.dispose)` より先に「SemanticsHandle が残っている」の
/// 検査が走り、主張と関係ない失敗になる。
///
/// 時間は Widget の中の Ticker 越しにしか進まないので `controller.tick` は
/// 呼ばず、[pumpFrames] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle` は
/// 使わない (見出し行の光が 1.6 秒周期で回り続けるので終わらない)。
void main() {
  /// 返答の Widget を置く幅。思考の文が必ず 2 行以上に折り返る狭さにする
  /// (思考の本文は 1 行の高さに切り詰められるので、読み上げが画面に
  /// 見えている行より先に進むことを主張できる)。
  const replyWidth = 360.0;

  /// 思考が流れている間の見出し行の文言 (三点リーダは U+2026)。
  const thinkingTitle = '考え中…';

  /// 返答の文 (記法を含まない 60 文字)。
  const replyText =
      '行の高さがばらばらだと毎フレーム計測が走ってカクつきます。'
      '行の高さを固定して builder に換えると計測が減ります。';

  /// 思考の文 (記法を含まない 52 文字。幅 360 では 2 行以上に折り返る)。
  const thinkingText =
      'ユーザーは一覧のカクつきを直したい。'
      '原因は行の高さがばらばらで毎フレーム計測が走ること。手順を短く示す。';

  /// 塊を届けてから読み上げ情報を見るまでに進める時間。
  ///
  /// 基準の速さ (40 文字/秒) では 100ms で出現を始めるのは数文字なので、
  /// 60 文字 / 52 文字のどちらも未出現の文字が残る。
  const receivingDuration = Duration(milliseconds: 100);

  /// 早送りと畳みが終わるまでに許すフレーム数の上限。
  ///
  /// 早送りの割り当て間隔は最速の間隔 16ms で頭打ちになるので、思考の 52 文字
  /// を出し切るのに最悪 51 × 16ms = 816ms かかり、そこから畳みの 300ms が要る。
  /// 1116ms = 70 フレームなので、余裕を見て 100 で打ち切る。
  const maxFramesToCollapse = 100;

  /// 返答の Widget を [replyWidth] の幅で置く。
  Future<void> pumpStreamingReply(
    WidgetTester tester,
    StreamingReplyController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: replyWidth,
              child: SingleChildScrollView(
                child: StreamingReply(
                  controller: controller,
                  thinkingTitle: thinkingTitle,
                  thoughtForSeconds: (seconds) => '$seconds 秒考えました',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [condition] が満たされるまで 1 フレームずつ進める。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    required int maxFrames,
    required String reason,
  }) async {
    for (var frame = 0; frame < maxFrames; frame++) {
      await tester.pump(frameInterval);
      if (condition()) return;
    }
    fail('$maxFrames フレーム進めても条件が満たされなかった: $reason');
  }

  /// [key] から辿れる semantics ノード (自身に無ければ最も近い祖先)。
  SemanticsNode nodeOf(WidgetTester tester, Key key) {
    expect(find.byKey(key), findsOneWidget, reason: '$key が tree に居る');
    return tester.getSemantics(find.byKey(key));
  }

  /// [key] の semantics ノードへ読み上げの操作 (tap) を送る。
  ///
  /// ノードは組み直しで id が変わりうるので、送る直前に取り直す。
  Future<void> performSemanticsTap(WidgetTester tester, Key key) async {
    final node = nodeOf(tester, key);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
  }

  testWidgets('AC-10 返答の受信中でも、返答の読み上げ文字列は未出現の文字を含む届いた全文と一致し、'
      '出現中の 1 文字ずつの span は読み上げに混ざらない', (tester) async {
    final controller = StreamingReplyController();
    await pumpStreamingReply(tester, controller);

    controller.addChunk(const Chunk(replyText));
    await pumpFrames(tester, receivingDuration);

    expect(
      controller.reply.pendingCount,
      greaterThan(0),
      reason: '前提: まだ未出現の文字が残っている (受信中)',
    );
    final visible = visibleText(tester, within: find.byKey(Keys.replyText));
    expect(
      visible.length,
      lessThan(controller.reply.text.length),
      reason: '前提: 画面に見えている文字は届いた全文より短い',
    );

    final node = nodeOf(tester, Keys.replyText);
    expect(
      node.label,
      controller.reply.text,
      reason: '返答の読み上げ文字列は届いた全文 (未出現の文字を含む) と一致する',
    );
    expect(
      node.childrenCount,
      0,
      reason: '出現中の 1 文字ずつの span が読み上げの子ノードとして混ざらない',
    );
  });

  testWidgets('AC-10 思考の受信中でも、思考の読み上げ文字列は未出現の文字を含む届いた全文と一致し、'
      '本文が 1 行に切り詰められていても全文を渡す', (tester) async {
    final controller = StreamingReplyController();
    await pumpStreamingReply(tester, controller);

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await pumpFrames(tester, receivingDuration);

    expect(
      controller.thinkingFrame,
      ThinkingFrameState.line,
      reason: '前提: 思考が流れていて本文は 1 行の高さ',
    );
    expect(
      controller.thinking.pendingCount,
      greaterThan(0),
      reason: '前提: まだ未出現の文字が残っている (受信中)',
    );

    final node = nodeOf(tester, Keys.thinkingText);
    expect(
      node.label,
      controller.thinking.text,
      reason: '思考の読み上げ文字列は届いた全文 (未出現の文字を含む) と一致する',
    );
    expect(
      node.childrenCount,
      0,
      reason: '出現中の 1 文字ずつの span が読み上げの子ノードとして混ざらない',
    );
  });

  testWidgets('AC-10 思考の枠の見出し行はボタンとして読み上げられ、読み上げの操作で '
      '1 行 ⇄ 全部 (思考中) / 畳み ⇄ 全部 (畳んだ後) に切り替わる', (tester) async {
    final controller = StreamingReplyController();
    await pumpStreamingReply(tester, controller);

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await pumpFrames(tester, receivingDuration);
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.line,
      reason: '前提: 思考が流れていて本文は 1 行の高さ',
    );

    final head = nodeOf(tester, Keys.thinkingFrameHead).getSemanticsData();
    expect(head.flagsCollection.isButton, isTrue, reason: '見出し行はボタンとして読み上げる');
    expect(
      head.hasAction(SemanticsAction.tap),
      isTrue,
      reason: '見出し行は読み上げから操作できる',
    );

    await performSemanticsTap(tester, Keys.thinkingFrameHead);
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.full,
      reason: '思考中の見出し行を読み上げから操作すると全部開く',
    );
    await performSemanticsTap(tester, Keys.thinkingFrameHead);
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.line,
      reason: 'もう一度操作すると 1 行に戻る',
    );

    // 受信完了させて思考の枠を畳み、畳んだ後も同じ操作で開閉することを見る。
    controller.addChunk(const Chunk(replyText));
    controller.complete();
    await tester.pump();
    await pumpUntil(
      tester,
      () => controller.thinkingFrame == ThinkingFrameState.collapsed,
      maxFrames: maxFramesToCollapse,
      reason: '前提: 思考の枠が畳まれない',
    );

    await performSemanticsTap(tester, Keys.thinkingFrameHead);
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.full,
      reason: '畳んだ後の見出し行を読み上げから操作すると全部開く',
    );
    await performSemanticsTap(tester, Keys.thinkingFrameHead);
    expect(
      controller.thinkingFrame,
      ThinkingFrameState.collapsed,
      reason: 'もう一度操作すると畳まれる',
    );
  });

  testWidgets('AC-10 返答と思考が受信中でも、自動で読み上げを始める (live region) ノードは無い', (
    tester,
  ) async {
    final controller = StreamingReplyController();
    await pumpStreamingReply(tester, controller);

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    controller.addChunk(const Chunk(replyText));
    await pumpFrames(tester, receivingDuration);

    expect(
      controller.thinking.pendingCount,
      greaterThan(0),
      reason: '前提: 思考にまだ未出現の文字が残っている',
    );
    expect(
      controller.reply.pendingCount,
      greaterThan(0),
      reason: '前提: 返答にまだ未出現の文字が残っている',
    );
    expect(
      nodeOf(tester, Keys.thinkingText).id,
      isNot(nodeOf(tester, Keys.replyText).id),
      reason: '前提: 思考と返答の読み上げノードが別に居る',
    );

    expect(
      find.semantics.byPredicate(
        (node) => node.flagsCollection.isLiveRegion,
        describeMatch: (_) => '自動で読み上げを始める (live region) の semantics ノード',
      ),
      findsNothing,
      reason: '受信中でも自動では読み上げを始めない',
    );
  });
}
