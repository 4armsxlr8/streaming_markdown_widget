import 'package:flutter/widgets.dart';

/// Keys for tests and manual checks to find widgets by.
abstract final class Keys {
  /// The thinking frame.
  static const thinkingFrame = ValueKey('thinking-frame');

  /// The thinking frame's headline row (tap to toggle line ⇄ full / collapsed ⇄ full).
  static const thinkingFrameHead = ValueKey('thinking-frame-head');

  /// The headline text ("Thinking…" / "Thought for n seconds").
  static const thinkingFrameTitle = ValueKey('thinking-frame-title');

  /// The thinking frame's body box (height varies between one line / full / 0).
  static const thinkingFrameBody = ValueKey('thinking-frame-body');

  /// The thinking text itself.
  static const thinkingText = ValueKey('thinking-text');

  /// The reply's characters.
  static const replyText = ValueKey('reply-text');

  /// The 3 waiting dots shown in the reply bubble before anything is received.
  static const waitingDots = ValueKey('waiting-dots');
}
