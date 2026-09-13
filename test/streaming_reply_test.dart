import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_widget/src/keys.dart';
import 'package:streaming_markdown_widget/src/reply_theme.dart';
import 'package:streaming_markdown_widget/src/streaming_reply.dart';
import 'package:streaming_markdown_widget/src/streaming_reply_controller.dart';

import 'helpers/reveal.dart';

/// 思考の文を塊に割り、未出現の残りが尽きる前に次を届ける送り手。
///
/// 思考の枠が畳まれるのは思考の未出現の残りが尽きた瞬間なので、タップや 2 行目を
/// 試している間は塊を届け続けて思考を流したままにする必要がある。1 塊
/// [chunkSize] 文字で、残りが [lowWaterMark] 文字を下回ったら次を届ける
/// (残りは常に遅れの上限 24 文字以下なので追いつきには入らない)。
class _ThinkingFeed {
  _ThinkingFeed(this._controller, String text, {int chunkSize = 12})
    : _chunks = [
        for (var start = 0; start < text.characters.length; start += chunkSize)
          text.characters.skip(start).take(chunkSize).toString(),
      ];

  final StreamingReplyController _controller;
  final List<String> _chunks;
  int _sent = 0;

  /// まだ届けていない塊があるか。
  bool get hasMore => _sent < _chunks.length;

  /// 次の塊を 1 つ届ける。
  void sendNext() {
    _controller.addChunk(Chunk(_chunks[_sent++], kind: ChunkKind.thinking));
  }

  /// 未出現の残りが [lowWaterMark] 文字を下回っていれば次の塊を届ける。
  void topUp({int lowWaterMark = 8}) {
    if (hasMore && _controller.thinking.pendingCount < lowWaterMark) sendNext();
  }
}

/// 思考の枠と返答の Widget の合成 ([StreamingReply]) のテスト
/// (AC-15, AC-16, AC-17, AC-18, AC-19, AC-21)。
///
/// 主張するのは状態遷移とタップ — 思考の枠が出る・消える条件、本文の高さ
/// (1 行 / 全部 / 0)、見出し行の文言、返答の吹き出しと待機の点の居る・
/// 居ない、そして返答が流れ始める順番。見出し行の光の流れ方・色・余白・待機の
/// 点の見た目は spec の「テストしないと決めたもの」なので触らない。
///
/// 時間は [RevealTicker] が回す Ticker 越しにしか進まないので `controller.tick`
/// は呼ばず、[pumpFrames] で 1 フレーム (16ms) ずつ進める。`pumpAndSettle` は
/// 使わない (見出し行の光が 1.6 秒周期で回り続けるので終わらない)。
void main() {
  /// 基準の速さ 40 文字/秒 の 1 文字あたりの間隔。
  const revealInterval = Duration(milliseconds: 25);

  /// 1 文字の不透明度が 0 から 1 になるまでの時間。
  const fadeDuration = Duration(milliseconds: 300);

  /// 受信完了の時点の残りを出し切るまでの猶予 (早送り)。
  const fastForwardBudget = Duration(milliseconds: 400);

  /// 本文の高さが変わるのにかかる時間 (AnimatedSize の 300ms)。畳みも同じ。
  const collapseDuration = Duration(milliseconds: 300);

  /// 返答の Widget を置く幅。思考の文が必ず 2 行以上に折り返る狭さにする。
  const replyWidth = 360.0;

  /// 思考の文 1 行の高さ (12.5 × 1.7 = 21.25)。
  const oneLineHeight = ReplyTheme.thinkingFontSize * ReplyTheme.thinkingHeight;

  /// 高さの比較に許す誤差。
  const heightTolerance = 1.0;

  /// 思考の最初の塊から返答の最初の塊 (AC-21 では受信完了) までに進めるフレーム数。
  /// 16ms × 125 = ちょうど 2 秒。
  const framesToReply = 125;

  /// [framesToReply] フレーム分の時間。
  final elapsedToReply = frameInterval * framesToReply;

  /// 「n 秒考えました」の n。[elapsedToReply] (2 秒) を四捨五入した秒数。
  const thinkingSeconds = 2;

  /// 思考が流れている間の見出し行の文言 (三点リーダは U+2026)。
  const thinkingTitle = '考え中…';

  /// 思考の文 (段落 2 つ、記法なし。93 文字)。
  const thinkingText =
      'ユーザーは ListView のカクつきを直したい。原因として多いのは、行の高さが'
      'ばらばらで毎フレーム計測が走ること。\n\n'
      'まず builder への置き換えと高さの固定を手順として示す。';

  /// 返答の文 (記法なし。18 文字なので遅れの上限 24 文字を超えず基準の速さで流れる)。
  const replyText = '行の高さを固定すると計測が減ります。';

  /// 早送り (400ms) と畳み (300ms) が終わるまでに許すフレーム数の上限。
  /// 700ms = 44 フレームなので、余裕を見て 60 で打ち切る。
  const maxFramesToCollapse = 60;

  /// 畳み終わってから返答が流れ始めるまでに許すフレーム数の上限。
  const maxFramesToReply = 40;

  /// 思考の文が 2 行目に入るまでに許すフレーム数の上限。
  /// 幅 360 なら 1 行は 26 文字ほど = 650ms ≒ 41 フレーム。
  const maxFramesToSecondLine = 120;

  /// 本文の箱の高さが目標へ追いつくまでに許すフレーム数の上限
  /// (AnimatedSize の 300ms = 19 フレーム。行が増えて追いかけ直す分の余裕を見る)。
  const maxFramesToHeight = 60;

  /// 返答の Widget を [replyWidth] の幅で置く。
  Future<void> pumpStreamingReply(
    WidgetTester tester,
    StreamingReplyController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: replyWidth,
              child: SingleChildScrollView(
                child: StreamingReply(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 思考の塊を届けながら [total] の時間を [frameInterval] 刻みで進める。
  Future<void> pumpFeeding(
    WidgetTester tester,
    _ThinkingFeed feed,
    Duration total,
  ) async {
    for (var elapsed = Duration.zero; elapsed < total; elapsed += frameInterval) {
      feed.topUp();
      await tester.pump(frameInterval);
    }
  }

  /// [condition] が満たされるまで 1 フレームずつ進める。
  /// [feeding] を渡すと、進めながら思考の塊を届け続ける。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    required int maxFrames,
    required String reason,
    _ThinkingFeed? feeding,
  }) async {
    for (var frame = 0; frame < maxFrames; frame++) {
      feeding?.topUp();
      await tester.pump(frameInterval);
      if (condition()) return;
    }
    fail('$maxFrames フレーム進めても条件が満たされなかった: $reason');
  }

  /// [key] の Text の文字 (光を流すために [Text.rich] で組んでいてもよい)。
  String textOf(WidgetTester tester, Key key) {
    expect(find.byKey(key), findsOneWidget, reason: '$key の Text が tree に居る');
    final text = tester.widget<Text>(find.byKey(key));
    return text.data ?? text.textSpan?.toPlainText() ?? '';
  }

  /// 見出し行の文言。
  String headTitle(WidgetTester tester) =>
      textOf(tester, Keys.thinkingFrameTitle);

  /// 開閉を示す矢印 (▸/▾) がどこにも描かれていないこと。
  ///
  /// 矢印は spec の改訂 (2026-09-12) で見出し行から無くしたので、Key ではなく
  /// 字そのものの不在で主張する (Key が消えてもこのテストは主張を保つ)。
  void expectNoArrow(WidgetTester tester) {
    expect(
      find.text('▸'),
      findsNothing,
      reason: '見出し行に開閉を示す矢印 (▸) は置かない',
    );
    expect(
      find.text('▾'),
      findsNothing,
      reason: '見出し行に開閉を示す矢印 (▾) は置かない',
    );
  }

  /// 本文の箱の高さ (1 行 / 全部 / 0)。
  double bodyHeight(WidgetTester tester) {
    expect(
      find.byKey(Keys.thinkingFrameBody),
      findsOneWidget,
      reason: '本文の箱は畳んでも tree に居る (高さが 0 になる)',
    );
    return tester.getRect(find.byKey(Keys.thinkingFrameBody)).height;
  }

  /// 思考の文そのものの高さ (箱に切り詰められる前の、行数ぶんの高さ)。
  double thinkingTextHeight(WidgetTester tester) {
    expect(find.byKey(Keys.thinkingText), findsOneWidget);
    return tester.getRect(find.byKey(Keys.thinkingText)).height;
  }

  /// [key] に描かれている可視文字の数 (出現を始めた文字数)。
  int revealedCharCount(WidgetTester tester, Key key) =>
      visibleText(tester, within: find.byKey(key)).characters.length;

  /// 本文の箱の下端と、思考の文の下端がそろっているか (最新の行が見える)。
  void expectLatestLineVisible(WidgetTester tester) {
    expect(
      tester.getRect(find.byKey(Keys.thinkingText)).bottom,
      closeTo(tester.getRect(find.byKey(Keys.thinkingFrameBody)).bottom, heightTolerance),
      reason: '思考の文の末尾が箱の下端にそろう = 最新の行が見える',
    );
  }

  testWidgets(
    'AC-15 思考の塊が届き始めると、思考の枠に「考え中…」の見出し行が出て思考の文が 1 文字ずつ出現し、返答の吹き出しと待機の点は居なくなる',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);

      expect(
        find.byKey(Keys.replyBubble),
        findsOneWidget,
        reason: '前提: 受信前は返答の吹き出しが居る',
      );
      expect(
        find.byKey(Keys.waitingDots),
        findsOneWidget,
        reason: '前提: 受信前は吹き出しの中に待機の点が居る',
      );
      expect(
        find.byKey(Keys.thinkingFrame),
        findsNothing,
        reason: '前提: 受信前は思考の枠が居ない',
      );

      final feed = _ThinkingFeed(controller, thinkingText);
      feed.sendNext();
      await tester.pump();

      expect(find.byKey(Keys.thinkingFrame), findsOneWidget, reason: '思考の枠が出る');
      expect(
        headTitle(tester),
        thinkingTitle,
        reason: '思考が流れている間の見出し行は「考え中…」',
      );

      await pumpFrames(tester, revealInterval * 2);
      final startedChars = revealedCharCount(tester, Keys.thinkingText);
      expect(startedChars, greaterThan(0), reason: '思考の文が出現を始めている');

      await pumpFrames(tester, revealInterval * 4);
      expect(
        revealedCharCount(tester, Keys.thinkingText),
        greaterThan(startedChars),
        reason: 'フレームを進めると思考の可視文字列が増える (1 文字ずつ出現する)',
      );
      expect(
        thinkingText.startsWith(visibleText(tester, within: find.byKey(Keys.thinkingText))),
        isTrue,
        reason: '見えているのは思考の文の先頭からの続き',
      );

      expect(
        find.byKey(Keys.replyBubble),
        findsNothing,
        reason: '思考の塊が届き始めたら返答の吹き出しは居なくなる',
      );
      expect(
        find.byKey(Keys.waitingDots),
        findsNothing,
        reason: '受信前にあった待機の点も居なくなる',
      );
    },
  );

  testWidgets(
    'AC-16 思考が 2 行目に入っても本文は 1 行の高さで最新の行を見せ、見出し行のタップで全部の高さ ⇄ 1 行の高さに変わり、思考の出現は止まらない',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);
      final feed = _ThinkingFeed(controller, thinkingText);

      // 思考の文が 2 行以上になるまで、塊を届けながら進める。
      await pumpUntil(
        tester,
        () => thinkingTextHeight(tester) > oneLineHeight * 1.5,
        maxFrames: maxFramesToSecondLine,
        reason: '思考の文が 2 行目に入らない',
        feeding: feed,
      );
      expect(
        controller.isThinking,
        isTrue,
        reason: 'テストの前提: 思考が流れ続けている (塊を届け続けているので畳まれない)',
      );

      // 2 行目に入っても本文は 1 行の高さのまま、最新の行が見える。
      expect(
        bodyHeight(tester),
        closeTo(oneLineHeight, heightTolerance),
        reason: '本文は 1 行の高さに切り詰められる',
      );
      expect(
        thinkingTextHeight(tester),
        greaterThan(oneLineHeight + heightTolerance),
        reason: '前提: 思考の文は 2 行以上ある (箱より高い)',
      );
      expectLatestLineVisible(tester);

      // 1 度目のタップ: 本文が全部の高さになる。
      final beforeFirstTap = revealedCharCount(tester, Keys.thinkingText);
      await tester.tap(find.byKey(Keys.thinkingFrameHead));
      await pumpUntil(
        tester,
        () => (bodyHeight(tester) - thinkingTextHeight(tester)).abs() <= heightTolerance,
        maxFrames: maxFramesToHeight,
        reason: '本文の箱が思考の文と同じ高さ (全部) にならない',
        feeding: feed,
      );
      expect(
        bodyHeight(tester),
        greaterThan(oneLineHeight + heightTolerance),
        reason: '全部の高さは 1 行より高い',
      );
      final afterFirstTap = revealedCharCount(tester, Keys.thinkingText);
      expect(
        afterFirstTap,
        greaterThan(beforeFirstTap),
        reason: 'タップしても思考の出現は止まらない',
      );

      // 2 度目のタップ: 1 行の高さに戻る。
      await tester.tap(find.byKey(Keys.thinkingFrameHead));
      await pumpFeeding(tester, feed, collapseDuration + frameInterval * 2);
      expect(
        bodyHeight(tester),
        closeTo(oneLineHeight, heightTolerance),
        reason: 'もう一度タップすると 1 行の高さに戻る',
      );
      expectLatestLineVisible(tester);
      expect(
        revealedCharCount(tester, Keys.thinkingText),
        greaterThan(afterFirstTap),
        reason: '2 度目のタップの前後でも思考の出現は止まらない',
      );
    },
  );

  testWidgets(
    'AC-17 思考の受信が終わって返答の最初の塊が届くと、見出し行が「2 秒考えました」になって本文が畳まれ、返答が流れ始める',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);
      final feed = _ThinkingFeed(controller, thinkingText);

      // 思考の最初の塊から 125 フレーム (2 秒) 進めてから返答の最初の塊を届ける
      // ので、n = 2。
      await pumpFeeding(tester, feed, elapsedToReply);
      while (feed.hasMore) {
        feed.sendNext();
      }
      expect(
        controller.thinking.pendingCount,
        greaterThan(0),
        reason: 'テストの前提: 返答が届く時点で思考にまだ未出現の残りがある '
            '(93 文字を 12 文字ずつ届けているので 2 秒時点では出し切っていない)。'
            'ここが崩れていたらテストの組み立ての問題',
      );
      expect(headTitle(tester), thinkingTitle, reason: '前提: まだ「考え中…」');

      controller.addChunk(const Chunk(replyText));
      await tester.pump();

      // 思考の残りを早送り (400ms 以内) してから畳む (300ms)。
      await pumpUntil(
        tester,
        () => bodyHeight(tester) <= heightTolerance,
        maxFrames: maxFramesToCollapse,
        reason: '思考の本文が畳まれない (高さ 0 にならない)',
      );

      expect(
        headTitle(tester),
        '$thinkingSeconds 秒考えました',
        reason: 'n は思考の最初の塊から返答の最初の塊までの秒数 (2 秒)',
      );
      expect(
        find.byKey(Keys.replyBubble),
        findsOneWidget,
        reason: '返答の吹き出しが現れる',
      );

      await pumpUntil(
        tester,
        () => revealedCharCount(tester, Keys.replyText) > 0,
        maxFrames: maxFramesToReply,
        reason: '畳んだあとに返答が流れ始めない',
      );
      final replyChars = revealedCharCount(tester, Keys.replyText);
      await pumpFrames(tester, revealInterval * 4);
      expect(
        revealedCharCount(tester, Keys.replyText),
        greaterThan(replyChars),
        reason: '返答の可視文字列が増える',
      );
      expect(
        replyText.startsWith(visibleText(tester, within: find.byKey(Keys.replyText))),
        isTrue,
        reason: '見えているのは返答の先頭からの続き',
      );
    },
  );

  testWidgets(
    'AC-18 受信中に畳まれた見出し行をタップすると思考の本文が全部開き、もう一度タップすると畳まれる (見出し行に矢印は無い)',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);
      final feed = _ThinkingFeed(controller, thinkingText);

      // 思考を少し流したところへ返答の最初の塊を届けて、畳まれた状態にする。
      await pumpFeeding(tester, feed, const Duration(milliseconds: 500));
      controller.addChunk(const Chunk(replyText));
      await tester.pump();
      await pumpUntil(
        tester,
        () => bodyHeight(tester) <= heightTolerance,
        maxFrames: maxFramesToCollapse,
        reason: '前提: 思考の本文が畳まれない',
      );
      expect(controller.isComplete, isFalse, reason: '前提: まだ受信中');

      await tester.tap(find.byKey(Keys.thinkingFrameHead));
      await pumpFrames(tester, collapseDuration + frameInterval * 2);

      final textHeight = thinkingTextHeight(tester);
      expect(
        textHeight,
        greaterThan(heightTolerance),
        reason: '前提: 届いた思考の文に高さがある',
      );
      expect(
        bodyHeight(tester),
        closeTo(textHeight, heightTolerance),
        reason: '畳まれた本文をタップすると全部開く',
      );
      expectNoArrow(tester);

      await tester.tap(find.byKey(Keys.thinkingFrameHead));
      await pumpFrames(tester, collapseDuration + frameInterval * 2);

      expect(
        bodyHeight(tester),
        closeTo(0, heightTolerance),
        reason: 'もう一度タップすると畳まれる',
      );
    },
  );

  testWidgets(
    'AC-18 受信完了後に畳まれた見出し行をタップすると思考の本文が全部開き、もう一度タップすると畳まれる (見出し行に矢印は無い)',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);
      final feed = _ThinkingFeed(controller, thinkingText);

      await pumpFeeding(tester, feed, const Duration(milliseconds: 500));
      controller.addChunk(const Chunk(replyText));
      controller.complete();
      await tester.pump();
      await pumpUntil(
        tester,
        () => bodyHeight(tester) <= heightTolerance,
        maxFrames: maxFramesToCollapse,
        reason: '前提: 思考の本文が畳まれない',
      );
      // 返答が出終わるまで進める。
      await pumpFrames(tester, fastForwardBudget + fadeDuration + frameInterval * 4);

      expect(controller.isComplete, isTrue, reason: '前提: 受信完了している');

      await tester.tap(find.byKey(Keys.thinkingFrameHead));
      await pumpFrames(tester, collapseDuration + frameInterval * 2);

      final textHeight = thinkingTextHeight(tester);
      expect(
        textHeight,
        greaterThan(heightTolerance),
        reason: '前提: 届いた思考の文に高さがある',
      );
      expect(
        bodyHeight(tester),
        closeTo(textHeight, heightTolerance),
        reason: '受信完了後でも、畳まれた本文をタップすると全部開く',
      );
      expectNoArrow(tester);

      await tester.tap(find.byKey(Keys.thinkingFrameHead));
      await pumpFrames(tester, collapseDuration + frameInterval * 2);

      expect(
        bodyHeight(tester),
        closeTo(0, heightTolerance),
        reason: 'もう一度タップすると畳まれる',
      );
    },
  );

  testWidgets(
    'AC-19 思考の塊が 1 つも届かずに返答が始まると、思考の枠は出ず、吹き出しに返答の文字が流れる',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);

      controller.addChunk(const Chunk(replyText));
      await tester.pump();

      expect(
        find.byKey(Keys.thinkingFrame),
        findsNothing,
        reason: '思考の塊が 1 つも届いていないので思考の枠は出ない',
      );
      expect(find.byKey(Keys.replyBubble), findsOneWidget, reason: '返答の吹き出しが居る');
      expect(
        find.byKey(Keys.waitingDots),
        findsNothing,
        reason: '返答の最初の塊が届いたら待機の点は居なくなる',
      );

      await pumpFrames(tester, revealInterval * 2);
      final replyChars = revealedCharCount(tester, Keys.replyText);
      expect(replyChars, greaterThan(0), reason: '返答の文字が吹き出しに出る');

      await pumpFrames(tester, revealInterval * 4);
      expect(
        revealedCharCount(tester, Keys.replyText),
        greaterThan(replyChars),
        reason: '畳みを待たずに返答が流れる',
      );
      expect(
        replyText.startsWith(visibleText(tester, within: find.byKey(Keys.replyText))),
        isTrue,
        reason: '見えているのは返答の先頭からの続き',
      );
    },
  );

  testWidgets(
    'AC-21 思考だけ届いて受信完了すると、思考の残りを早送りして「2 秒考えました」に畳まれ、返答の吹き出しは出ない',
    (tester) async {
      final controller = StreamingReplyController();
      await pumpStreamingReply(tester, controller);
      final feed = _ThinkingFeed(controller, thinkingText);

      // 思考の最初の塊から 125 フレーム (2 秒) 進めてから受信完了するので、n = 2。
      await pumpFeeding(tester, feed, elapsedToReply);
      while (feed.hasMore) {
        feed.sendNext();
      }
      expect(
        controller.thinking.pendingCount,
        greaterThan(0),
        reason: 'テストの前提: 受信完了の時点で思考にまだ未出現の残りがある '
            '(93 文字を 12 文字ずつ届けているので 2 秒時点では出し切っていない)。'
            'ここが崩れていたらテストの組み立ての問題',
      );

      controller.complete();
      await tester.pump();

      await pumpUntil(
        tester,
        () => bodyHeight(tester) <= heightTolerance,
        maxFrames: maxFramesToCollapse,
        reason: '思考の本文が畳まれない (高さ 0 にならない)',
      );

      expect(
        headTitle(tester),
        '$thinkingSeconds 秒考えました',
        reason: 'n は思考の最初の塊から受信完了までの秒数 (2 秒)',
      );
      expect(
        visibleText(tester, within: find.byKey(Keys.thinkingText)),
        thinkingText,
        reason: '受信完了で思考の残りを早送りして出し切る',
      );
      expect(
        controller.thinking.pendingCount,
        0,
        reason: '早送りで未出現の残りが無くなる',
      );
      expect(
        find.byKey(Keys.replyBubble),
        findsNothing,
        reason: '返答が 1 文字も届いていないので吹き出しは出ない',
      );
      expect(find.byKey(Keys.waitingDots), findsNothing);
    },
  );
}
