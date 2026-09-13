import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/src/reply_page.dart';

import 'app.dart' show viewSize;

/// 供給の乱数を固定した画面のヘルパ (AC-32, AC-33)。
///
/// 既存の `app.dart` の `pumpReplyPage` は乱数を渡せないので、seed を固定して
/// 塊の届き方を決めたいテストはこちらを使う (`app.dart` は書き換えない)。

/// 供給の乱数に [random] を渡した画面を [viewSize] で pump する。
Future<void> pumpSeededReplyPage(
  WidgetTester tester, {
  required String thinking,
  required String reply,
  required Random random,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewSize;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ReplyPage(thinking: thinking, reply: reply, random: random),
    ),
  );
}

/// 画面の縦スクロール ([Keys.replyScroll]) の位置。
///
/// コードブロックや表は自前の横スクロールを持つので、`Keys.replyScroll` の
/// 下で最初に見つかる [Scrollable] (= 縦スクロールそのもの) を取る。
ScrollPosition replyScrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(Keys.replyScroll),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;
