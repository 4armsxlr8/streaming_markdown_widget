import 'package:flutter/widgets.dart';

/// テストや動作確認から辿るためのキー。
abstract final class Keys {
  /// 思考の枠。
  static const thinkingFrame = ValueKey('thinking-frame');

  /// 思考の枠の見出し行 (タップで 1 行 ⇄ 全部 / 畳み ⇄ 全部)。
  static const thinkingFrameHead = ValueKey('thinking-frame-head');

  /// 見出し行の文言 (「考え中…」/「n 秒考えました」)。
  static const thinkingFrameTitle = ValueKey('thinking-frame-title');

  /// 思考の枠の本文の箱 (高さが 1 行 / 全部 / 0 の間で変わる)。
  static const thinkingFrameBody = ValueKey('thinking-frame-body');

  /// 思考の文そのもの。
  static const thinkingText = ValueKey('thinking-text');

  /// 返答の吹き出し。
  static const replyBubble = ValueKey('reply-bubble');

  /// 返答の文字。
  static const replyText = ValueKey('reply-text');

  /// 受信前に吹き出しへ出す待機の点 3 つ。
  static const waitingDots = ValueKey('waiting-dots');

  /// 「最初から流す」ボタン。
  static const replayButton = ValueKey('replay-button');

  /// 画面全体の縦スクロール (自動追随の対象)。
  static const replyScroll = ValueKey('reply-scroll');
}
