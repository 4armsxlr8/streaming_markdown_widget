import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/fake_reply_source.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/src/reply_theme.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

import 'helpers/page.dart';
import 'helpers/reveal.dart';

/// 供給の再現性と、返答が伸びるときの自動追随のテスト (AC-32, AC-33)。
///
/// `reply_page_test.dart` は供給のむら (乱数) に一切依存しない書き方をして
/// いるが、ここは逆に seed を固定して「同じ seed なら同じ塊の列と間隔」
/// (AC-32) を主張し、その固定した届き方の上でスクロール位置 (AC-33) を見る。
///
/// 時間は供給の Timer と [RevealTicker] が回す Ticker 越しにしか進まないので、
/// [pumpFrames] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle` は使わない
/// (待機の点と見出し行の光が回り続けるので終わらない)。
void main() {
  /// 供給の乱数に渡す seed。値そのものに意味はなく、2 回とも同じであることだけ
  /// が効く。
  const supplySeed = 1;

  /// AC-32 で供給する思考の文 (10 文字 = 3 塊)。
  const supplyThinking = 'あいうえおかきくけこ';

  /// AC-32 で供給する返答 (20 文字 = 5 塊。5 回に 1 回の大きい塊も通る)。
  const supplyReply = 'あいうえおかきくけこさしすせそたちつてと';

  /// AC-32 で 2 つの供給を見比べるフレーム数 (8 塊 × 間隔の上限 250ms に余裕)。
  const supplyFrames = 200;

  /// AC-33 で供給する思考の文 (短く済ませて返答へ移る)。
  const followThinking = '短い思考。';

  /// AC-33 で供給する返答 (段落 36 個。画面 (844px) より確実に高くなる)。
  final followReply = List.generate(36, (i) => '${i + 1} 行目').join('\n\n');

  /// [followReply] の最後の段落 (出し切ったかどうかの目印)。
  const followReplyLastLine = '36 行目';

  /// AC-33 で利用者が上へスクロールする距離。
  ///
  /// 末尾から 72px 以内なら追随する決まりなので、その 2 倍以上を引いて
  /// 「明らかに離れた」状態を作る。
  const dragDistance = 200.0;

  /// 返答が届き切って出現し終わるまでに許す時間の上限。
  ///
  /// 返答は約 240 文字 = 50 塊ほどで、1 塊の間隔の上限は 250ms なので
  /// 供給だけで最大 13 秒。早送りと出現のぶんを足して 20 秒で打ち切る。
  const flowBudget = Duration(seconds: 20);

  /// スクロール位置を見る前に追随を落ち着かせるフレーム数。
  const settleFrames = 8;

  /// [condition] が true になるまで [frameInterval] 刻みで進める
  /// (上限 [limit])。true にならなくても例外にはせず、呼び出し側が前提を
  /// `expect` で主張する。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    required Duration limit,
  }) async {
    for (
      var elapsed = Duration.zero;
      elapsed < limit && !condition();
      elapsed += frameInterval
    ) {
      await tester.pump(frameInterval);
    }
  }

  /// [controller] の観測値のうち、塊の届き方だけで決まるぶんの写し。
  ///
  /// 受信した文字数 (思考・返答) と受信完了かどうか。フレームごとに集めると、
  /// 数の増え方が塊の切れ目、増えたフレームが届く間隔になる。
  String supplySnapshot(StreamingReplyController controller) =>
      '${controller.thinking.receivedCount}/'
      '${controller.reply.receivedCount}/'
      '${controller.isComplete}';

  testWidgets('AC-32 同じ seed で供給を 2 回作ると、塊の列と間隔が 2 回とも同じになる', (
    tester,
  ) async {
    // 供給の Timer を進めるだけなので、画面は要らない。
    await tester.pumpWidget(const SizedBox.shrink());

    final controllers = [
      StreamingReplyController(),
      StreamingReplyController(),
    ];
    final sources = [
      for (final controller in controllers)
        FakeReplySource(
          controller: controller,
          thinking: supplyThinking,
          reply: supplyReply,
          random: Random(supplySeed),
        ),
    ];
    for (final source in sources) {
      addTearDown(source.dispose);
      source.start();
    }

    final series = [<String>[], <String>[]];
    for (var frame = 0; frame < supplyFrames; frame++) {
      await tester.pump(frameInterval);
      for (var i = 0; i < controllers.length; i++) {
        series[i].add(supplySnapshot(controllers[i]));
      }
    }

    expect(
      controllers.map((controller) => controller.isComplete),
      everyElement(isTrue),
      reason: '前提: どちらの供給も最後まで届き切った',
    );
    expect(
      series[1],
      series[0],
      reason: '同じ seed なら塊の切れ目 (受信した文字数の増え方) も間隔 '
          '(増えたフレーム) も一致する',
    );
  });

  testWidgets('AC-33 返答が画面の末尾を越えて伸びると、末尾に追随してスクロール位置が進む', (
    tester,
  ) async {
    await pumpSeededReplyPage(
      tester,
      thinking: followThinking,
      reply: followReply,
      random: Random(supplySeed),
    );

    await pumpUntil(
      tester,
      () => visibleText(
        tester,
        within: find.byKey(Keys.replyText),
      ).contains(followReplyLastLine),
      limit: flowBudget,
    );
    await pumpFrames(tester, frameInterval * settleFrames);

    final position = replyScrollPosition(tester);
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: '前提: 返答が画面の末尾を越えて伸びた',
    );
    expect(
      position.pixels,
      greaterThan(0),
      reason: '新しい文字に追随してスクロール位置が進む',
    );
    expect(
      position.maxScrollExtent - position.pixels,
      lessThanOrEqualTo(ReplyTheme.autoFollowDistance),
      reason: '追随した位置は末尾 (maxScrollExtent) の近くに留まる',
    );
  });

  testWidgets('AC-33 利用者が上へスクロールして末尾から 72px より離れると、追随せずスクロール位置が動かない', (
    tester,
  ) async {
    await pumpSeededReplyPage(
      tester,
      thinking: followThinking,
      reply: followReply,
      random: Random(supplySeed),
    );

    // 上へ離れる余地ができる (末尾から 72px より離せる) まで返答を伸ばす。
    await pumpUntil(
      tester,
      () =>
          replyScrollPosition(tester).maxScrollExtent >
          dragDistance + ReplyTheme.autoFollowDistance,
      limit: flowBudget,
    );
    expect(
      replyScrollPosition(tester).maxScrollExtent,
      greaterThan(dragDistance + ReplyTheme.autoFollowDistance),
      reason: '前提: 末尾から 72px より離れられるところまで返答が伸びた',
    );

    await tester.drag(find.byKey(Keys.replyScroll), const Offset(0, dragDistance));
    await pumpFrames(tester, frameInterval * settleFrames);

    final pixelsAfterDrag = replyScrollPosition(tester).pixels;
    final extentAfterDrag = replyScrollPosition(tester).maxScrollExtent;
    expect(
      extentAfterDrag - pixelsAfterDrag,
      greaterThan(ReplyTheme.autoFollowDistance),
      reason: '前提: 上へスクロールして末尾から 72px より離れた',
    );

    await pumpUntil(
      tester,
      () => replyScrollPosition(tester).maxScrollExtent > extentAfterDrag,
      limit: flowBudget,
    );

    expect(
      replyScrollPosition(tester).maxScrollExtent,
      greaterThan(extentAfterDrag),
      reason: '前提: 離れている間も返答は伸び続けた',
    );
    expect(
      replyScrollPosition(tester).pixels,
      moreOrLessEquals(pixelsAfterDrag, epsilon: 0.5),
      reason: '末尾から離れている間は追随せず、読んでいる位置が動かない',
    );
  });
}
