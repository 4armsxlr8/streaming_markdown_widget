import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/src/sample_reply.dart';

import 'helpers/app.dart';
import 'helpers/reveal.dart';

/// サンプル画面 ([ReplyPage]) のテスト (AC-1, AC-13, AC-14)。
///
/// 主張するのは画面にあるもの (返答の吹き出し・待機の点・「最初から流す」
/// ボタン) と、自動で流れ始めること・押すと 0 から流れ直すこと・返答を
/// 長押ししても選択が始まらないこと。背景色や吹き出し・ボタンの質感は spec の
/// 「テストしないと決めたもの」なので触らない。
///
/// 供給のむら (間隔 125ms × [0.5, 2.0) の乱数) も「テストしないと決めたもの」
/// なので、時間は必ず乱数の幅を吸収できる余裕で進める — 1 塊が届くまでの
/// 上限は [maxChunkInterval]、以下の「〜まで許す時間」はすべてその上限で
/// 見積もった値。乱数の実際の出目には一切依存しない。
///
/// 時間は [RevealTicker] が回す Ticker と供給の Timer 越しにしか進まないので、
/// [pumpFrames] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle` は使わない
/// (待機の点と見出し行の光が回り続けるので終わらない)。
void main() {
  /// 「最初から流す」ボタンの文言。
  const replayLabel = '最初から流す';

  /// 塊が 1 つ届くまでの間隔の上限 (125ms × 2.0)。
  const maxChunkInterval = Duration(milliseconds: 250);

  /// 流れ始めたことを見るまでに進める時間。
  ///
  /// 最初の塊は遅くとも [maxChunkInterval] で届き、出現はその次のフレームから
  /// 始まるので、2 秒あれば必ず思考の文が出ている。
  const startBudget = Duration(seconds: 2);

  /// サンプルの返答の最初の文字が吹き出しに出るまでに許す時間の上限。
  ///
  /// 思考の文 (約 130 文字 = 1 塊 4〜8 文字で 30 塊ほど) が遅くとも
  /// 30 × 250ms = 7.5 秒で届き切り、畳みに 300ms、返答の最初の数塊が
  /// 記法だけで可視文字を持たないことも見込んで 20 秒を上限にする。
  const replyBudget = Duration(seconds: 20);

  /// 短い思考の文と返答が出揃うまでに許す時間の上限
  /// (それぞれ 2 塊 = 4 × 250ms に畳みと出現を足した余裕)。
  const shortFlowBudget = Duration(seconds: 5);

  /// 「最初から流す」を押したあと、前の供給が生きていれば必ず次の塊を届けて
  /// いるといえる時間 ([maxChunkInterval] の 4 倍)。
  ///
  /// これ以上長く進めても前の供給について分かることは増えず、新しい流れの
  /// 返答が伸びるだけなので短く取る。
  const stopBudget = Duration(seconds: 1);

  /// 受信完了まで進めるテストで使う短い思考の文。
  const shortThinking = '短い思考。';

  /// 受信完了まで進めるテストで使う短い返答 (記法なし)。
  const shortReply = '短い返答。';

  /// 「n 秒考えました」の形。
  final thinkingDoneTitle = RegExp(r'^\d+ 秒考えました$');

  /// [total] を [frameInterval] 刻みで進めるのに要るフレーム数。
  int framesFor(Duration total) =>
      (total.inMicroseconds / frameInterval.inMicroseconds).ceil();

  /// [key] に描かれている可視文字列。
  String visibleOf(WidgetTester tester, Key key) =>
      visibleText(tester, within: find.byKey(key));

  /// [key] の Text の文字 (光を流すために [Text.rich] で組んでいてもよい)。
  String textOf(WidgetTester tester, Key key) {
    expect(find.byKey(key), findsOneWidget, reason: '$key の Text が tree に居る');
    final text = tester.widget<Text>(find.byKey(key));
    return text.data ?? text.textSpan?.toPlainText() ?? '';
  }

  /// [condition] が満たされるまで 1 フレームずつ進める。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    required Duration budget,
    required String reason,
  }) async {
    final maxFrames = framesFor(budget);
    for (var frame = 0; frame < maxFrames; frame++) {
      await tester.pump(frameInterval);
      if (condition()) return;
    }
    fail('${budget.inMilliseconds}ms 進めても条件が満たされなかった: $reason');
  }

  /// 受信前の姿 (返答の吹き出しに待機の点、思考の枠は無し) になっているか。
  void expectBeforeReceiving(WidgetTester tester, {required String reason}) {
    expect(
      find.byKey(Keys.thinkingFrame),
      findsNothing,
      reason: '$reason: 思考の枠が居ない',
    );
    expect(
      find.byKey(Keys.replyBubble),
      findsOneWidget,
      reason: '$reason: 返答の吹き出しが 1 つ居る',
    );
    expect(
      find.byKey(Keys.waitingDots),
      findsOneWidget,
      reason: '$reason: 吹き出しの中は待機の点 (返答は 0 文字)',
    );
  }

  /// 思考の文が [thinking] の先頭から流れ始めているか。
  void expectThinkingFlowing(
    WidgetTester tester,
    String thinking, {
    required String reason,
  }) {
    expect(find.byKey(Keys.thinkingFrame), findsOneWidget, reason: '$reason: 思考の枠が出る');
    final visible = visibleOf(tester, Keys.thinkingText);
    expect(visible, isNotEmpty, reason: '$reason: 思考の文が出現を始めている');
    expect(
      thinking.startsWith(visible),
      isTrue,
      reason: '$reason: 見えているのは思考の文の先頭からの続き '
          '(前の供給が同じ Controller へ届き続けていれば先頭からの続きにならない)',
    );
  }

  testWidgets(
    'AC-1 起動すると返答の吹き出しに待機の点と「最初から流す」ボタンが出て、'
    '返答が自動で流れ始める',
    (tester) async {
      await pumpApp(tester);

      expectBeforeReceiving(tester, reason: '起動直後は受信前の姿');
      expect(
        find.byKey(Keys.replayButton),
        findsOneWidget,
        reason: '「最初から流す」ボタンが 1 つ居る',
      );
      expect(
        find.descendant(
          of: find.byKey(Keys.replayButton),
          matching: find.text(replayLabel),
          matchRoot: true,
        ),
        findsOneWidget,
        reason: 'ボタンの文言は「$replayLabel」',
      );

      // 起動すると自動で流れ始める (押さなくてよい)。
      await pumpFrames(tester, startBudget);
      expectThinkingFlowing(tester, sampleThinking, reason: '自動で流れ始める');

      // さらに進めれば返答の文字が吹き出しに出る。思考の塊が届き切って枠が
      // 畳まれるまで返答は流れないので、可視文字が出るまで待つ。
      await pumpUntil(
        tester,
        () => visibleOf(tester, Keys.replyText).isNotEmpty,
        budget: replyBudget,
        reason: '返答の文字が吹き出しに出ない',
      );
      expect(
        find.byKey(Keys.replyBubble),
        findsOneWidget,
        reason: '返答の文字は返答の吹き出しの中に出る',
      );
      expect(
        find.byKey(Keys.waitingDots),
        findsNothing,
        reason: '返答が届いたら待機の点は居なくなる',
      );
    },
  );

  testWidgets(
    'AC-13 受信中に「最初から流す」を押すと、受信前の姿に戻って 0 から流れ直し、'
    '前の流れは止まる',
    (tester) async {
      await pumpApp(tester);

      // 返答は最短の間隔 (62.5ms) で届いても 6 秒以上かかるので、2 秒の時点は
      // 必ず受信中。
      await pumpFrames(tester, startBudget);
      expectThinkingFlowing(tester, sampleThinking, reason: '前提: もう流れている');

      await tester.tap(find.byKey(Keys.replayButton));
      // 時間を進めずに 1 フレームだけ描く (供給の Timer はまだ発火しない)。
      await tester.pump();

      expectBeforeReceiving(tester, reason: '押した直後は受信前の姿 = 0 文字から');

      await pumpFrames(tester, startBudget);
      expectThinkingFlowing(tester, sampleThinking, reason: 'また流れ始める');

      // 前の流れが止まっていなければ、捨てた Controller へ塊が届いて
      // dispose 後使用の例外になる。
      await pumpFrames(tester, stopBudget);
      expect(
        tester.takeException(),
        isNull,
        reason: '前の供給が止まっているので例外は出ない',
      );
    },
  );

  testWidgets(
    'AC-13 受信完了後に「最初から流す」を押すと、受信前の姿に戻って 0 から'
    '流れ直し、前の流れは止まる',
    (tester) async {
      await pumpReplyPage(tester, thinking: shortThinking, reply: shortReply);

      await pumpUntil(
        tester,
        () => visibleOf(tester, Keys.replyText) == shortReply,
        budget: shortFlowBudget,
        reason: '短い返答が出揃わない',
      );
      // 受信完了は最後の塊のあとに届くので、出揃ってから 1 塊ぶんの間隔を
      // 足して進める (出揃った時点ではまだ受信中のことがある)。
      await pumpFrames(tester, maxChunkInterval + frameInterval * 2);

      expect(
        textOf(tester, Keys.thinkingFrameTitle),
        matches(thinkingDoneTitle),
        reason: '前提: 思考が終わって見出し行が「n 秒考えました」になっている',
      );
      expect(
        visibleOf(tester, Keys.replyText),
        shortReply,
        reason: '前提: 受信完了していて返答が出揃っている',
      );

      await tester.tap(find.byKey(Keys.replayButton));
      await tester.pump();

      expectBeforeReceiving(tester, reason: '押した直後は受信前の姿 = 0 文字から');

      await pumpFrames(tester, startBudget);
      expectThinkingFlowing(tester, shortThinking, reason: 'また流れ始める');

      await pumpFrames(tester, stopBudget);
      expect(
        tester.takeException(),
        isNull,
        reason: '前の供給が止まっているので例外は出ない',
      );
    },
  );

  testWidgets(
    'AC-14 返答を長押ししても選択が始まらない',
    (tester) async {
      await pumpReplyPage(tester, thinking: shortThinking, reply: shortReply);

      await pumpUntil(
        tester,
        () => visibleOf(tester, Keys.replyText) == shortReply,
        budget: shortFlowBudget,
        reason: '短い返答が出揃わない',
      );
      await pumpFrames(tester, maxChunkInterval + frameInterval * 2);

      final before = visibleOf(tester, Keys.replyText);
      expect(before, shortReply, reason: '前提: 返答が出揃っている');

      // 長押しは 600ms をまとめて進めるが、受信完了して出現も終わっているので
      // 途中のフレームで新しく描かれる文字は無い。
      await tester.longPress(find.byKey(Keys.replyText));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '長押しで例外が出ない');
      expect(
        visibleOf(tester, Keys.replyText),
        before,
        reason: '長押しの前後で返答の可視文字列は変わらない',
      );
      expect(
        find.byType(SelectableText),
        findsNothing,
        reason: '選択できる Text が居ない',
      );
      expect(
        find.byType(SelectionArea),
        findsNothing,
        reason: '選択の範囲が居ない',
      );
      expect(
        find.byType(SelectableRegion),
        findsNothing,
        reason: '選択の仕組みが居ない',
      );
      expect(
        find.byType(EditableText),
        findsNothing,
        reason: '選択の把手や虫眼鏡を出す EditableText が居ない',
      );
    },
  );
}
