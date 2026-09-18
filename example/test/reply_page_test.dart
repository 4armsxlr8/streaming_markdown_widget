import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/keys.dart';
import 'package:streaming_markdown_widget_example/src/sample_reply.dart';

import 'helpers/app.dart';
import 'helpers/reveal.dart';

/// サンプル画面 ([ReplyPage]) の文言・構成と、移した既存の挙動のテスト
/// (AC-3, AC-26)。
///
/// AC-3 が主張するのは、前の spec の画面の受け入れ基準 (AC-1・13・14) の挙動が
/// 画面を作り直した後も維持されること — 起動で自動で流れ始める・再生で受信前の
/// 姿に戻って 0 から流れ直す・返答を長押ししても選択が始まらない。再生は AppBar
/// のアイコン 1 つで、本文中のボタンは無い。
///
/// AC-26 が主張するのは画面の文言と構成 — AppBar のタイトル
/// 「Streaming Markdown Widget」と再生・キーのアイコン、入力欄のプレースホルダ
/// 「Ask anything」、思考の枠の見出し (流れている間「Thinking…」、終わると
/// 「Thought for {n}s」)、送信ボタンと再生のアイコンが読み上げから操作できる
/// こと、そして画面に日本語の文字列が無いこと。
///
/// 背景色・ボタンやダイアログの質感・出現の見た目・待機の点の動きは spec の
/// 「テストしないと決めたもの」なので触らない。
///
/// example はパッケージの内部 (`src/`) を import できないので、パッケージ側の
/// `Keys` で掴んでいたものは公開型 ([ThinkingFrame] / [RevealedMarkdown]) と
/// 文字で探す。待機の点 (`WaitingDots` は非公開) だけは掴めないため、受信前の
/// 判定は「思考の枠も返答の文字も無い」に置き換えた。
///
/// 供給のむら (間隔 125ms × [0.5, 2.0) の乱数) も「テストしないと決めたもの」
/// なので、時間は必ず乱数の幅を吸収できる余裕で進める — 1 塊が届くまでの上限は
/// [maxChunkInterval]、以下の「〜まで許す時間」はすべてその上限で見積もった値。
/// 乱数の実際の出目には一切依存しない。
///
/// 時間は `RevealTicker` が回す Ticker と供給の Timer 越しにしか進まないので、
/// [pumpFrames] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle` は使わない
/// (待機の点と見出し行の光が回り続けるので終わらない)。
void main() {
  /// 思考の枠の見出し (流れている間)。
  const thinkingTitle = 'Thinking…';

  /// 思考の枠の見出し (思考が終わった後) の形。
  final thoughtForSecondsTitle = RegExp(r'^Thought for \d+s$');

  /// 塊が 1 つ届くまでの間隔の上限 (125ms × 2.0)。
  const maxChunkInterval = Duration(milliseconds: 250);

  /// 流れ始めたことを見るまでに進める時間。
  ///
  /// 最初の塊は遅くとも [maxChunkInterval] で届き、出現はその次のフレームから
  /// 始まるので、2 秒あれば必ず思考の文が出ている。
  const startBudget = Duration(seconds: 2);

  /// サンプルの思考が流れ切って見出しが変わるまでに許す時間の上限。
  ///
  /// サンプルの思考は 1 行 (60〜70 文字 = 1 塊 4〜8 文字で 17 塊ほど) で、
  /// 遅くとも 17 × 250ms ≒ 4.3 秒で届き切る。出現と秒数の確定ぶんの余裕を見て
  /// 10 秒を上限にする。
  const thinkingDoneBudget = Duration(seconds: 10);

  /// サンプルの返答の最初の文字が画面に出るまでに許す時間の上限
  /// ([thinkingDoneBudget] に畳みと最初の数塊ぶんの余裕を足した値)。
  const replyBudget = Duration(seconds: 12);

  /// 短い思考と返答が出揃うまでに許す時間の上限
  /// (それぞれ 2 塊 = 4 × 250ms に畳みと出現を足した余裕)。
  const shortFlowBudget = Duration(seconds: 5);

  /// 再生を押したあと、前の供給が生きていれば必ず次の塊を届けているといえる
  /// 時間 ([maxChunkInterval] の 4 倍)。
  const stopBudget = Duration(seconds: 1);

  /// 思考が [thinking] の先頭から流れ始めているか。
  void expectThinkingFlowing(
    WidgetTester tester,
    String thinking, {
    required String reason,
  }) {
    expect(
      find.byType(ThinkingFrame),
      findsOneWidget,
      reason: '$reason: 思考の枠が出る',
    );
    final visible = visibleText(tester, within: thinkingText);
    expect(visible, isNotEmpty, reason: '$reason: 思考が出現を始めている');
    expect(
      thinking.startsWith(visible),
      isTrue,
      reason:
          '$reason: 見えているのは思考の先頭からの続き '
          '(前の供給が同じ Controller へ届き続けていれば先頭からの続きにならない)',
    );
  }

  /// 画面に描かれている文字列に日本語が無いか。
  void expectNoJapanese(WidgetTester tester, {required String reason}) {
    final withJapanese = screenTexts(
      tester,
    ).where(japanese.hasMatch).toList(growable: false);
    expect(withJapanese, isEmpty, reason: '$reason: 画面に日本語の文字列は無い');
  }

  testWidgets('AC-3 起動すると AppBar に再生のアイコンが出て、返答が自動で流れ始める', (tester) async {
    await pumpApp(tester);

    expectBeforeReceiving(reason: '起動直後は受信前の姿');
    expect(
      find.byKey(Keys.replayButton),
      findsOneWidget,
      reason: '再生のアイコンは画面に 1 つだけ (本文中のボタンは無い)',
    );
    expect(replayButton, findsOneWidget, reason: '再生のアイコンは AppBar にある');

    // 起動すると自動で流れ始める (押さなくてよい)。
    await pumpFrames(tester, startBudget);
    expectThinkingFlowing(tester, sampleThinking, reason: '自動で流れ始める');

    // さらに進めれば返答の文字が画面に出る。思考の塊が届き切るまで返答は
    // 流れないので、可視文字が出るまで待つ。
    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText).isNotEmpty,
      budget: replyBudget,
      reason: '返答の文字が画面に出ない',
    );
    expect(replyText, findsOneWidget, reason: '返答の文字が画面に出る');
  });

  testWidgets('AC-3 受信中に再生を押すと、受信前の姿に戻って 0 から流れ直し、前の流れは止まる', (tester) async {
    await pumpApp(tester);

    await pumpFrames(tester, startBudget);
    expectThinkingFlowing(tester, sampleThinking, reason: '前提: もう流れている');

    await tester.tap(replayButton);
    // 時間を進めずに 1 フレームだけ描く (供給の Timer はまだ発火しない)。
    await tester.pump();

    expectBeforeReceiving(reason: '押した直後は受信前の姿 = 0 文字から');

    await pumpFrames(tester, startBudget);
    expectThinkingFlowing(tester, sampleThinking, reason: 'また流れ始める');

    // 前の流れが止まっていなければ、捨てた Controller へ塊が届いて
    // dispose 後使用の例外になる。
    await pumpFrames(tester, stopBudget);
    expect(tester.takeException(), isNull, reason: '前の供給が止まっているので例外は出ない');
  });

  testWidgets('AC-3 受信完了後に再生を押すと、受信前の姿に戻って 0 から流れ直し、前の流れは止まる', (tester) async {
    await pumpReplyPage(tester, thinking: shortThinking, reply: shortReply);

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText) == shortReply,
      budget: shortFlowBudget,
      reason: '短い返答が出揃わない',
    );
    // 受信完了は最後の塊のあとに届くので、出揃ってから 1 塊ぶんの間隔を
    // 足して進める (出揃った時点ではまだ受信中のことがある)。
    await pumpFrames(tester, maxChunkInterval + frameInterval * 2);

    expect(
      find.textContaining(thoughtForSecondsTitle),
      findsOneWidget,
      reason: '前提: 思考が終わって見出しが「Thought for {n}s」になっている',
    );
    expect(
      visibleText(tester, within: replyText),
      shortReply,
      reason: '前提: 受信完了していて返答が出揃っている',
    );

    await tester.tap(replayButton);
    await tester.pump();

    expectBeforeReceiving(reason: '押した直後は受信前の姿 = 0 文字から');

    await pumpFrames(tester, startBudget);
    expectThinkingFlowing(tester, shortThinking, reason: 'また流れ始める');

    await pumpFrames(tester, stopBudget);
    expect(tester.takeException(), isNull, reason: '前の供給が止まっているので例外は出ない');
  });

  testWidgets('AC-3 返答を長押ししても選択が始まらない', (tester) async {
    await pumpReplyPage(tester, thinking: shortThinking, reply: shortReply);

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText) == shortReply,
      budget: shortFlowBudget,
      reason: '短い返答が出揃わない',
    );
    await pumpFrames(tester, maxChunkInterval + frameInterval * 2);

    final before = visibleText(tester, within: replyText);
    expect(before, shortReply, reason: '前提: 返答が出揃っている');

    // 長押しは 600ms をまとめて進めるが、受信完了して出現も終わっているので
    // 途中のフレームで新しく描かれる文字は無い。
    await tester.longPress(replyText);
    await tester.pump();

    expect(tester.takeException(), isNull, reason: '長押しで例外が出ない');
    expect(
      visibleText(tester, within: replyText),
      before,
      reason: '長押しの前後で返答の可視文字列は変わらない',
    );
    expect(
      find.byType(SelectableText),
      findsNothing,
      reason: '選択できる Text が居ない',
    );
    expect(find.byType(SelectionArea), findsNothing, reason: '選択の範囲が居ない');
    expect(find.byType(SelectableRegion), findsNothing, reason: '選択の仕組みが居ない');
    // 画面の下端には質問の入力欄 (TextField = 内部に EditableText) が居るので、
    // 木全体ではなく返答の領域の中に居ないことを主張する。
    expect(
      find.descendant(of: replyText, matching: find.byType(EditableText)),
      findsNothing,
      reason: '返答の中に、選択の把手や虫眼鏡を出す EditableText が居ない',
    );
  });

  testWidgets('AC-26 起動すると AppBar のタイトルは「$appBarTitle」で再生とキーのアイコンがあり、入力欄の'
      'プレースホルダは「$questionHint」、思考の枠の見出しは「$thinkingTitle」', (tester) async {
    // 再生とキーのアイコンを読み上げ名で探すので読み上げの木を立てる (解放の
    // 作法は helpers/app.dart の「読み上げ (Semantics) を見るテストの作法」)。
    final handle = tester.ensureSemantics();

    await pumpApp(tester);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(appBarTitle),
      ),
      findsOneWidget,
      reason: 'AppBar のタイトルは「$appBarTitle」',
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.bySemanticsLabel(replayLabel),
      ),
      findsOneWidget,
      reason: 'AppBar に読み上げ名「$replayLabel」のアイコンがある',
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.bySemanticsLabel(apiKeyLabel),
      ),
      findsOneWidget,
      reason: 'AppBar に読み上げ名「$apiKeyLabel」のアイコンがある',
    );
    expect(
      find.text(questionHint),
      findsOneWidget,
      reason: '起動時 (入力欄が空) は入力欄のプレースホルダ「$questionHint」が画面に出る',
    );

    // 思考が届き始めた時点の見出しを見る (思考は 1 行なので、時間を大きく
    // 進めると届き切って見出しが変わってしまう)。
    await pumpUntil(
      tester,
      () => find.byType(ThinkingFrame).evaluate().isNotEmpty,
      budget: startBudget,
      reason: '思考の枠が出ない',
    );
    expect(
      find.text(thinkingTitle),
      findsOneWidget,
      reason: '流れている間の思考の枠の見出しは「$thinkingTitle」',
    );

    expectNoJapanese(tester, reason: '起動してサンプルが流れている間');

    handle.dispose();
  });

  testWidgets('AC-26 起動すると送信ボタンと再生のアイコンは、読み上げから操作できる (tap の操作を持つ)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpApp(tester);

    // 送信ボタンは `excludeSemantics` で中の GestureDetector のタップを木から
    // 隠しているので、ノード自身が tap の操作を持っていないと、読み上げから
    // 操作するときに呼ぶ相手が居なくなる。
    expect(
      tester
          .getSemantics(sendButton)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
      reason: '「$sendLabel」のノードは tap の操作を持つ',
    );
    expect(
      tester
          .getSemantics(replayButton)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
      reason: '「$replayLabel」のノードも tap の操作を持つ',
    );

    handle.dispose();
  });

  testWidgets('AC-26 サンプルの思考が流れ終わると、思考の枠の見出しが「Thought for {n}s」になる', (
    tester,
  ) async {
    await pumpApp(tester);

    await pumpUntil(
      tester,
      () => find.textContaining(thoughtForSecondsTitle).evaluate().isNotEmpty,
      budget: thinkingDoneBudget,
      reason: '思考の枠の見出しが「Thought for {n}s」にならない',
    );

    expect(
      find.textContaining(thoughtForSecondsTitle),
      findsOneWidget,
      reason: '思考が終わった後の見出しは「Thought for {n}s」',
    );
    expect(
      find.text(thinkingTitle),
      findsNothing,
      reason: '思考が終わったら「$thinkingTitle」は出ていない',
    );

    expectNoJapanese(tester, reason: '思考が終わって返答が流れている間');
  });
}
