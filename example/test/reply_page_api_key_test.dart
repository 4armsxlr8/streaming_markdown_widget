import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

import 'helpers/app.dart';
import 'helpers/reveal.dart';

/// キーのダイアログのテスト (AC-25)。
///
/// seam は利用例アプリの画面。主張するのは 6 つ — ダイアログにキーを入れて
/// 「Use key」を押すと以後の送信が Gemini に行き、入力欄は伏せ字でキーの文字列は
/// 画面のどのテキストにも出ないこと、「Clear」で空にすると以後の送信がサンプルの
/// 再生に戻ること、--dart-define のキーで起動してダイアログを開くと入力欄
/// にキーが入った状態 (伏せ字) で開くこと、キーを文言に含む例外で Gemini が
/// エラー終了してもエラーの 1 行ではキーの位置が `***` になること、空白だけを
/// 入れるとキー無し扱いになること、そして前後に空白の付いたキーは空白を落として
/// 使われること。
///
/// 伏せ字の見た目そのもの・ダイアログの質感は spec の「テストしないと決めた
/// もの」なので触らない — ここで固定するのは `obscureText` が立っていることと、
/// ダイアログを閉じた後にキーの文字列が画面のどのテキストにも出ないことだけ。
///
/// キーは端末に保存しない (State に持つだけ) ので、保存先を覗くテストは無い。
/// --dart-define の値は `app.dart` の `String.fromEnvironment` から
/// [ReplyPage.apiKey] に渡るので、ここでは `apiKey` を直接渡して代える。
///
/// 「Use key」「Clear」はどちらもダイアログを閉じる (閉じなければ「以後の送信」
/// に進めない) ものとして書いている — spec はそこまで書いていないので、
/// 押した後にダイアログが消えることも主張に含める。
///
/// 時間は供給の Timer と返答の Widget が回す Ticker 越しにしか進まないので、
/// [pumpFrames] / [pumpUntil] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle`
/// は使わない (待機の点と見出し行の光が回り続けるので終わらない)。
void main() {
  /// ダイアログに入れる「空白だけ」の文字列と、前後に空白の付いたキー
  /// (キーそのものは [apiKey])。
  const blankKey = '  \n';
  const paddedKey = '  $apiKey \n';

  /// キーの文字列を `toString()` に含む例外の文言と、画面に出るべきその姿。
  ///
  /// `dart:io` のヘッダ検査は問題のあったヘッダの値をそのまま
  /// `FormatException` の文言に載せ、Gemini のリクエストはキーをヘッダで送る
  /// ので、キーが例外の文言に混ざるのは実際に起きる形。
  const keyInFailure = 'Invalid HTTP header field value: "$apiKey"';
  const redactedFailure = 'Invalid HTTP header field value: "***"';

  testWidgets('AC-25 ダイアログにキーを入れて「$apiKeyUseLabel」を押すと、以後の送信は Gemini に行き、'
      'キーの文字列は画面のどのテキストにも出ない', (tester) async {
    final asked = <String>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: '',
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    await openApiKeyDialog(tester);

    expect(find.text(dialogTitle), findsOneWidget, reason: 'ダイアログのタイトル');
    expect(find.text(dialogNote), findsOneWidget, reason: 'メモリにだけ持つ注記が出る');
    expect(apiKeyDialogField, findsOneWidget, reason: 'キーの入力欄は 1 つ');
    expect(
      find.descendant(of: apiKeyDialog, matching: find.text(apiKeyLabel)),
      findsOneWidget,
      reason: 'キーの入力欄のラベルは「$apiKeyLabel」',
    );
    expect(
      tester.widget<TextField>(apiKeyDialogField).obscureText,
      isTrue,
      reason: 'キーの入力欄は伏せ字',
    );

    await tester.enterText(apiKeyDialogField, apiKey);
    await tester.pump();
    await tester.tap(find.text(apiKeyUseLabel));
    await pumpFrames(tester, dialogTransition);

    expect(
      find.text(dialogTitle),
      findsNothing,
      reason: '「$apiKeyUseLabel」でダイアログは閉じる',
    );

    await sendQuestion(tester, question);

    expect(asked, [question], reason: 'キーを入れた後の送信は Gemini に行く');
    expect(
      screenTexts(tester).where((text) => text.contains(apiKey)),
      isEmpty,
      reason: 'キーの文字列は画面のどのテキストにも出ない',
    );
  });

  testWidgets('AC-25 ダイアログで「$apiKeyClearLabel」を押すと、以後の送信はサンプルを再生する', (
    tester,
  ) async {
    final asked = <String>[];

    // --dart-define でキーを渡して起動した状態。
    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    await clearApiKey(tester);

    expect(
      find.text(dialogTitle),
      findsNothing,
      reason: '「$apiKeyClearLabel」でダイアログは閉じる',
    );

    await sendQuestion(tester, question);

    expect(asked, isEmpty, reason: 'キーを空にした後の送信は Gemini に行かない');

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText) == shortReply,
      budget: flowBudget,
      reason: 'キーを空にした後の送信でサンプルの返答が流れない',
    );
  });

  testWidgets('AC-25 キーを文言に含む例外で Gemini がエラー終了しても、エラーの 1 行ではキーの位置が '
      '「***」になり、キーの文字列は画面のどのテキストにも出ない', (tester) async {
    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
      realReplyStream: (question) =>
          Stream<Chunk>.error(const FormatException(keyInFailure)),
    );

    await sendQuestion(tester, question);

    await pumpUntil(
      tester,
      () => find.textContaining(errorLinePrefix).evaluate().isNotEmpty,
      budget: flowBudget,
      reason: 'エラーの 1 行が出ない',
    );

    expect(
      find.textContaining(errorLinePrefix),
      findsOneWidget,
      reason: '「Error: 」で始まる 1 行が 1 つだけ出る',
    );
    expect(
      find.textContaining(redactedFailure),
      findsOneWidget,
      reason: 'キーのあった位置は「***」になり、文言の残りはそのまま出る',
    );
    expect(
      screenTexts(tester).where((text) => text.contains(apiKey)),
      isEmpty,
      reason: 'キーの文字列は画面のどのテキストにも出ない',
    );
  });

  testWidgets('AC-25 ダイアログに空白だけを入れて「$apiKeyUseLabel」を押すと、キー無し扱いになり、'
      '以後の送信はサンプルを再生する', (tester) async {
    final asked = <String>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: '',
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    await useApiKey(tester, blankKey);
    await sendQuestion(tester, question);

    expect(asked, isEmpty, reason: '空白だけはキー無し扱い → Gemini は呼ばれない');

    await pumpUntil(
      tester,
      () => visibleText(tester, within: replyText) == shortReply,
      budget: flowBudget,
      reason: '空白だけを入れた後の送信でサンプルの返答が流れない',
    );
  });

  testWidgets('AC-25 ダイアログに前後の空白が付いたキーを入れて「$apiKeyUseLabel」を押すと、空白を落とした'
      'キーで以後の送信が Gemini に行く', (tester) async {
    final asked = <String>[];

    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: '',
      realReplyStream: (question) {
        asked.add(question);
        return const Stream<Chunk>.empty();
      },
    );

    await useApiKey(tester, paddedKey);
    await sendQuestion(tester, question);

    expect(asked, [question], reason: '前後に空白が付いていてもキーとして効く');

    // 持っているキーが空白を落としたものであることは、開き直したダイアログの
    // 入力欄の中身に出る (`find.text` は完全一致なので、空白が残っていれば
    // 見つからない)。
    await openApiKeyDialog(tester);

    expect(
      find.descendant(of: apiKeyDialog, matching: find.text(apiKey)),
      findsOneWidget,
      reason: '開き直した入力欄には前後の空白を落としたキーが入っている',
    );
  });

  testWidgets('AC-25 --dart-define のキーで起動してダイアログを開くと、入力欄にキーが入った状態 '
      '(伏せ字) で開く', (tester) async {
    await pumpReplyPage(
      tester,
      thinking: shortThinking,
      reply: shortReply,
      apiKey: apiKey,
    );

    await openApiKeyDialog(tester);

    expect(
      find.descendant(of: apiKeyDialog, matching: find.text(apiKey)),
      findsOneWidget,
      reason: '入力欄には --dart-define のキーが入っている',
    );
    expect(
      tester.widget<TextField>(apiKeyDialogField).obscureText,
      isTrue,
      reason: 'キーの入力欄は伏せ字',
    );
  });
}
