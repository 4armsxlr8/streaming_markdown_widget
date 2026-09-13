import 'package:flutter/material.dart';

import 'reveal_clock.dart' show RevealClock;
import 'streaming_reply_controller.dart' show StreamingReplyController;

/// 返答の Markdown の見た目の基準値。
///
/// mock.html の確定案 (`#variant=F`) の `.demo-md` 系 CSS (共通部分。案ごとに
/// 違うのは新しく届いた部分の現れ方だけ) から転記する。フォントはプラット
/// フォームの既定 (iOS/Android) に任せ、等幅だけ明示で指定する。
abstract final class ReplyTheme {
  // ── 色 (.demo-chat / .demo-md-*) ──

  /// 本文の文字色。
  static const Color textColor = Color(0xFF1D2026);

  /// リンクの文字色。
  static const Color linkColor = Color(0xFF2F62C9);

  /// インラインコードの地の色。
  static const Color inlineCodeBackground = Color(0xFFEFF0F3);

  /// インラインコードの文字色。
  static const Color inlineCodeTextColor = Color(0xFF2C3340);

  /// コードブロックの地の色。
  static const Color codeBlockBackground = Color(0xFF23272F);

  /// コードブロックの文字色。
  static const Color codeBlockTextColor = Color(0xFFE3E8F0);

  /// 引用の左罫線の色。
  static const Color quoteBorderColor = Color(0xFFD6D9E0);

  /// 引用の文字色。
  static const Color quoteTextColor = Color(0xFF5B6069);

  /// 表の罫線の色。
  static const Color tableBorderColor = Color(0xFFE1E3E8);

  /// 表の見出し行の地の色。
  static const Color tableHeaderBackground = Color(0xFFF4F5F8);

  /// 思考の文の色。
  static const Color thinkingTextColor = Color(0xFF8B9099);

  /// 思考の枠の左罫線の色。
  static const Color thinkingFrameBorderColor = Color(0xFFD7DAE0);

  /// 見出し行の光の地の色 (`.demo-shimmer` のグラデーションの大部分)。
  static const Color thinkingShimmerBaseColor = Color(0xFFA9AEB6);

  /// 見出し行の光がいま通っている部分の色。
  static const Color thinkingShimmerHighlightColor = Color(0xFF3F4650);

  /// 待機の点の色。
  static const Color waitingDotColor = Color(0xFFB4B9C1);

  /// 返答の吹き出しの地の色。
  static const Color replyBubbleBackground = Color(0xFFFFFFFF);

  // ── 出現 ──

  /// 1 文字の不透明度が 0 から 1 になるまでの時間
  /// (調整パネルの `fadeDuration` の最終値 = `--demo-fade` の既定値。
  /// 値の正本は [RevealClock.defaultFade])。
  static const Duration fadeDuration = RevealClock.defaultFade;

  // ── 等幅フォント (インラインコード・コードブロック) ──

  static const String monospaceFontFamily = 'Menlo';

  static const List<String> monospaceFontFamilyFallback = [
    'SFMono-Regular',
    'Consolas',
    'monospace',
  ];

  // ── 間隔 ──

  /// 段落・箇条書き・番号リスト・コードブロック・表・引用の下余白
  /// (`.demo-md-p` 等の `margin-bottom`)。
  static const double blockSpacing = 11;

  /// 2 段目見出しの下余白。
  static const double h2SpacingBottom = 9;

  /// 3 段目見出しの下余白。
  static const double h3SpacingBottom = 7;

  /// 箇条書き・番号リストの項目同士の間隔 (`.demo-md-li` の `margin-bottom`)。
  static const double listItemSpacing = 3;

  /// 箇条書き・番号リストの字下げ (`padding-left: 1.4em`。本文 14px の 1.4 倍)。
  static const double listIndent = 19.6;

  // ── 段落・見出し ──

  static const double bodyFontSize = 14;

  /// 本文の行間 (line-height 比)。
  static const double bodyHeight = 1.75;

  static const double h2FontSize = 16;
  static const double h3FontSize = 14.5;

  /// 見出しの行間 (line-height 比)。
  static const double headingHeight = 1.55;

  // ── インラインコード ──
  //
  // 背景色のみ (`inlineCodeTextStyle` の `backgroundColor`)。余白・角丸は
  // 1 文字 1 TextSpan の背景では出せないため定数を持たない。

  static const double inlineCodeFontSize = 12.5;

  // ── コードブロック ──

  static const double codeBlockFontSize = 12;

  /// コードブロックの行間 (line-height 比)。
  static const double codeBlockHeight = 1.62;
  static const double codeBlockBorderRadius = 8;
  static const EdgeInsets codeBlockPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );

  // ── 表 ──

  static const double tableFontSize = 12.5;

  /// 表の行間 (line-height 比)。
  static const double tableHeight = 1.55;
  static const double tableBorderWidth = 1;
  static const EdgeInsets tableCellPadding = EdgeInsets.symmetric(
    horizontal: 9,
    vertical: 5,
  );

  // ── 引用 ──

  static const double quoteBorderWidth = 3;

  /// 引用の左罫線から文字までの余白 (`padding: 2px 0 2px 11px` の左)。
  static const double quoteIndent = 11;

  // ── 思考 (`.demo-md--think`) ──

  static const double thinkingFontSize = 12.5;

  /// 思考の文の行間 (line-height 比)。
  static const double thinkingHeight = 1.7;

  // ── 思考の枠 (`.demo-think`) ──

  /// 見出し行の文字サイズ (`.demo-think-head`)。
  static const double thinkingHeadFontSize = 12;

  /// 左罫線の太さ。
  static const double thinkingFrameBorderWidth = 2;

  /// 左罫線から中身までの余白 (`padding-left`)。
  static const double thinkingFrameIndent = 10;

  /// 思考の枠と下に続く返答の吹き出しとの間隔 (`margin-bottom`)。
  static const double thinkingFrameSpacingBottom = 10;

  /// 本文の高さが 1 行 ⇄ 全部 ⇄ 畳みの間で変わる時間 (`AnimatedSize`。値の正本は
  /// [StreamingReplyController.collapseDuration])。
  static const Duration thinkingCollapseDuration = StreamingReplyController.collapseDuration;

  /// 見出し行の光が 1 周するのにかかる時間。
  static const Duration thinkingShimmerDuration = Duration(milliseconds: 1600);

  // ── 待機の点 (`.demo-wait-dot`) ──

  static const double waitingDotDiameter = 7;
  static const double waitingDotGap = 5;

  /// 点を並べる行の高さ。
  static const double waitingDotsHeight = 20;

  /// 1 つの点が不透明度の谷から山、また谷に戻るまでの周期。
  static const Duration waitingDotDuration = Duration(milliseconds: 1400);

  /// 2 つ目・3 つ目の点が 1 つ目より遅れて始まる時間。
  static const Duration waitingDotStagger = Duration(milliseconds: 200);

  static const double waitingDotMinOpacity = 0.22;
  static const double waitingDotMaxOpacity = 0.9;

  // ── 返答の吹き出し (`.demo-bubble-ai`) ──

  static const EdgeInsets replyBubblePadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  );

  static const double replyBubbleMinHeight = 44;

  static const BorderRadius replyBubbleBorderRadius = BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(16),
    bottomRight: Radius.circular(16),
    bottomLeft: Radius.circular(4),
  );

  static const BoxShadow replyBubbleShadow = BoxShadow(
    color: Color(0x0D000000),
    offset: Offset(0, 1),
    blurRadius: 2,
  );

  // ── 画面の地 (`.demo-chat`) ──

  /// 画面の背景色。
  static const Color pageBackground = Color(0xFFF1F2F4);

  /// 画面の余白 (`padding: 16px 12px 28px`)。
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(12, 16, 12, 28);

  /// 自動追随: 読んでいる位置がこの距離 (px) 以内なら末尾へ追随する
  /// (mock.html の `stick()` と同じ値)。
  static const double autoFollowDistance = 72.0;

  // ── 「最初から流す」ボタン (`.demo-actions` / `.demo-replay`) ──

  /// 返答の吹き出しとボタンの間隔 (`.demo-actions` の `margin: 8px 0 0`)。
  static const double actionsSpacingTop = 8;

  static const Color replayButtonBackground = Color(0xFFFFFFFF);
  static const Color replayButtonBorderColor = Color(0xFFD2D5DB);
  static const double replayButtonBorderWidth = 1;

  /// ボタンの角丸 (`border-radius: 999px` = 完全な丸みの pill 形)。
  static const double replayButtonBorderRadius = 999;

  static const Color replayButtonTextColor = Color(0xFF4A4F58);
  static const double replayButtonFontSize = 11.5;

  /// ボタンの文字の行間 (line-height 比)。
  static const double replayButtonHeight = 1.4;

  static const EdgeInsets replayButtonPadding = EdgeInsets.symmetric(
    horizontal: 11,
    vertical: 5,
  );

  // ── 作り物の供給 (`cz-mock-script` の供給ループと同じ値) ──

  /// 塊が届く基準の間隔 (`tokensPerSecond` 8 = 1000ms / 8)。実際の間隔は
  /// これに [supplyIntervalJitterMin]〜[supplyIntervalJitterMax] のむらを
  /// 掛ける。
  static const Duration supplyBaseInterval = Duration(milliseconds: 125);

  static const double supplyIntervalJitterMin = 0.5;
  static const double supplyIntervalJitterMax = 2.0;

  /// 1 塊の基準の文字数 (`charsPerToken` 4)。
  static const int supplyChunkChars = 4;

  /// この回数に 1 回、塊を [supplyLongChunkMultiplier] 倍の大きさにして
  /// むらを作る。
  static const int supplyLongChunkEvery = 5;
  static const int supplyLongChunkMultiplier = 2;

  // ── TextStyle ──

  static const TextStyle bodyTextStyle = TextStyle(
    color: textColor,
    fontSize: bodyFontSize,
    height: bodyHeight,
  );

  static const TextStyle h2TextStyle = TextStyle(
    color: textColor,
    fontSize: h2FontSize,
    height: headingHeight,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle h3TextStyle = TextStyle(
    color: textColor,
    fontSize: h3FontSize,
    height: headingHeight,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle inlineCodeTextStyle = TextStyle(
    color: inlineCodeTextColor,
    fontSize: inlineCodeFontSize,
    fontFamily: monospaceFontFamily,
    fontFamilyFallback: monospaceFontFamilyFallback,
    backgroundColor: inlineCodeBackground,
  );

  static const TextStyle codeBlockTextStyle = TextStyle(
    color: codeBlockTextColor,
    fontSize: codeBlockFontSize,
    height: codeBlockHeight,
    fontFamily: monospaceFontFamily,
    fontFamilyFallback: monospaceFontFamilyFallback,
  );

  static const TextStyle tableTextStyle = TextStyle(
    color: textColor,
    fontSize: tableFontSize,
    height: tableHeight,
  );

  static const TextStyle tableHeaderTextStyle = TextStyle(
    color: textColor,
    fontSize: tableFontSize,
    height: tableHeight,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle thinkingTextStyle = TextStyle(
    color: thinkingTextColor,
    fontSize: thinkingFontSize,
    height: thinkingHeight,
  );

  static const TextStyle thinkingHeadTextStyle = TextStyle(
    color: thinkingTextColor,
    fontSize: thinkingHeadFontSize,
    height: thinkingHeight,
  );

  static const TextStyle replayButtonTextStyle = TextStyle(
    color: replayButtonTextColor,
    fontSize: replayButtonFontSize,
    height: replayButtonHeight,
  );
}
