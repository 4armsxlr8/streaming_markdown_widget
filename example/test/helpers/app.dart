import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget_example/src/app.dart';
import 'package:streaming_markdown_widget_example/src/reply_page.dart';

/// テストのビュー寸法 (iPhone 程度)。
///
/// 画面には返答の Widget と「最初から流す」ボタンしか無いので、兄弟サンプルの
/// ように張り出しを見込んで広げる必要はない。
const Size viewSize = Size(390, 844);

/// ビューを [viewSize] に固定してサンプルを pump する。
Future<void> pumpApp(WidgetTester tester) async {
  _fixView(tester);
  await tester.pumpWidget(const StreamingMarkdownWidgetApp());
}

/// 思考の文と返答を差し替えた画面を [viewSize] で pump する。
///
/// サンプルの思考の文・返答は受信完了まで 20 秒以上かかるので、受信完了後の
/// 挙動を見るテストは短い文を渡してこちらを使う。
Future<void> pumpReplyPage(
  WidgetTester tester, {
  required String thinking,
  required String reply,
}) async {
  _fixView(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: ReplyPage(thinking: thinking, reply: reply),
    ),
  );
}

void _fixView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewSize;
  addTearDown(tester.view.reset);
}
