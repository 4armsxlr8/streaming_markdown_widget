import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/sample_reply.dart';

import 'helpers/app.dart';
import 'helpers/reveal.dart';

/// 送信と再生・エラーの 1 行のテスト (AC-19, AC-20)。
///
/// seam は利用例アプリの画面。主張するのは 8 つ — キー無しで起動するとサンプルの
/// 質問の吹き出しが出てサンプルの返答が自動で流れる、キー無しで質問を送ると
/// 入力欄が空になり質問の吹き出しが出てサンプルの返答が 0 から流れる
/// (Gemini は呼ばれない)、キーありで質問を送ると質問が 1 回 Gemini に送られて
/// 返答が 0 から流れる (再生は直前の質問をもう一度送る)、Gemini の受信中は送信と
/// 再生が無効で Stream は 1 本のまま (受信完了で再び送れる)、直前の返答の早送りの
/// 尻尾で送っても Stream は 2 本のままで受信中の無効が続く、キーを空にして送った
/// 質問もキーを入れ直した後の再生で Gemini に送られる、入力欄のキーボードの送信は
/// 送信ボタンと同じに働く、そして Gemini がエラーで終わると返答の下に
/// 「Error: 」で始まる 1 行が出て届いた分の文字は残る (エラーでも再び送れる)。
///
/// 「切り替え・理由の 1 行・案内の 1 行は無い」(AC-19 の 1 つ目のケース) は、
/// 旧画面のその 3 つがすべて日本語の文字列だったので `reply_page_test.dart` の
/// AC-26「画面に日本語の文字列は無い」が押さえている — ここで旧文言を探し直す
/// ことはしない (用語集の「使わない語」を持ち込まないため)。
///
/// 本物の Gemini は呼ばない (spec の「テストしないと決めたもの」)。Gemini への
/// 送信は [ReplyPage.realReplyStream] の差し替え口に作り物の [Stream] を渡して
/// 代える。画面が組み立てる URL やヘッダは変換のテスト
/// (`gemini_reply_source_test.dart`) の持ち分なので、ここでは触らない。
///
/// 起動するとキーの有無に関わらずサンプルが流れ始めるので、送信のテストは
/// pump したあとに入力欄へ打って送る。サンプルの届き方は [Random] の seed で
/// 固定する (`reply_page_supply_test.dart` と同じ作法)。
///
/// 時間は供給の Timer と返答の Widget が回す Ticker 越しにしか進まないので、
/// [pumpFrames] / [pumpUntil] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle`
/// は使わない (待機の点と見出し行の光が回り続けるので終わらない)。
void main() {
  /// 供給の乱数に渡す seed (サンプルの届き方を固定するためだけのもの)。
  const supplySeed = 1;

  /// 入力欄に打つ 2 通目の質問 (1 通目は [question])。
  const secondQuestion = 'How do I render a table?';

  /// Gemini (差し替えた Stream) が流す思考と返答。
  const geminiThinking = '本物の思考。';
  const geminiReply = '本物の返答。';

  /// 2 通目の Gemini の返答。
  const secondReply = '2 通目の返答。';

  /// 早送りの尻尾で送るケースで流す 1 塊。
  ///
  /// 早送りは最速でも 1 フレームに 1 文字なので、60 文字なら受信完了の後も
  /// 60 フレームほど出現が続く — その途中で送れる。
  final fastForwardChunk = 'word ' * 12;

  /// AC-20 で届く返答の 2 塊と、エラーの文言。
  const errorFirstChunk = '届いた 1 塊目。';
  const errorSecondChunk = '届いた 2 塊目。';
  const errorReply = '$errorFirstChunk$errorSecondChunk';
  const errorMessage = 'connection failed';

  /// サンプルが流れ始めたことを見るまでに進める時間
  /// (1 塊の間隔の上限 250ms に余裕を足した値)。
  const startBudget = Duration(seconds: 2);

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

  testWidgets('AC-19 キー無しで起動すると、サンプルの質問の吹き出しが出てサンプルの返答が自動で流れる', (tester) async {
    // --dart-define を渡していないテストの起動はキー無し (app.dart の
    // String.fromEnvironment が空) なので、アプリをそのまま pump する。
    await pumpApp(tester);

    expect(
      find.text(sampleQuestion),
      findsOneWidget,
      reason: '起動時の質問の吹き出しはサンプルの質問',
    );
    expect(
      find.text(questionHint),
      findsOneWidget,
      reason: '入力欄は空でプレースホルダが出ている',
    );

    await pumpUntil(
      tester,
      () => visibleText(tester, within: thinkingText).isNotEmpty,
      budget: startBudget,
      reason: 'サンプルの思考が流れ始めない',
    );
    expect(
      sampleThinking.startsWith(visibleText(tester, within: thinkingText)),
      isTrue,
      reason: '流れているのはサンプルの思考',
    );
  });

  testWidgets('AC-19 キー無しで質問を送ると、入力欄が空になり質問の吹き出しが出て、'
      'サンプルの返答が 0 から流れる (Gemini は呼ばれない)', (tester) async {
    final asked = <String>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: '',
      random: Random(supplySeed),
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    // 起動のサンプルを少し流してから送る (0 から流れ直すことを見るため)。
    await pumpUntil(
      tester,
      () => visibleText(tester, within: thinkingText).isNotEmpty,
      budget: startBudget,
      reason: '前提: 起動のサンプルが流れ始めない',
    );

    await sendQuestion(tester, question);

    expect(asked, isEmpty, reason: 'キーが空なら Gemini は呼ばれない');
    expectBeforeReceiving(reason: '送った直後は受信前の姿 = 0 文字から');
    expect(
      find.text(question),
      findsOneWidget,
      reason: '送った質問の吹き出しが 1 つだけ出る (入力欄には残らない)',
    );
    expect(
      find.descendant(of: questionField, matching: find.text(question)),
      findsNothing,
      reason: '送ると入力欄は空になる',
    );
    expect(
      find.text(sampleQuestion),
      findsNothing,
      reason: '質問の吹き出しは送った質問に置き換わる (履歴は持たない)',
    );

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText) == shortReply,
      budget: flowBudget,
      reason: 'サンプルの返答が 0 から流れ直さない',
    );
    expect(
      visibleText(tester, within: thinkingText),
      shortThinking,
      reason: '流れるのはサンプルの思考',
    );
  });

  testWidgets('AC-19 キーありで質問を送ると、質問が 1 回 Gemini に送られて入力欄が空になり、'
      '質問の吹き出しが出て返答が 0 から流れる', (tester) async {
    final asked = <String>[];
    final sources = <StreamController<Chunk>>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      random: Random(supplySeed),
      realReplyStream: (question) {
        asked.add(question);
        final source = StreamController<Chunk>();
        sources.add(source);
        return source.stream;
      },
    );

    await sendQuestion(tester, question);

    expect(asked, [question], reason: '入力欄の質問で Gemini の Stream が 1 回だけ作られる');
    expectBeforeReceiving(reason: '送った直後は受信前の姿 = 0 文字から');
    expect(
      find.text(question),
      findsOneWidget,
      reason: '送った質問の吹き出しが 1 つだけ出る (入力欄には残らない)',
    );
    expect(
      find.descendant(of: questionField, matching: find.text(question)),
      findsNothing,
      reason: '送ると入力欄は空になる',
    );

    sources.last.add(const Chunk(geminiThinking, kind: ChunkKind.thinking));
    sources.last.add(const Chunk(geminiReply, kind: ChunkKind.reply));
    unawaited(sources.last.close());

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText).length >= geminiReply.length,
      budget: flowBudget,
      reason: 'Gemini の返答が出揃わない',
    );
    expect(
      find.byType(ThinkingFrame),
      findsOneWidget,
      reason: '思考の枠 → 返答の順に流れる',
    );
    expect(
      visibleText(tester, within: thinkingText),
      geminiThinking,
      reason: '思考の枠に流れるのは Gemini の思考',
    );
    expect(
      visibleText(tester, within: replyText),
      geminiReply,
      reason: '返答は Gemini の塊だけ (サンプルの返答は混ざらない)',
    );
    expect(
      tester.getBottomLeft(find.text(question)).dy,
      lessThanOrEqualTo(tester.getTopLeft(replyText).dy),
      reason: '質問の吹き出しは返答より上に出る',
    );

    // 再生はキーがあれば直前の質問をもう一度送る (spec: 再生は Gemini なら
    // 直前の質問をもう一度送り、サンプルなら流し直す)。
    await tester.tap(replayButton);
    await tester.pump();

    expect(asked, [question, question], reason: '再生は直前の質問で Stream をもう一度作る');
    expectBeforeReceiving(reason: '再生した直後は受信前の姿 = 0 文字から');
    expect(find.text(question), findsOneWidget, reason: '再生しても同じ質問の吹き出しが出たまま');
  });

  testWidgets('AC-19 Gemini の受信中は送信と再生が無効で Stream は 1 本のまま、受信完了で再び送れる', (
    tester,
  ) async {
    // 読み上げの状態を見るので読み上げの木を立てる (解放の作法は
    // helpers/app.dart の「読み上げ (Semantics) を見るテストの作法」)。
    final handle = tester.ensureSemantics();
    final asked = <String>[];
    final cancelled = <String>[];
    final sources = <String, StreamController<Chunk>>{};

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      random: Random(supplySeed),
      realReplyStream: (question) {
        asked.add(question);
        final source = StreamController<Chunk>(
          onCancel: () => cancelled.add(question),
        );
        sources[question] = source;
        return source.stream;
      },
    );

    await sendQuestion(tester, question);

    // 1 通目は受信中 (閉じない) のまま返答の文字を出しておく。
    sources[question]!.add(const Chunk(geminiReply, kind: ChunkKind.reply));
    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText).length >= geminiReply.length,
      budget: flowBudget,
      reason: '1 通目の返答が出揃わない',
    );

    // 質問を入力してから見る — 入力欄が空だから無効なのではなく、受信中だから
    // 無効だと言えるようにする。
    await tester.enterText(questionField, secondQuestion);
    await tester.pump();

    expectDisabled(tester, sendButton, '受信中は「$sendLabel」が無効と読み上げられる');
    expectDisabled(tester, replayButton, '受信中は「$replayLabel」が無効と読み上げられる');

    // 受信中にもう一度送ろうとしても、押せない。
    await tapWhileDisabled(tester, sendButton);
    await tapWhileDisabled(tester, replayButton);

    expect(asked, [question], reason: '受信中は Stream は 1 本のまま (2 回目は作られない)');
    expect(cancelled, isEmpty, reason: '受信中の前の Stream の購読は解除されない');
    expect(
      visibleText(tester, within: replyText),
      geminiReply,
      reason: '受信中に押しても流れは 0 に戻らず、届いた返答はそのまま',
    );

    // 受信完了 (Stream が閉じる) で、また送れるようになる。閉じた知らせは
    // microtask で届くので、時間を刻んで 1 フレーム描き直す (素の `pump()` では
    // 何も動いていない場面で描き直しが次の pump まで遅れる)。
    unawaited(sources[question]!.close());
    await tester.pump(frameInterval);

    expectEnabled(tester, sendButton, '受信完了で「$sendLabel」は有効に戻る');
    expectEnabled(tester, replayButton, '受信完了で「$replayLabel」は有効に戻る');

    await sendQuestion(tester, secondQuestion);

    expect(asked, [question, secondQuestion], reason: '受信完了の後は 2 通目を送れる');
    expectBeforeReceiving(reason: '送り直した直後は受信前の姿 = 0 文字から');

    sources[secondQuestion]!.add(
      const Chunk(secondReply, kind: ChunkKind.reply),
    );
    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText).length >= secondReply.length,
      budget: flowBudget,
      reason: '2 通目の返答が出揃わない',
    );
    expect(
      visibleText(tester, within: replyText),
      secondReply,
      reason: '画面に出るのは 2 通目の返答だけ (1 通目の返答は消える)',
    );

    handle.dispose();
  });

  testWidgets('AC-19 直前の返答の早送りの尻尾でもう一度送れて、Stream は 2 本のまま受信中の無効が続く', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final asked = <String>[];
    final sources = <String, StreamController<Chunk>>{};

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      random: Random(supplySeed),
      realReplyStream: (question) {
        asked.add(question);
        final source = StreamController<Chunk>();
        sources[question] = source;
        return source.stream;
      },
    );

    await sendQuestion(tester, question);

    // 1 通目は 60 文字の塊 1 つを流して閉じる (受信完了)。出現は最速でも
    // 1 フレームに 1 文字なので、ここから 60 フレームほど早送りが続く。
    sources[question]!.add(Chunk(fastForwardChunk, kind: ChunkKind.reply));
    unawaited(sources[question]!.close());
    await pumpFrames(tester, frameInterval * 5);

    expect(
      visibleText(tester, within: replyText).length,
      allOf(greaterThan(0), lessThan(fastForwardChunk.length)),
      reason: '前提: 受信完了したがまだ早送りの途中 (出現し切っていない)',
    );
    expectEnabled(tester, sendButton, '前提: 受信完了しているので早送り中でも送れる');

    await sendQuestion(tester, secondQuestion);
    await pumpFrames(tester, frameInterval * 2);

    expect(asked, [
      question,
      secondQuestion,
    ], reason: '早送りの尻尾で送っても Stream は 2 本 (前の分が作り直されない)');
    expectBeforeReceiving(reason: '早送りの尻尾で送った直後も受信前の姿 = 0 文字から');
    expectDisabled(tester, sendButton, '2 通目の受信中は「$sendLabel」が無効');
    expectDisabled(tester, replayButton, '2 通目の受信中は「$replayLabel」が無効');

    // 1 通目の早送りが残っていた分 (1 フレーム 1 文字なので 60 文字ぶん) を
    // 通り過ぎるまで進める。捨てた前の世代の Controller が「終わった」と報告
    // し直すと、ここで受信中が解けて無効が外れてしまう。
    await pumpFrames(tester, frameInterval * (fastForwardChunk.length + 10));

    expect(asked, [
      question,
      secondQuestion,
    ], reason: '2 通目の受信完了までに 3 本目は作られない');
    expectDisabled(tester, sendButton, '1 通目の早送りが流れ切っても「$sendLabel」は無効のまま');
    expectDisabled(tester, replayButton, '1 通目の早送りが流れ切っても「$replayLabel」は無効のまま');

    // 2 通目の受信完了まで見て、そこまでに 3 本目が作られないことを閉じる。
    unawaited(sources[secondQuestion]!.close());
    await tester.pump(frameInterval);

    expect(asked, [
      question,
      secondQuestion,
    ], reason: '2 通目の受信完了までに 3 本目は作られない');

    handle.dispose();
  });

  testWidgets('AC-19 キーを空にして送った質問は、キーを入れ直した後の再生で Gemini に送られる', (tester) async {
    final asked = <String>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      random: Random(supplySeed),
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    await sendQuestion(tester, question);
    expect(asked, [question], reason: '前提: キーありの 1 通目は Gemini に行く');

    // 空の Stream の受信完了は microtask で届くので、1 フレーム進めて受信中を
    // 解く (受信中のままでは次の送信が無効で、前提が崩れる)。
    await tester.pump(frameInterval);

    await clearApiKey(tester);
    await sendQuestion(tester, secondQuestion);

    expect(asked, [question], reason: 'キーを空にした後の送信は Gemini に行かない');
    expect(
      find.text(secondQuestion),
      findsOneWidget,
      reason: '質問の吹き出しは 2 通目の質問になる (サンプルを再生しても)',
    );

    await useApiKey(tester, apiKey);
    await tester.tap(replayButton);
    await tester.pump();

    expect(asked, [
      question,
      secondQuestion,
    ], reason: '再生が Gemini に送るのは直前の質問 (1 通目ではない)');
    expect(
      find.text(secondQuestion),
      findsOneWidget,
      reason: '再生しても 2 通目の質問の吹き出しが出たまま',
    );
  });

  testWidgets('AC-19 入力欄でキーボードの送信を受けると、送信ボタンを押したのと同じに質問が送られる', (tester) async {
    final asked = <String>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      random: Random(supplySeed),
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    expect(
      tester.widget<TextField>(questionField).textInputAction,
      TextInputAction.send,
      reason: '入力欄のキーボードは送信のキーを出す (これが無いとキーボードの送信は届かない)',
    );

    await tester.enterText(questionField, question);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(asked, [question], reason: 'キーボードの送信でも質問は 1 回 Gemini に送られる');
    expect(
      find.text(question),
      findsOneWidget,
      reason: '送った質問の吹き出しが 1 つだけ出る (入力欄には残らない)',
    );
    expect(
      find.descendant(of: questionField, matching: find.text(question)),
      findsNothing,
      reason: '送ると入力欄は空になる',
    );
    expect(
      find.text(questionHint),
      findsOneWidget,
      reason: '入力欄が空になったのでプレースホルダが出ている',
    );
  });

  testWidgets('AC-20 Gemini が通信の失敗で終わると、返答の下に「Error: 」で始まる 1 行が出て、'
      '届いた分の文字は残る', (tester) async {
    final handle = tester.ensureSemantics();

    Stream<Chunk> failingReplyStream(String question) async* {
      yield const Chunk(errorFirstChunk, kind: ChunkKind.reply);
      yield const Chunk(errorSecondChunk, kind: ChunkKind.reply);
      throw Exception(errorMessage);
    }

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      random: Random(supplySeed),
      realReplyStream: failingReplyStream,
    );

    await sendQuestion(tester, question);

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText).length >= errorReply.length,
      budget: flowBudget,
      reason: 'エラーの前に届いた 2 塊が出揃わない',
    );

    expect(
      visibleText(tester, within: replyText),
      errorReply,
      reason: '届いた 2 塊の文字は消えずに残る',
    );
    final errorLine = find.textContaining(errorLinePrefix);
    expect(errorLine, findsOneWidget, reason: '「Error: 」で始まる 1 行が 1 つだけ出る');
    expect(
      find.textContaining(errorMessage),
      findsOneWidget,
      reason: 'エラーの 1 行に失敗の内容が出る',
    );
    expect(
      tester.getTopLeft(errorLine).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(replyText).dy),
      reason: 'エラーの 1 行は返答の下に出る',
    );

    // AC-19 の「受信完了かエラーで再び送れる」のエラー側。
    await tester.enterText(questionField, secondQuestion);
    await tester.pump();

    expectEnabled(tester, sendButton, 'エラーの後は「$sendLabel」が有効に戻る');
    expectEnabled(tester, replayButton, 'エラーの後は「$replayLabel」が有効に戻る');

    handle.dispose();
  });
}
