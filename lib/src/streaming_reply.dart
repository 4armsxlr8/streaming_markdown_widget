import 'package:flutter/widgets.dart';

import 'keys.dart';
import 'reveal_ticker.dart';
import 'revealed_markdown.dart';
import 'streaming_reply_controller.dart';
import 'streaming_reply_style.dart';
import 'thinking_frame.dart';
import 'waiting_dots.dart';

/// The reply widget: thinking frame + reply bubble.
///
/// Wraps itself in a `RevealTicker` and listens to [StreamingReplyController]
/// directly, stacking [ThinkingFrame] above the reply bubble. Before
/// anything is received, shows a white rounded bubble with 3 waiting dots
/// ([WaitingDots]). Once thinking chunks start arriving, replaces the bubble
/// with [ThinkingFrame]; once the reply's first chunk arrives (without
/// waiting for the thinking frame to collapse), shows the bubble. If no
/// thinking chunk ever arrives, no frame is shown and the bubble simply
/// appears on the reply's first chunk.
class StreamingReply extends StatelessWidget {
  const StreamingReply({
    super.key,
    required this.controller,
    this.style,
    this.thinkingTitle = '…',
    this.thoughtForSeconds,
  });

  /// The entry point for reveal state and thinking frame state.
  final StreamingReplyController controller;

  /// Look-and-feel values (default if omitted). Passed down to
  /// [ThinkingFrame], [RevealedMarkdown], and [WaitingDots] via an
  /// InheritedWidget ([StreamingReplyStyleScope]).
  final StreamingReplyStyle? style;

  /// Passed straight through to [ThinkingFrame.thinkingTitle].
  final String thinkingTitle;

  /// Passed straight through to [ThinkingFrame.thoughtForSeconds].
  final String Function(int seconds)? thoughtForSeconds;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? StreamingReplyStyleScope.of(context);
    return StreamingReplyStyleScope(
      style: effectiveStyle,
      child: RevealTicker(
        controller: controller,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final showThinkingFrame =
                controller.thinkingFrame != ThinkingFrameState.none;
            final hasReply = controller.reply.receivedCount > 0;
            final showBody = !showThinkingFrame || hasReply;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showThinkingFrame)
                  ThinkingFrame(
                    controller: controller,
                    thinkingTitle: thinkingTitle,
                    thoughtForSeconds: thoughtForSeconds,
                  ),
                if (showThinkingFrame && showBody)
                  SizedBox(height: effectiveStyle.thinkingFrameSpacingBottom),
                if (showBody)
                  hasReply
                      ? RevealedMarkdown(
                          key: Keys.replyText,
                          controller: controller,
                          kind: ChunkKind.reply,
                        )
                      : const WaitingDots(key: Keys.waitingDots),
              ],
            );
          },
        ),
      ),
    );
  }
}
