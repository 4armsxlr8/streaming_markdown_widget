import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'helpers/reveal.dart';

/// 1 区分の Widget を単体で置いたときに出現が進むことのテスト
/// (AC-4, AC-23, AC-28)。
///
/// ここで主張するのは 3 つ — 利用側が時計を回す部品 (合成 Widget) を
/// 組まなくても、[RevealedMarkdown] / [ThinkingFrame] を単体で置いただけで
/// 出現が進み、表示済みが増えること (AC-4)。そして [ThinkingFrame] は単体でも
/// 枠の状態を自分で進めること — 思考中は本文が 1 行の高さを持ち、思考が終わると
/// 畳まれて見出し行が「n 秒考えました」になる (AC-23)。そして枠の開閉のカーブが
/// Widget 側の基準値で差し替えられ、畳みの時間そのものは Controller 側の
/// `thinkingCollapseDuration` のままであること (AC-28)。出現の間隔・追いつき・早送りの規則
/// そのものは `streaming_reply_controller_test.dart` と
/// `revealed_markdown_test.dart` が固定しているのでここでは繰り返さない。
/// 合成 Widget ([StreamingReply]) で包んだ従来の形は
/// `streaming_reply_test.dart` が固定しているので触らない。
///
/// 時間は Widget の中の Ticker 越しにしか進まないので、テストから
/// `controller.tick` は呼ばず、[pumpFrames] で 1 フレーム (16ms) ずつ進める。
/// `pumpAndSettle` は使わない (思考の枠の見出し行の光が 1.6 秒周期で回り続ける
/// ので終わらない)。
void main() {
  /// 基準の速さ 40 文字/秒 の 1 文字あたりの間隔。
  const revealInterval = Duration(milliseconds: 25);

  /// 1 文字の不透明度が 0 から 1 になるまでの時間。
  const fadeDuration = Duration(milliseconds: 300);

  /// 不透明度の比較に許す誤差。
  const opacityTolerance = 1e-6;

  /// 不透明度がこの値以上なら表示済みとみなす。
  const opaqueThreshold = 1 - opacityTolerance;

  /// 返答の文 (記法を含まない 12 文字)。
  const replyText = '合成なしで出現する返答。';

  /// 思考の文 (記法を含まない 6 文字。1 行に収まる長さ)。
  const thinkingText = '考えの要約。';

  /// [replyText] の文字数。
  const replyCount = 12;

  /// 塊が届いてから全文が表示済みになるまでの時間。
  ///
  /// 12 文字が 25ms 間隔で出現を始め (最後の文字は 275ms)、各文字は 300ms で
  /// 表示済みになる。Widget が出現開始を刻むのは「その文字が初めて描かれた
  /// フレーム」なので、フレームの刻み 4 つ分を余裕として足す。
  final revealAllDuration =
      revealInterval * replyCount + fadeDuration + frameInterval * 4;

  /// 最初の塊を届ける前に進める時間。
  ///
  /// 計画文の「1 フレーム進めてから届ける」の意図 (到着時刻が [Duration.zero]
  /// でない状態を作る) を、widget test でも効く長さにしたもの。widget test の
  /// フレーム時刻は 0 近辺から始まるので 1 フレーム (16ms) では
  /// [Duration.zero] との差が小さすぎ、「到着が [Duration.zero] で解決される」
  /// 経路を観測で区別できない。全文が出現し終えるだけの時間を先に流して
  /// おけば、その経路では最初の観測の時点で 12 文字すべてが出現を始めた
  /// (しかも表示済みの) 状態になるので、途中の観測がそれを弾く。
  final beforeChunkDuration = revealAllDuration;

  /// 描かれている文字数 (= 出現を始めた文字数)。
  int startedCount(WidgetTester tester) =>
      visibleText(tester).characters.length;

  /// 表示済み (不透明度 1) の文字数。
  int displayedCount(WidgetTester tester) => revealedSpans(tester)
      .where((span) => span.opacity >= opaqueThreshold)
      .fold(0, (count, span) => count + span.text.characters.length);

  /// 受信完了の時点の残りを出し切るまでの猶予 (早送り)。
  const fastForwardBudget = Duration(milliseconds: 400);

  /// 本文の箱の高さが変わるのにかかる時間 ([AnimatedSize] の 300ms)。畳みも同じ。
  const collapseDuration = Duration(milliseconds: 300);

  /// 思考が流れている間の見出し行の文言 (三点リーダは U+2026)。
  const thinkingTitle = '考え中…';

  /// 思考が終わった後の見出し行の形 (n は秒数)。
  final thoughtForSecondsPattern = RegExp(r'^\d+ 秒考えました$');

  /// 省略時の基準値 (思考の文の文字サイズ 12.5 と行間 1.7 を読む)。
  final defaultStyle = StreamingReplyStyle();

  /// 思考の文 1 行の高さ (12.5 × 1.7 = 21.25)。
  final oneLineHeight =
      defaultStyle.thinkingTextStyle.fontSize! *
      defaultStyle.thinkingTextStyle.height!;

  /// 高さの比較に許す誤差。
  const heightTolerance = 1.0;

  /// 本文の箱の高さ (1 行 / 畳み)。
  double bodyHeight(WidgetTester tester) {
    expect(
      find.byKey(Keys.thinkingFrameBody),
      findsOneWidget,
      reason: '本文の箱は畳んでも tree に居る (高さが 0 になる)',
    );
    return tester.getRect(find.byKey(Keys.thinkingFrameBody)).height;
  }

  /// 見出し行の文言 (光を流すために [Text.rich] で組んでいてもよい)。
  String headTitle(WidgetTester tester) {
    expect(
      find.byKey(Keys.thinkingFrameTitle),
      findsOneWidget,
      reason: '見出し行の Text が tree に居る',
    );
    final text = tester.widget<Text>(find.byKey(Keys.thinkingFrameTitle));
    return text.data ?? text.textSpan?.toPlainText() ?? '';
  }

  /// [child] を合成 Widget で包まず単体で置く。
  Future<void> pumpStandalone(WidgetTester tester, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  testWidgets('AC-4 1 区分の Widget を合成 Widget で包まず単体で置き、塊を届けて時間を進めると、'
      '出現が 1 文字ずつ進んで表示済みが全文になる', (tester) async {
    expect(replyText.characters.length, replyCount, reason: '前提: 返答の文は 12 文字');

    final controller = StreamingReplyController();
    await pumpStandalone(
      tester,
      RevealedMarkdown(controller: controller, kind: ChunkKind.reply),
    );

    await pumpFrames(tester, beforeChunkDuration);
    expect(startedCount(tester), 0, reason: '前提: 塊が届く前は 1 文字も描かれていない');

    controller.addChunk(const Chunk(replyText));
    await tester.pump();

    await pumpFrames(tester, revealInterval * 3);
    final startedEarly = startedCount(tester);
    expect(
      startedEarly,
      inInclusiveRange(1, replyCount - 1),
      reason:
          '塊が届いた直後は、出現を始めた文字が 1 文字以上あり、'
          'まだ全文には届いていない (一斉には出ない)',
    );

    await pumpFrames(tester, revealInterval * 3);
    expect(
      startedCount(tester),
      greaterThan(startedEarly),
      reason: '単体で置いても時計が進むので、出現は 1 文字目で止まらずに先へ進む',
    );
    expect(
      displayedCount(tester),
      lessThan(replyCount),
      reason: '出現の途中なので、全文がまとめて表示済みになってはいない',
    );

    await pumpFrames(tester, revealAllDuration);
    expect(visibleText(tester), replyText, reason: '時間を進めれば全文が描かれる');
    expect(
      revealedSpans(tester).map((span) => span.opacity),
      everyElement(closeTo(1, opacityTolerance)),
      reason: '全文が表示済み (不透明度 1) になる',
    );
  });

  testWidgets('AC-4 思考の枠を合成 Widget で包まず単体で置き、思考の塊を届けて時間を進めると、'
      '同じように出現が進んで表示済みが全文になる', (tester) async {
    final controller = StreamingReplyController();
    await pumpStandalone(tester, ThinkingFrame(controller: controller));

    await pumpFrames(tester, beforeChunkDuration);
    expect(startedCount(tester), 0, reason: '前提: 思考の塊が届く前は 1 文字も描かれていない');

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await tester.pump();

    await pumpFrames(tester, revealInterval * 3);
    expect(
      startedCount(tester),
      inInclusiveRange(1, thinkingText.characters.length - 1),
      reason:
          '思考の枠も、Ticker を回す部品で包まずに出現が始まり、'
          'まだ全文には届いていない',
    );

    await pumpFrames(tester, revealAllDuration);
    expect(visibleText(tester), thinkingText, reason: '時間を進めれば思考の文が全文描かれる');
    expect(
      revealedSpans(tester).map((span) => span.opacity),
      everyElement(closeTo(1, opacityTolerance)),
      reason: '思考の文も全文が表示済み (不透明度 1) になる',
    );
  });

  testWidgets('AC-23 思考の枠を合成 Widget で包まず単体で置き、思考の塊を届けて流し終えると、'
      '枠の状態が自分で進む (思考中は本文が 1 行の高さ、終わると畳まれて見出し行が'
      '「n 秒考えました」になる)', (tester) async {
    final controller = StreamingReplyController();
    await pumpStandalone(
      tester,
      ThinkingFrame(
        controller: controller,
        // 見出し行の文言の既定は「…」なので、このテストが主張する
        // 「考え中…」「n 秒考えました」は利用側として渡す。
        thinkingTitle: thinkingTitle,
        thoughtForSeconds: (seconds) => '$seconds 秒考えました',
      ),
    );

    await pumpFrames(tester, frameInterval);

    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await tester.pump();

    // 本文の箱は AnimatedSize (300ms) で 0 から 1 行の高さへ伸びるので、
    // 伸びきるまで進めてから測る。
    await pumpFrames(tester, collapseDuration + frameInterval * 4);

    expect(
      headTitle(tester),
      thinkingTitle,
      reason: '思考が流れている間の見出し行は「$thinkingTitle」',
    );
    expect(
      bodyHeight(tester),
      closeTo(oneLineHeight, heightTolerance),
      reason: '思考中の本文は 1 行の高さを持つ (合成 Widget で包まなくても)',
    );

    controller.complete();
    await tester.pump();

    // 早送り (400ms) で残りを出し切り、畳み (300ms) で高さが 0 になる。
    await pumpFrames(
      tester,
      fastForwardBudget + collapseDuration + frameInterval * 4,
    );

    expect(
      headTitle(tester),
      matches(thoughtForSecondsPattern),
      reason:
          '思考が終わると見出し行は「n 秒考えました」になる '
          '(Controller を listen していなければ「$thinkingTitle」のまま止まる)',
    );
    expect(
      bodyHeight(tester),
      lessThanOrEqualTo(heightTolerance),
      reason: '思考が終わると本文は畳まれて高さが 0 に戻る',
    );
  });

  // ── 思考の枠の開閉のカーブ (AC-28) ──

  /// 開閉のカーブを見るときの畳みの時間 (100 フレームぶん)。
  ///
  /// 既定の 300ms では半分が 9 フレームしかなく、1 フレームのずれが高さの 5% を
  /// 動かしてしまう。長くしておけば、半分の時点のずれは高さの 1% に収まる。
  /// 畳みの時間は今までどおり Controller 側の [StreamingReplyStyle] から
  /// 読まれるので、渡すのも Controller 側。
  const slowCollapseDuration = Duration(milliseconds: 1600);

  /// [slowCollapseDuration] の半分のフレーム数 (1600ms ÷ 16ms ÷ 2)。
  const halfCollapseFrames = 50;

  /// 畳みが始まるまでに進めるフレーム数の上限 (早送りの 400ms + 余裕)。
  const maxCollapseWaitFrames = 60;

  /// 思考を流し終えて畳みに入り、畳みの時間の半分まで進める。
  ///
  /// 返すのは畳みに入る前の高さ (start) と、半分の時点の高さ (half)。[style] は
  /// 思考の枠に渡す Widget 側の基準値 (省略すると渡さない = 既定)。
  ///
  /// 畳みが始まるのは早送りが終わってからなので、時刻で決め打ちせず、枠の状態が
  /// 畳みに変わったフレームを探してそこから数える ([AnimatedSize] はその
  /// フレームのレイアウトで動き始め、まだ畳み前の高さを描いている)。
  Future<({double start, double half})> collapseHalfway(
    WidgetTester tester, {
    StreamingReplyStyle? style,
  }) async {
    final controller = StreamingReplyController(
      style: StreamingReplyStyle(
        thinkingCollapseDuration: slowCollapseDuration,
      ),
    );
    await pumpStandalone(
      tester,
      ThinkingFrame(controller: controller, style: style),
    );

    await pumpFrames(tester, frameInterval);
    controller.addChunk(const Chunk(thinkingText, kind: ChunkKind.thinking));
    await tester.pump();

    // 本文の箱が 0 から 1 行の高さへ伸びるのにも同じ時間がかかるので、
    // 伸びきるまで進めてから畳み前の高さを測る。
    await pumpFrames(tester, slowCollapseDuration + frameInterval * 4);
    final start = bodyHeight(tester);
    expect(
      start,
      closeTo(oneLineHeight, heightTolerance),
      reason: '前提: 畳みに入る前の本文は 1 行の高さ',
    );

    controller.complete();
    await tester.pump();

    var waited = 0;
    while (controller.thinkingFrame != ThinkingFrameState.collapsed) {
      await tester.pump(frameInterval);
      waited++;
      expect(
        waited,
        lessThan(maxCollapseWaitFrames),
        reason: '前提: 受信完了のあと早送りが終わると枠が畳みに入る',
      );
    }
    expect(
      bodyHeight(tester),
      closeTo(start, heightTolerance),
      reason: '前提: 畳みに入った最初のフレームではまだ畳み前の高さ',
    );

    await pumpFrames(tester, frameInterval * halfCollapseFrames);
    return (start: start, half: bodyHeight(tester));
  }

  testWidgets('AC-28 開閉のカーブに Curves.linear を渡して思考を流し終え、'
      '畳みの時間の半分まで進めると、枠の高さが線形の中間値 (畳み前と畳み後の中点) になる', (tester) async {
    final heights = await collapseHalfway(
      tester,
      style: StreamingReplyStyle(thinkingCollapseCurve: Curves.linear),
    );

    expect(
      heights.half,
      closeTo(heights.start / 2, heightTolerance),
      reason:
          '線形のカーブなら、畳みの時間の半分の時点の高さも中点 '
          '(畳み前の高さと畳み後の 0 の中点) になる。畳みの時間は Widget 側に'
          '渡した基準値ではなく Controller 側の thinkingCollapseDuration のまま',
    );
  });

  testWidgets('AC-28 開閉のカーブを渡さずに思考を流し終え、畳みの時間の半分まで進めると、'
      '既定 (fastOutSlowIn) では枠の高さが中点と異なる', (tester) async {
    final heights = await collapseHalfway(tester);

    expect(
      heights.half,
      isNot(closeTo(heights.start / 2, heightTolerance)),
      reason: '既定の fastOutSlowIn は序盤が速いので、半分の時点の高さは中点にならない',
    );
    expect(
      heights.half,
      inExclusiveRange(0, heights.start),
      reason:
          '中点と違うのは畳みの途中だからで、畳み終わっている (高さ 0) からではない。'
          '畳みの時間は Controller 側の thinkingCollapseDuration のまま',
    );
  });
}
