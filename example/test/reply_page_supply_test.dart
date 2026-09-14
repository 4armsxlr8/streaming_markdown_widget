import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/fake_reply_source.dart';

import 'helpers/reveal.dart';

/// 作り物の供給の再現性のテスト (AC-32)。
///
/// `reply_page_test.dart` は供給のむら (乱数) に一切依存しない書き方をして
/// いるが、ここは逆に seed を固定して「同じ seed なら同じ塊の列と間隔」
/// (AC-32) を主張する。
///
/// 時間は供給の Timer 越しにしか進まないので、[frameInterval] 刻みで
/// 1 フレームずつ進める。`pumpAndSettle` は使わない。
void main() {
  /// 供給の乱数に渡す seed。値そのものに意味はなく、2 回とも同じであることだけ
  /// が効く。
  const supplySeed = 1;

  /// 供給する思考の文 (10 文字 = 3 塊)。
  const supplyThinking = 'あいうえおかきくけこ';

  /// 供給する返答 (20 文字 = 5 塊。5 回に 1 回の大きい塊も通る)。
  const supplyReply = 'あいうえおかきくけこさしすせそたちつてと';

  /// 2 つの供給を見比べるフレーム数 (8 塊 × 間隔の上限 250ms に余裕)。
  const supplyFrames = 200;

  /// [controller] の観測値のうち、塊の届き方だけで決まるぶんの写し。
  ///
  /// 受信した文字数 (思考・返答) と受信完了かどうか。フレームごとに集めると、
  /// 数の増え方が塊の切れ目、増えたフレームが届く間隔になる。
  String supplySnapshot(StreamingReplyController controller) =>
      '${controller.thinking.receivedCount}/'
      '${controller.reply.receivedCount}/'
      '${controller.isComplete}';

  testWidgets('AC-32 同じ seed で供給を 2 回作ると、塊の列と間隔が 2 回とも同じになる', (tester) async {
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
      reason:
          '同じ seed なら塊の切れ目 (受信した文字数の増え方) も間隔 '
          '(増えたフレーム) も一致する',
    );
  });
}
