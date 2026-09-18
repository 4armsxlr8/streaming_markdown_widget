import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/app.dart';
import 'package:streaming_markdown_widget_example/src/keys.dart';
import 'package:streaming_markdown_widget_example/src/reply_page.dart';

import 'reveal.dart';

/// テストのビュー寸法 (iPhone 程度)。
///
/// 画面にあるのは AppBar・質問の吹き出し・返答・下端から浮いた入力欄だけで、
/// 兄弟サンプルのように枠の外へ張り出すものは無いので、寸法に余裕を足す必要は
/// ない。
const Size viewSize = Size(390, 844);

/// ビューを [viewSize] に固定してサンプルを pump する。
Future<void> pumpApp(WidgetTester tester) async {
  _fixView(tester);
  await tester.pumpWidget(const StreamingMarkdownWidgetApp());
}

/// 思考と返答を差し替えた画面を [viewSize] で pump する。
///
/// サンプルは 32 文字/秒で 16 秒ほどかけて流れるので、受信完了後の挙動を見る
/// テストは短い文を渡してこちらを使う。
///
/// [apiKey] を渡すと送信は Gemini へ行き ([realReplyStream] に差し替えられる)、
/// 空なら送信はサンプルを再生する。[random] は作り物の供給の届き方を固定したい
/// ときだけ渡す (渡さなければ本物の乱数)。
Future<void> pumpReplyPage(
  WidgetTester tester, {
  required String thinking,
  required String reply,
  String apiKey = '',
  Random? random,
  Stream<Chunk> Function(String question)? realReplyStream,
}) async {
  _fixView(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: ReplyPage(
        thinking: thinking,
        reply: reply,
        apiKey: apiKey,
        random: random,
        realReplyStream: realReplyStream,
      ),
    ),
  );
}

/// 画面に描かれている文字列を集める。
///
/// [RichText] (返答の文字も [Text] の文字も、描かれるときはこれになる) と
/// [EditableText] (入力欄) の 2 つを見る。「日本語の文字列が無い」「キーの文字列
/// が出ない」のように、画面のどこにも出ないことを主張するテストで使う。
List<String> screenTexts(WidgetTester tester) {
  final texts = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    texts.add(rich.text.toPlainText());
  }
  for (final editable in tester.widgetList<EditableText>(
    find.byType(EditableText),
  )) {
    texts.add(editable.controller.text);
  }
  return texts;
}

// ── 画面の文言 (複数のテストファイルが探し当てに使うぶん) ──

/// AppBar のタイトル。
const String appBarTitle = 'Streaming Markdown Widget';

/// 入力欄のプレースホルダ。
const String questionHint = 'Ask anything';

/// 送信ボタンの読み上げ名。
const String sendLabel = 'Send';

/// AppBar の再生のアイコンの読み上げ名。
const String replayLabel = 'Replay';

/// AppBar のキーのアイコンの読み上げ名と、ダイアログの入力欄のラベル
/// (どちらも「API key」)。
const String apiKeyLabel = 'API key';

/// キーのダイアログのタイトルと注記。
const String dialogTitle = 'Gemini API key';
const String dialogNote = 'Kept in memory only. Cleared when the app closes.';

/// キーのダイアログの 2 つのボタン。
const String apiKeyClearLabel = 'Clear';
const String apiKeyUseLabel = 'Use key';

/// エラーの 1 行の頭 (AC-20: 「Error: 」で始まる)。
final RegExp errorLinePrefix = RegExp(r'^Error: ');

/// 日本語にあたる文字 (全角の句読点・ひらがな・カタカナ・漢字・半角カナ)。
///
/// 「…」(U+2026) は日本語の文字ではないので含めない — 思考の枠の見出し
/// 「Thinking…」で使う。
final RegExp japanese = RegExp(r'[　-〿぀-ヿ一-鿿！-｠｡-ﾟ]');

// ── テストが渡す値 ──

/// 画面に渡す API キー (値そのものに意味はなく、空でないことだけが効く —
/// Gemini への送信は差し替えるのでキーは使われない。サンプルの英文には出て
/// こない文字列にして、「画面のどのテキストにも出ない」を見られるようにする)。
const String apiKey = 'AIzaTestKey123';

/// 入力欄に打つ質問。
const String question = 'How do I fix janky scrolling?';

/// 受信完了まで進めるテストで使う短い思考と返答 (記法なし)。
///
/// サンプルは 32 文字/秒で 16 秒ほどかけて流れるので、受信完了後の挙動を見る
/// テストはこれを [pumpReplyPage] に渡す。
const String shortThinking = '短い思考。';
const String shortReply = '短い返答。';

// ── 時間 ──

/// ダイアログの出入りが終わるまで進める時間 (Material の 150ms に余裕)。
const Duration dialogTransition = Duration(milliseconds: 200);

/// 短い思考と返答が出揃うまでに許す時間の上限
/// (出現 25ms/文字・畳み 300ms・早送り 400ms に余裕を足した値)。
const Duration flowBudget = Duration(seconds: 5);

// ── 画面の部品の Finder ──

/// 画面下端の質問の入力欄。
final Finder questionField = find.byKey(Keys.questionField);

/// 入力欄の送信ボタン。
final Finder sendButton = find.byKey(Keys.sendButton);

/// AppBar の再生のアイコン。
final Finder replayButton = find.descendant(
  of: find.byType(AppBar),
  matching: find.byKey(Keys.replayButton),
);

/// AppBar のキーのアイコン。
final Finder apiKeyIcon = find.byKey(Keys.apiKeyButton);

/// キーのダイアログと、その中のキーの入力欄 (`AlertDialog` も [Dialog] を組む)。
final Finder apiKeyDialog = find.byType(Dialog);
final Finder apiKeyDialogField = find.descendant(
  of: find.byType(Dialog),
  matching: find.byType(TextField),
);

// ── 読み上げ (Semantics) を見るテストの作法 ──

// 読み上げ名や読み上げの状態 (`tester.getSemantics`) を見るテストは、冒頭で
// `tester.ensureSemantics()` を呼んで読み上げの木を立て、解放はテストの末尾で
// `handle.dispose()` を明示的に呼ぶ — 解放を `addTearDown` に預けると
// 「テスト終了時に SemanticsHandle が生きている」と怒られる。

// ── 画面の姿の主張 ──

/// 受信前の姿 (思考の枠も返答の文字も無い = 返答は 0 文字) になっているか。
void expectBeforeReceiving({required String reason}) {
  expect(find.byType(ThinkingFrame), findsNothing, reason: '$reason: 思考の枠が居ない');
  expect(replyText, findsNothing, reason: '$reason: 返答の文字はまだ無い');
}

// ── 画面の操作 ──

/// [question] を入力欄に打って送信ボタンを押す。
Future<void> sendQuestion(WidgetTester tester, String question) async {
  expect(questionField, findsOneWidget, reason: '前提: 質問の入力欄がある');
  await tester.enterText(questionField, question);
  await tester.pump();
  await tester.tap(sendButton);
  await tester.pump();
}

/// キーのアイコンを押してダイアログを開く。
Future<void> openApiKeyDialog(WidgetTester tester) async {
  await tester.tap(apiKeyIcon);
  await pumpFrames(tester, dialogTransition);
}

/// ダイアログを開いて [key] を入れ、「Use key」で閉じる。
Future<void> useApiKey(WidgetTester tester, String key) async {
  await openApiKeyDialog(tester);
  await tester.enterText(apiKeyDialogField, key);
  await tester.pump();
  await tester.tap(find.text(apiKeyUseLabel));
  await pumpFrames(tester, dialogTransition);
}

/// ダイアログを開いて「Clear」で閉じる (キーを空にする)。
Future<void> clearApiKey(WidgetTester tester) async {
  await openApiKeyDialog(tester);
  await tester.tap(find.text(apiKeyClearLabel));
  await pumpFrames(tester, dialogTransition);
}

void _fixView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = viewSize;
  addTearDown(tester.view.reset);
}
