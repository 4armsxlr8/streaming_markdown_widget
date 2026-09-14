import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/keys.dart';
import 'package:streaming_markdown_widget_example/src/reply_page.dart';

import 'helpers/app.dart' show viewSize;
import 'helpers/reveal.dart';

/// 供給の切り替え・入力欄・「送る」とエラーの 1 行のテスト (AC-19, AC-20)。
///
/// seam は利用例アプリの画面。主張するのは 5 つ — API キーが無ければ本物の
/// 供給は選べず理由が 1 行出て作り物が流れる、本物を選んでまだ送っていない間は
/// 返答の位置に案内の 1 行が出る (待機の点は出ない)、キーがあれば入力欄の質問が
/// 本物の供給へ 1 回送られて入力欄が空になり質問が返答の上に 1 行出て返答が 0 から
/// 流れる (「最初から流す」は直前の質問を再送する)、本物の受信中は「送る」と
/// 「最初から流す」が無効で Stream は 1 本のまま (受信完了で再び送れる)、そして
/// 本物がエラーで終わると返答の下にエラーの 1 行が出て届いた分の文字は残る。
///
/// 本物の Gemini は呼ばない (spec の「テストしないと決めたもの」)。本物の供給は
/// [ReplyPage.realReplyStream] の差し替え口に作り物の [Stream] を渡して代える。
/// 画面が組み立てる URL やヘッダは項目 7 の変換のテスト
/// (`gemini_reply_source_test.dart`) の持ち分なので、ここでは触らない。
///
/// 起動時は作り物が選ばれていて自動で流れ始めるので、本物のテストは pump した
/// 直後に切り替えてから送る。作り物の届き方は [Random] の seed で固定する
/// (`reply_page_supply_test.dart` と同じ作法)。
///
/// 時間は供給の Timer と返答の Widget が回す Ticker 越しにしか進まないので、
/// [pumpFrames] / [pumpUntil] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle`
/// は使わない (待機の点と見出し行の光が回り続けるので終わらない)。
void main() {
  /// 切り替えの文言。
  const fakeSupplyLabel = '作り物';
  const realSupplyLabel = '本物 (Gemini)';

  /// キーが無いときに出る理由の 1 行。
  const noKeyReasonLine = 'API キーが無いため本物は選べません';

  /// 本物を選んでまだ送っていない間、返答の位置に出る案内の 1 行。
  const guidanceLineText = '質問を入力して送ってください';

  /// 入力欄の案内 (placeholder)。
  const questionHint = '質問を入力';

  /// 「送る」ボタンの読み上げ名。
  const sendLabel = '送る';

  /// 画面に渡す API キー (値そのものに意味はなく、空でないことだけが効く —
  /// 本物の供給は差し替えるのでキーは使われない)。
  const apiKey = 'test-key';

  /// 供給の乱数に渡す seed (作り物の届き方を固定するためだけのもの)。
  const supplySeed = 1;

  /// 作り物の供給が流す思考の文と返答 (短く済ませる)。
  const fakeThinking = '作り物の思考。';
  const fakeReply = '作り物の返答。';

  /// 入力欄に打つ質問。
  const question = 'リストのカクつきを直したい';
  const secondQuestion = '表の出し方も知りたい';

  /// 本物の供給 (差し替えた Stream) が流す思考の文と返答。
  const realThinking = '本物の思考。';
  const realReply = '本物の返答。';

  /// 2 通目の本物の供給が流す返答。
  const secondReply = '2 通目の返答。';

  /// AC-20 で届く返答の 2 塊と、エラーの文言。
  const errorFirstChunk = '届いた 1 塊目。';
  const errorSecondChunk = '届いた 2 塊目。';
  const errorReply = '$errorFirstChunk$errorSecondChunk';
  const errorMessage = '通信に失敗しました';

  /// 作り物の供給が流れ始めたことを見るまでに進める時間
  /// (1 塊の間隔の上限 250ms に余裕を足した値)。
  const startBudget = Duration(seconds: 2);

  /// 短い思考の文と返答が出揃うまでに許す時間の上限
  /// (出現 25ms/文字・畳み 300ms・早送り 400ms に余裕を足した値)。
  const flowBudget = Duration(seconds: 5);

  /// 上部の切り替えの 2 つのボタン。
  final fakeSupplyButton = find.text(fakeSupplyLabel);
  final realSupplyButton = find.text(realSupplyLabel);

  /// キーが無い理由の 1 行。
  final noKeyReason = find.text(noKeyReasonLine);

  /// 未送信の案内の 1 行。
  final guidanceLine = find.text(guidanceLineText);

  /// 「最初から流す」ボタン。
  final replayButton = find.byKey(Keys.replayButton);

  /// 下端に固定した入力欄と「送る」ボタン。
  ///
  /// 「送る」は読み上げ名で探すので、Finder を作るには読み上げの仕組みが要る。
  /// `main()` のトップレベルで作ると binding の初期化前に
  /// `SemanticsBinding.instance` へ触れて読み込みに失敗するので、各テストの中で
  /// 遅延して作る (各テストは冒頭で `tester.ensureSemantics()` を呼ぶ)。
  final questionField = find.byType(TextField);
  Finder sendButton() => find.bySemanticsLabel(sendLabel);

  /// 返答の文字 (返答の区分の [RevealedMarkdown])。
  final replyText = find.byWidgetPredicate(
    (widget) => widget is RevealedMarkdown && widget.kind == ChunkKind.reply,
  );

  /// 思考の文 (思考の区分の [RevealedMarkdown])。
  final thinkingText = find.byWidgetPredicate(
    (widget) => widget is RevealedMarkdown && widget.kind == ChunkKind.thinking,
  );

  /// [finder] に描かれている可視文字列 (見つからなければ空)。
  String visibleOf(WidgetTester tester, Finder finder) =>
      visibleText(tester, within: finder);

  /// [condition] が満たされるまで 1 フレームずつ進める。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    required Duration budget,
    required String reason,
  }) async {
    for (
      var elapsed = Duration.zero;
      elapsed < budget;
      elapsed += frameInterval
    ) {
      await tester.pump(frameInterval);
      if (condition()) return;
    }
    fail('${budget.inMilliseconds}ms 進めても条件が満たされなかった: $reason');
  }

  /// 受信前の姿 (思考の枠も返答の文字も無い = 返答は 0 文字)。
  void expectBeforeReceiving({required String reason}) {
    expect(
      find.byType(ThinkingFrame),
      findsNothing,
      reason: '$reason: 思考の枠が居ない',
    );
    expect(replyText, findsNothing, reason: '$reason: 返答の文字はまだ無い');
  }

  /// 切り替え・入力欄・「送る」を持つ画面を [viewSize] で pump する。
  ///
  /// `helpers/app.dart` の `pumpReplyPage` は [apiKey] と
  /// [ReplyPage.realReplyStream] を渡せないので、このスライスのテストは
  /// こちらを使う (移した既存テストの pump は書き換えない)。
  Future<void> pumpSwitchableReplyPage(
    WidgetTester tester, {
    required String apiKey,
    required Stream<Chunk> Function(String question) realReplyStream,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewSize;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ReplyPage(
          thinking: fakeThinking,
          reply: fakeReply,
          random: Random(supplySeed),
          apiKey: apiKey,
          realReplyStream: realReplyStream,
        ),
      ),
    );
  }

  /// 本物を選んで [question] を入力し「送る」を押す。
  Future<void> sendQuestion(WidgetTester tester, String question) async {
    await tester.enterText(questionField, question);
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
  }

  /// 無効な [button] を押す (効かないことを見るためのタップ)。
  ///
  /// 無効の表し方しだいでタップが Widget まで届かないので `warnIfMissed` を
  /// 外す — 主張は「押しても供給が作り直されない」で、当たり判定そのものでは
  /// ない。
  Future<void> tapWhileDisabled(WidgetTester tester, Finder button) async {
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
  }

  /// [button] の読み上げが「無効」を表していること。
  void expectDisabled(WidgetTester tester, Finder button, String reason) {
    expect(
      tester.getSemantics(button),
      isSemantics(hasEnabledState: true, isEnabled: false),
      reason: reason,
    );
  }

  /// [button] の読み上げが「有効」を表していること。
  void expectEnabled(WidgetTester tester, Finder button, String reason) {
    expect(
      tester.getSemantics(button),
      isSemantics(hasEnabledState: true, isEnabled: true),
      reason: reason,
    );
  }

  testWidgets('AC-19 API キー無しで起動すると「本物 (Gemini)」は選べず理由が 1 行出て、'
      '作り物が流れる', (tester) async {
    // 読み上げ名で「送る」を探すので読み上げの木を立てる。解放は
    // `addTearDown` ではなくテストの末尾で明示的に呼ぶ (`addTearDown` だと
    // 「テスト終了時に SemanticsHandle が生きている」と怒られる)。
    final handle = tester.ensureSemantics();
    final asked = <String>[];

    await pumpSwitchableReplyPage(
      tester,
      apiKey: '',
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    expect(
      fakeSupplyButton,
      findsOneWidget,
      reason: '上部に「$fakeSupplyLabel」が居る',
    );
    expect(
      realSupplyButton,
      findsOneWidget,
      reason: '上部に「$realSupplyLabel」が居る',
    );
    expect(noKeyReason, findsOneWidget, reason: 'キーが無い理由が 1 行出る');
    expect(
      find.widgetWithText(TextField, questionHint),
      findsOneWidget,
      reason: '下端の入力欄は「$questionHint」の案内を出す',
    );
    expect(sendButton(), findsOneWidget, reason: '「$sendLabel」ボタンが読み上げ名で見つかる');

    // キーが無ければ「本物 (Gemini)」を押しても切り替わらない。
    await tester.tap(realSupplyButton);
    await tester.pump();

    expect(asked, isEmpty, reason: 'キーが無ければ本物の供給は 1 度も作られない');

    // 選ばれているのは作り物のままなので、作り物が今までどおり流れる。
    await pumpUntil(
      tester,
      () => visibleOf(tester, thinkingText).isNotEmpty,
      budget: startBudget,
      reason: '作り物の思考の文が流れ始めない',
    );
    expect(
      fakeThinking.startsWith(visibleOf(tester, thinkingText)),
      isTrue,
      reason: '流れているのは作り物の思考の文',
    );

    handle.dispose();
  });

  testWidgets('AC-19 キーありで「本物 (Gemini)」を選んでまだ送っていない間は、待機の点を'
      '出さず返答の位置に案内の 1 行が出る', (tester) async {
    final handle = tester.ensureSemantics();
    final asked = <String>[];

    await pumpSwitchableReplyPage(
      tester,
      apiKey: apiKey,
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    expect(guidanceLine, findsNothing, reason: '作り物が選ばれている間は案内の 1 行は出ない');

    await tester.tap(realSupplyButton);
    await tester.pump();

    expect(guidanceLine, findsOneWidget, reason: '本物を選んだ未送信では案内の 1 行が出る');
    // 待機の点は example のテストから掴めないので、「思考の枠も返答の文字も
    // 無い」= 何も流れていない、で代える (spec の「待機の点の動きはテスト
    // しない」に沿う)。
    expectBeforeReceiving(reason: '未送信では何も流れない');

    // 供給を作らないまま待ち続けても、案内の 1 行のままで何も流れ始めない
    // (作り物が本物の名前で流れ出さない)。
    await pumpFrames(tester, startBudget);

    expect(guidanceLine, findsOneWidget, reason: '待っても案内の 1 行のまま');
    expectBeforeReceiving(reason: '待っても何も流れ始めない');
    expect(asked, isEmpty, reason: '送るまで本物の供給は作られない');

    handle.dispose();
  });

  testWidgets('AC-19 キーありで「本物 (Gemini)」を選んで質問を送ると、入力欄の質問が 1 回'
      '送られて入力欄が空になり、質問が返答の上に 1 行出て返答が 0 から流れる', (tester) async {
    final handle = tester.ensureSemantics();
    final asked = <String>[];
    final sources = <StreamController<Chunk>>[];

    /// 返答の上に出る、送った質問の 1 行。
    final questionLine = find.text(question);

    await pumpSwitchableReplyPage(
      tester,
      apiKey: apiKey,
      realReplyStream: (question) {
        asked.add(question);
        final source = StreamController<Chunk>();
        sources.add(source);
        return source.stream;
      },
    );

    expect(noKeyReason, findsNothing, reason: 'キーがあれば理由の 1 行は出ない');

    await tester.tap(realSupplyButton);
    await tester.pump();
    await sendQuestion(tester, question);

    expect(asked, [question], reason: '入力欄の質問で本物の供給が 1 回だけ作られる');
    expectBeforeReceiving(reason: '送った直後は受信前の姿 = 0 文字から');
    expect(
      find.widgetWithText(TextField, question),
      findsNothing,
      reason: '送ると入力欄は空になる',
    );
    expect(
      questionLine,
      findsOneWidget,
      reason: '送った質問は Text の 1 行として 1 つだけ出る (入力欄には残らない)',
    );
    expect(guidanceLine, findsNothing, reason: '送った後は未送信の案内の 1 行は出ない');

    sources.last.add(const Chunk(realThinking, kind: ChunkKind.thinking));
    sources.last.add(const Chunk(realReply, kind: ChunkKind.reply));
    unawaited(sources.last.close());

    await pumpUntil(
      tester,
      () => visibleOf(tester, replyText).length >= realReply.length,
      budget: flowBudget,
      reason: '本物の返答が出揃わない',
    );
    expect(
      find.byType(ThinkingFrame),
      findsOneWidget,
      reason: '思考の枠 → 返答の順に流れる',
    );
    expect(
      visibleOf(tester, thinkingText),
      realThinking,
      reason: '思考の枠に流れるのは本物の供給の思考の文',
    );
    expect(
      visibleOf(tester, replyText),
      realReply,
      reason: '返答は本物の供給の塊だけ (作り物の返答は混ざらない)',
    );
    expect(
      tester.getBottomLeft(questionLine).dy,
      lessThanOrEqualTo(tester.getTopLeft(replyText).dy),
      reason: '質問の 1 行は返答より上に出る',
    );

    // 「最初から流す」は本物では直前の質問をもう一度送る。
    await tester.tap(replayButton);
    await tester.pump();

    expect(asked, [question, question], reason: '「最初から流す」は直前の質問で本物の供給をもう一度作る');
    expectBeforeReceiving(reason: '流し直した直後は受信前の姿 = 0 文字から');
    expect(questionLine, findsOneWidget, reason: '流し直しても同じ質問の 1 行が出たまま');

    handle.dispose();
  });

  testWidgets('AC-19 本物の受信中は「送る」と「最初から流す」が無効で Stream は 1 本のまま、'
      '受信完了で再び送れる', (tester) async {
    final handle = tester.ensureSemantics();
    final asked = <String>[];
    final cancelled = <String>[];
    final sources = <String, StreamController<Chunk>>{};

    await pumpSwitchableReplyPage(
      tester,
      apiKey: apiKey,
      realReplyStream: (question) {
        asked.add(question);
        final source = StreamController<Chunk>(
          onCancel: () => cancelled.add(question),
        );
        sources[question] = source;
        return source.stream;
      },
    );

    await tester.tap(realSupplyButton);
    await tester.pump();
    await sendQuestion(tester, question);

    // 1 通目は受信中 (閉じない) のまま返答の文字を出しておく。
    sources[question]!.add(const Chunk(realReply, kind: ChunkKind.reply));
    await pumpUntil(
      tester,
      () => visibleOf(tester, replyText).length >= realReply.length,
      budget: flowBudget,
      reason: '1 通目の返答が出揃わない',
    );

    // 質問を入力してから見る — 入力欄が空だから無効なのではなく、受信中だから
    // 無効だと言えるようにする。
    await tester.enterText(questionField, secondQuestion);
    await tester.pump();

    expectDisabled(tester, sendButton(), '受信中は「$sendLabel」が無効と読み上げられる');
    expectDisabled(tester, replayButton, '受信中は「最初から流す」が無効と読み上げられる');

    // 受信中にもう一度送ろうとしても、押せない。
    await tapWhileDisabled(tester, sendButton());
    await tapWhileDisabled(tester, replayButton);

    expect(asked, [question], reason: '受信中は Stream は 1 本のまま (2 回目は作られない)');
    expect(cancelled, isEmpty, reason: '受信中の前の Stream の購読は解除されない');
    expect(
      visibleOf(tester, replyText),
      realReply,
      reason: '受信中に押しても流れは 0 に戻らず、届いた返答はそのまま',
    );

    // 受信完了 (Stream が閉じる) で、また送れるようになる。閉じた知らせは
    // microtask で届くので、時間を刻んで 1 フレーム描き直す (素の `pump()` では
    // 何も動いていない場面で描き直しが次の pump まで遅れる)。
    unawaited(sources[question]!.close());
    await tester.pump(frameInterval);

    expectEnabled(tester, sendButton(), '受信完了で「$sendLabel」は有効に戻る');
    expectEnabled(tester, replayButton, '受信完了で「最初から流す」は有効に戻る');

    await sendQuestion(tester, secondQuestion);

    expect(asked, [question, secondQuestion], reason: '受信完了の後は 2 通目を送れる');
    expectBeforeReceiving(reason: '送り直した直後は受信前の姿 = 0 文字から');

    sources[secondQuestion]!.add(
      const Chunk(secondReply, kind: ChunkKind.reply),
    );
    await pumpUntil(
      tester,
      () => visibleOf(tester, replyText).length >= secondReply.length,
      budget: flowBudget,
      reason: '2 通目の返答が出揃わない',
    );
    expect(
      visibleOf(tester, replyText),
      secondReply,
      reason: '画面に出るのは 2 通目の返答だけ (1 通目の返答は消える)',
    );

    handle.dispose();
  });

  testWidgets('AC-20 本物が通信の失敗で終わると、返答の下にエラーの 1 行が出て、'
      '届いた分の文字は残る', (tester) async {
    final handle = tester.ensureSemantics();

    Stream<Chunk> failingReplyStream(String question) async* {
      yield const Chunk(errorFirstChunk, kind: ChunkKind.reply);
      yield const Chunk(errorSecondChunk, kind: ChunkKind.reply);
      throw Exception(errorMessage);
    }

    await pumpSwitchableReplyPage(
      tester,
      apiKey: apiKey,
      realReplyStream: failingReplyStream,
    );

    await tester.tap(realSupplyButton);
    await tester.pump();
    await sendQuestion(tester, question);

    await pumpUntil(
      tester,
      () => visibleOf(tester, replyText).length >= errorReply.length,
      budget: flowBudget,
      reason: 'エラーの前に届いた 2 塊が出揃わない',
    );

    expect(
      visibleOf(tester, replyText),
      errorReply,
      reason: '届いた 2 塊の文字は消えずに残る',
    );
    final errorLine = find.textContaining(errorMessage);
    expect(errorLine, findsOneWidget, reason: 'エラーは 1 行だけ出る');
    expect(
      tester.getTopLeft(errorLine).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(replyText).dy),
      reason: 'エラーの 1 行は返答の下に出る',
    );

    handle.dispose();
  });
}
