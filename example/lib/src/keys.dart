import 'package:flutter/widgets.dart';

/// Keys for tests and manual checks (sample screen only).
abstract final class Keys {
  /// The AppBar's replay icon.
  static const replayButton = ValueKey('replay-button');

  /// The AppBar's API key icon.
  static const apiKeyButton = ValueKey('api-key-button');

  /// The screen's vertical scroll view.
  static const replyScroll = ValueKey('reply-scroll');

  /// The bottom-fixed question input field.
  static const questionField = ValueKey('question-field');

  /// The input bar's send button.
  static const sendButton = ValueKey('send-button');
}
